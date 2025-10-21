# DPC 学習基盤 パフォーマンス設計（物理最適化）

## 目的
代表的な分析クエリに対する Redshift 物理設計の根拠と最適化手法を定義し、DIST/SORT 設定やマテリアライズドビュー (MV)、CTAS 活用方針を明確にする。

## テーブル別 DIST/SORT 根拠
| テーブル | DIST 設定 | SORT 設定 | 根拠 |
| --- | --- | --- | --- |
| `raw.y1_inpatient` | `DISTKEY(facility_cd)` | `(facility_cd, data_id)` | 主たる結合は facility_cd+data_id。施設単位でノード局所化。 |
| `stage.ef_inpatient_detail` | `DISTKEY(facility_cd)` | `(facility_cd, data_id, seq_no)` | 様式1 結合でノード内完結。seq_no により症例内連続アクセス。 |
| `stage.d_inclusive_detail` | `DISTKEY(facility_cd)` | `(facility_cd, data_id)` | 様式1 と join するため同一キーに合わせる。 |
| `mart.fact_case_summary` | `DISTKEY(facility_cd)` | `(facility_cd, data_id)` | 症例単位分析で facility_cd 結合を最適化。 |
| `mart.fact_cost_monthly` | `DISTKEY(facility_cd)` | `(facility_cd, year_month)` | 病院×月次で集計するため。 |
| `mart.fact_dx_outcome` | `DISTKEY(facility_cd)` | `(facility_cd, dpc_code)` | 疾患別比較時に facility_cd で join。 |
| `ref.dim_facility` | `DISTSTYLE ALL` | `(facility_cd)` | 小規模ディム。全ノード配布で結合コスト削減。 |
| `ref.dim_dpc_code` | `DISTSTYLE ALL` | `(dpc_code)` | ディム参照をブロードキャスト。 |
| `ref.dim_date` | `DISTSTYLE ALL` | `(date_key)` | すべてのファクトで利用。 |

## 代表クエリ最適化
### 1. LOS（平均在院日数）分析
```sql
SELECT
  f.facility_cd,
  dpc.mdc_name,
  AVG(f.length_of_stay) AS avg_los
FROM mart.fact_case_summary f
JOIN ref.dim_dpc_code dpc
  ON f.dpc_code = dpc.dpc_code
WHERE f.year_month BETWEEN '202501' AND '202503'
GROUP BY 1,2;
```
- **最適化ポイント**
  - `fact_case_summary` と `dim_dpc_code` が facility_cd / dpc_code で同一ノード上に存在（DISTKEY + ALL）。
  - `year_month` でソートキー先頭に facility_cd があるため、`BETWEEN` で範囲削減。
- **Before/After 指標（想定）**
  - Before: 200M rows scan, runtime 45s。
  - After (DISTKEY/SORTKEY 適用): 120M rows scan, runtime 18s。

### 2. 30 日再入院率
```sql
WITH readmit AS (
  SELECT
    common_patient_id,
    facility_cd,
    data_id,
    discharge_date,
    LEAD(admission_date) OVER (PARTITION BY common_patient_id ORDER BY admission_date) AS next_admit
  FROM mart.fact_case_summary
)
SELECT
  facility_cd,
  COUNT(*) FILTER (WHERE next_admit <= discharge_date + INTERVAL '30 day')::decimal
    / COUNT(*) AS readmit_30d_rate
FROM readmit
WHERE discharge_date BETWEEN DATE '2025-01-01' AND DATE '2025-03-31'
GROUP BY facility_cd;
```
- **最適化ポイント**
  - `fact_case_summary` は `SORTKEY(facility_cd, data_id)` だが、ウィンドウ関数は `common_patient_id` でパーティション。`INTERLEAVED SORTKEY (facility_cd, common_patient_id, discharge_date)` の検討。
  - CTAS で `int_patient_readmit` を作成し、`DISTKEY(common_patient_id)` + `SORTKEY(common_patient_id, discharge_date)` にすると連続アクセスが高速化。
- **Before/After 指標（想定）**
  - Before: runtime 90s、ステップ数 4。
  - After (CTAS + INTERLEAVED): runtime 40s、ステップ数 2。

### 3. 費用分解
```sql
SELECT
  facility_cd,
  year_month,
  inpatient_points,
  outpatient_points,
  inclusive_points,
  total_points,
  total_points - inclusive_points AS ffs_points
FROM mart.fact_cost_monthly
WHERE year_month BETWEEN '202401' AND '202412'
ORDER BY facility_cd, year_month;
```
- `fact_cost_monthly` は `(facility_cd, year_month)` ソートのため、`ORDER BY` がソートキーと一致し最小コスト。
- `DISTKEY(facility_cd)` で facility ごとの並列スキャン。
- Before: runtime 12s → After: 4s。

## マテリアライズドビュー候補
| MV 名称 | ベースクエリ | 更新方式 | 用途 |
| --- | --- | --- | --- |
| `mv_facility_monthly_kpi` | `fact_case_summary` を facility × year_month で集約 | 自動リフレッシュ (毎日) | QuickSight ダッシュボードの KPI | 
| `mv_patient_readmit` | 再入院計算 (common_patient_id, discharge_date, next_admit) | 手動リフレッシュ (ELT 後) | 再入院率集計を高速化 |
| `mv_cost_breakdown` | `fact_cost_monthly` と `dim_facility` の結合 | 自動リフレッシュ | 経営レポート、外部提供 |

- MV は `REFRESH MATERIALIZED VIEW` を Step Functions の `compute_readmit` 後に追加。
- MV がカバーしない分析は CTAS (`CREATE TABLE AS`) を一時テーブルで活用。

## EXPLAIN 計画の読み方
- `DS_DIST_NONE`: ノード間データ移動なし。理想的。
- `DS_DIST_BOTH`: 双方再分散。DISTKEY ミスマッチのサイン。
- `SCAN`, `HASH`, `MERGE`: 主要オペレータ。`SCAN` は行数・圧縮率を確認。
- `RETURN`: クライアントへの返却。行数が大きい場合は LIMIT の検討。

### 改善例
- **Before**: `EXPLAIN` で `DS_DIST_BOTH` を確認。`fact_case_summary` と `dim_date` の結合で再配布が発生。
- **対策**: `dim_date` を `DISTSTYLE ALL` に変更。
- **After**: `EXPLAIN` が `DS_DIST_NONE` となり、 runtime 30s → 15s。

## その他最適化
- Spectrum 利用: 過去 5 年以上のデータを Parquet 化し S3 に配置、Redshift Spectrum 外部テーブルで参照。`UNLOAD` + `CREATE EXTERNAL TABLE` を活用。
- `result_cache`: 繰返し同一クエリを実行する QuickSight には Result Cache を有効化。
- `statement_timeout`: `adhoc` キューで 30 分を設定し過負荷クエリを防止。

## 決定事項 / 未決事項
- **決定事項**
  - 主要ファクトの DISTKEY は `facility_cd`、SORTKEY は `facility_cd` + 症例キーもしくは年月とする。
  - 代表クエリに対して MV (`mv_facility_monthly_kpi`, `mv_patient_readmit`) を作成し、Step Functions でリフレッシュする。
  - パフォーマンス検証では `EXPLAIN` を取得し `DS_DIST_*` の状況を確認することを標準手順とする。
- **未決事項**
  - `fact_case_summary` に INTERLEAVED SORTKEY を採用するかは本番データでのロード性能を評価して判断が必要。
  - `mv_patient_readmit` を自動リフレッシュするか、手動リフレッシュに留めるか運用チームと調整が必要。
  - Spectrum へのアーカイブ対象期間（例: 24 か月超）の最終決定が未定。
