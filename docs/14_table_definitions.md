# テーブル定義書（DPC 学習基盤）

本書は DPC データ学習基盤で作成・管理する各スキーマのテーブル定義を整理したものです。物理 DDL（`docs/05_physical_ddl.md`、`ddl/core/*.sql`）の内容をもとに、テーブル目的・主キー・分散/ソートキー・主要カラム仕様を記載します。

## raw スキーマ

### raw.y1_inpatient（様式1 退院患者票）
- **目的**: 様式1（退院患者調査票）の原本データを保持する。
- **主キー**: `(facility_cd, data_id)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード（施設識別子）。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID（レコード識別子）。 |
| admission_date | DATE | NULL | 入院日。 |
| discharge_date | DATE | NULL | 退院日。 |
| sex_code | CHAR(1) | NULL | 性別コード。 |
| birth_date | DATE | NULL | 生年月日。 |
| age | SMALLINT | NULL | 入院時年齢。 |
| dpc_code | CHAR(14) | NULL | DPC コード。 |
| main_icd10 | VARCHAR(10) | NULL | 主傷病 ICD10 コード。 |
| outcome_code | CHAR(2) | NULL | 転帰コード。 |
| emergency_flag | CHAR(1) | NULL | 救急搬送フラグ。 |
| surgery_flag | CHAR(1) | NULL | 手術実施フラグ。 |
| height_cm | DECIMAL(5,2) | NULL | 身長（cm）。 |
| weight_kg | DECIMAL(5,2) | NULL | 体重（kg）。 |
| created_at | TIMESTAMP | NULL | レコード作成日時（ロード時刻）。 |

### raw.y3_facility（様式3 施設情報）
- **目的**: 様式3で提供される医療機関属性を保持する。
- **主キー**: `(facility_cd, report_year)`
- **DIST/SORT KEY**: `DISTSTYLE ALL`, `SORTKEY(facility_cd)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| report_year | CHAR(4) | NOT NULL | 報告年度（西暦 YYYY）。 |
| facility_name | VARCHAR(120) | NULL | 医療機関名称。 |
| bed_function_code | CHAR(2) | NULL | 病床機能区分コード。 |
| hospital_group | VARCHAR(40) | NULL | 法人/グループ名称。 |
| pref_code | CHAR(2) | NULL | 都道府県コード。 |
| city_code | CHAR(5) | NULL | 市区町村コード。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.y4_noncovered（様式4 非保険症例）
- **目的**: 様式4に基づく非保険診療の記録を保持する。
- **主キー**: `(facility_cd, data_id)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| noncovered_reason | CHAR(2) | NULL | 非保険となった理由コード。 |
| noncovered_amount | INTEGER | NULL | 非保険点数または金額。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.ef_inpatient（EF 入院明細）
- **目的**: EF ファイル（入院）による診療明細を保持する。
- **主キー**: `(facility_cd, data_id, seq_no, detail_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id, seq_no)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| seq_no | INTEGER | NOT NULL | 明細シーケンス番号。 |
| detail_no | INTEGER | NOT NULL | 明細枝番。 |
| service_date | DATE | NULL | 診療実施日。 |
| service_code | VARCHAR(12) | NULL | 診療行為コード。 |
| unit_code | VARCHAR(3) | NULL | 単位コード。 |
| qty | DECIMAL(10,3) | NULL | 数量。 |
| points | INTEGER | NULL | 点数。 |
| yen_flag | CHAR(1) | NULL | 円換算フラグ。 |
| doctor_code | VARCHAR(10) | NULL | 担当医コード。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.ef_outpatient（EF 外来明細）
- **目的**: EF ファイル（外来）の診療明細を保持する。
- **主キー**: `(facility_cd, data_id, seq_no, detail_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id, seq_no)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| seq_no | INTEGER | NOT NULL | 明細シーケンス番号。 |
| detail_no | INTEGER | NOT NULL | 明細枝番。 |
| visit_date | DATE | NULL | 来院日。 |
| service_code | VARCHAR(12) | NULL | 診療行為コード。 |
| qty | DECIMAL(10,3) | NULL | 数量。 |
| points | INTEGER | NULL | 点数。 |
| yen_flag | CHAR(1) | NULL | 円換算フラグ。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.d_inclusive（包括評価 D ファイル）
- **目的**: 包括評価（D ファイル）のセグメント情報を保持する。
- **主キー**: `(facility_cd, data_id, segment_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| segment_no | SMALLINT | NOT NULL | 包括セグメント番号。 |
| dpc_code | CHAR(14) | NULL | 包括対象の DPC コード。 |
| start_date | DATE | NULL | セグメント開始日。 |
| end_date | DATE | NULL | セグメント終了日。 |
| inclusive_points | INTEGER | NULL | 包括点数。 |
| adjust_points | INTEGER | NULL | 調整点数。 |
| reason_code | CHAR(2) | NULL | 調整理由コード。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.h_daily（日次重症度 H ファイル）
- **目的**: H ファイル（日次重症度評価）の原本データを保持する。
- **主キー**: `(facility_cd, data_id, eval_date, seq_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id, eval_date)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| eval_date | DATE | NOT NULL | 評価日。 |
| seq_no | SMALLINT | NOT NULL | 項目シーケンス番号。 |
| item_code | VARCHAR(6) | NULL | 評価項目コード。 |
| severity_score | SMALLINT | NULL | 重症度スコア。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### raw.k_common_id（共通患者 ID）
- **目的**: 共通患者 ID 紐付け情報を保持する。
- **主キー**: `(facility_cd, data_id)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| common_patient_id | VARCHAR(40) | NOT NULL | 共通患者 ID。 |
| birth_month | DATE | NULL | 生年月（1 日固定）。 |
| insurer_no | VARCHAR(8) | NULL | 保険者番号。 |
| subscriber_no | VARCHAR(8) | NULL | 被保険者証番号。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

## stage スキーマ

### stage.y1_case（様式1 クレンジング）
- **目的**: 様式1 原本をクレンジングし派生列を付与した症例テーブル。
- **主キー**: `(facility_cd, data_id)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| admission_date | DATE | NULL | 入院日。 |
| discharge_date | DATE | NULL | 退院日。 |
| length_of_stay | INTEGER | NULL | 在院日数（退院日-入院日）。 |
| patient_sex | CHAR(1) | NULL | 性別コード。 |
| birth_date | DATE | NULL | 生年月日。 |
| age | SMALLINT | NULL | 入院時年齢。 |
| dpc_code | CHAR(14) | NULL | DPC コード。 |
| main_icd10 | VARCHAR(10) | NULL | 主傷病 ICD10。 |
| surgery_flag | CHAR(1) | NULL | 手術実施フラグ。 |
| emergency_flag | CHAR(1) | NULL | 救急搬送フラグ。 |
| outcome_code | CHAR(2) | NULL | 転帰コード。 |
| insurance_type | VARCHAR(4) | NULL | 保険種別コード。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### stage.ef_inpatient_detail（入院明細統合）
- **目的**: EF 入院明細をマスター突合・集約した派生テーブル。
- **主キー**: `(facility_cd, data_id, seq_no, detail_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id, seq_no)`
- **外部キー想定**: `(facility_cd, data_id)` → `stage.y1_case`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| seq_no | INTEGER | NOT NULL | 明細シーケンス番号。 |
| detail_no | INTEGER | NOT NULL | 明細枝番。 |
| service_date | DATE | NULL | 診療実施日。 |
| master_code | VARCHAR(12) | NULL | 統合マスターコード。 |
| category_code | VARCHAR(4) | NULL | カテゴリコード。 |
| unit_code | VARCHAR(3) | NULL | 単位コード。 |
| qty | DECIMAL(12,3) | NULL | 明細数量。 |
| order_count | DECIMAL(12,3) | NULL | オーダー回数。 |
| total_qty | DECIMAL(12,3) | NULL | 数量×回数の合計。 |
| points | INTEGER | NULL | 点数。 |
| yen_flag | CHAR(1) | NULL | 円換算フラグ。 |
| points_yen | DECIMAL(12,2) | NULL | 点数換算額（円）。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### stage.d_inclusive_detail（包括評価集約）
- **目的**: 包括評価セグメントを集約し派生指標を付与したテーブル。
- **主キー**: `(facility_cd, data_id, segment_no)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| segment_no | SMALLINT | NOT NULL | 包括セグメント番号。 |
| dpc_code | CHAR(14) | NULL | DPC コード。 |
| inclusive_points | INTEGER | NULL | 包括点数。 |
| adjust_points | INTEGER | NULL | 調整点数。 |
| reason_code | CHAR(2) | NULL | 調整理由コード。 |
| bundle_days | INTEGER | NULL | 包括対象日数。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### stage.h_daily_score（日次重症度集約）
- **目的**: H ファイルの重症度スコアを日次集約し acuity 指標を付与したテーブル。
- **主キー**: `(facility_cd, data_id, eval_date)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id, eval_date)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| eval_date | DATE | NOT NULL | 評価日。 |
| severity_score | SMALLINT | NULL | 日次重症度スコア。 |
| acuity_flag | BOOLEAN | NULL | 高重症度フラグ。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### stage.patient_dim_seed（患者ディメンション種表）
- **目的**: 共通患者 ID を起点とした患者ディメンション候補データを保持する。
- **主キー**: `(common_patient_id, facility_cd, data_id)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| common_patient_id | VARCHAR(40) | NOT NULL | 共通患者 ID。 |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| birth_month | DATE | NULL | 生年月（1 日固定）。 |
| sex_code | CHAR(1) | NULL | 性別コード。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

## mart スキーマ

### mart.fact_case_summary（症例サマリファクト）
- **目的**: 症例単位の主要指標を集約し、分析クエリの中心となるファクトテーブル。
- **主キー**: `(facility_cd, data_id)`（サロゲートキー `case_sk` あり）
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, data_id)`
- **外部キー想定**: `facility_cd` → `ref.dim_facility`、`dpc_code` → `ref.dim_dpc_code`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| case_sk | BIGINT IDENTITY | NOT NULL | サロゲートキー。 |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| data_id | CHAR(10) | NOT NULL | 症例 ID。 |
| common_patient_id | VARCHAR(40) | NULL | 共通患者 ID。 |
| admission_date | DATE | NULL | 入院日。 |
| discharge_date | DATE | NULL | 退院日。 |
| length_of_stay | INTEGER | NULL | 在院日数。 |
| dpc_code | CHAR(14) | NULL | DPC コード。 |
| main_icd10 | VARCHAR(10) | NULL | 主傷病 ICD10。 |
| sex_code | CHAR(1) | NULL | 性別コード。 |
| age | SMALLINT | NULL | 入院時年齢。 |
| surgery_flag | CHAR(1) | NULL | 手術フラグ。 |
| emergency_flag | CHAR(1) | NULL | 救急搬送フラグ。 |
| outcome_code | CHAR(2) | NULL | 転帰コード。 |
| total_points | INTEGER | NULL | 請求点数合計。 |
| inclusive_points | INTEGER | NULL | 包括点数。 |
| ffs_points | INTEGER | NULL | 出来高（出来高払い）点数。 |
| noncovered_flag | BOOLEAN | NULL | 非保険診療有無。 |
| readmit_7d_flag | BOOLEAN | NULL | 7 日以内再入院フラグ。 |
| readmit_30d_flag | BOOLEAN | NULL | 30 日以内再入院フラグ。 |
| acuity_avg | DECIMAL(6,3) | NULL | 平均重症度スコア。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |
| updated_at | TIMESTAMP | NULL | 最終更新日時。 |

### mart.fact_cost_monthly（月次コストファクト）
- **目的**: 施設×年月単位の診療区分別点数を保持する。
- **主キー**: `(facility_cd, year_month)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, year_month)`
- **外部キー想定**: `facility_cd` → `ref.dim_facility`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| year_month | CHAR(6) | NOT NULL | 年月（YYYYMM）。 |
| inpatient_points | INTEGER | NULL | 入院点数。 |
| outpatient_points | INTEGER | NULL | 外来点数。 |
| inclusive_points | INTEGER | NULL | 包括点数。 |
| drug_points | INTEGER | NULL | 薬剤点数。 |
| material_points | INTEGER | NULL | 特定保険医療材料点数。 |
| surgery_points | INTEGER | NULL | 手術点数。 |
| other_points | INTEGER | NULL | その他点数。 |
| total_points | INTEGER | NULL | 点数合計。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### mart.fact_dx_outcome（疾患別アウトカムファクト）
- **目的**: 施設×年月×DPC コード単位の症例数とアウトカム指標を保持する。
- **主キー**: `(facility_cd, year_month, dpc_code)`
- **DIST/SORT KEY**: `DISTKEY(facility_cd)`, `SORTKEY(facility_cd, dpc_code)`
- **外部キー想定**: `facility_cd` → `ref.dim_facility`、`dpc_code` → `ref.dim_dpc_code`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| year_month | CHAR(6) | NOT NULL | 年月（YYYYMM）。 |
| dpc_code | CHAR(14) | NOT NULL | DPC コード。 |
| cases | INTEGER | NULL | 症例数。 |
| avg_los | DECIMAL(6,2) | NULL | 平均在院日数。 |
| mortality_rate | DECIMAL(5,2) | NULL | 死亡率（%）。 |
| readmit_30d_rate | DECIMAL(5,2) | NULL | 30 日以内再入院率（%）。 |
| avg_acuity | DECIMAL(6,3) | NULL | 平均重症度スコア。 |
| surgery_ratio | DECIMAL(5,2) | NULL | 手術実施率（%）。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

## ref スキーマ

### ref.dim_facility（施設ディメンション）
- **目的**: 医療機関マスタ情報と変遷（SCD2）を管理するディメンション。
- **主キー**: `(facility_cd, effective_from)`
- **DIST/SORT KEY**: `DISTSTYLE ALL`, `SORTKEY(facility_cd)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| facility_name | VARCHAR(120) | NULL | 医療機関名称。 |
| facility_name_kana | VARCHAR(180) | NULL | 医療機関名称（カナ）。 |
| bed_function_code | CHAR(2) | NULL | 病床機能区分コード。 |
| hospital_group | VARCHAR(40) | NULL | 法人/グループ名。 |
| pref_code | CHAR(2) | NULL | 都道府県コード。 |
| medical_region | VARCHAR(10) | NULL | 医療圏コード。 |
| dpc_category | VARCHAR(20) | NULL | DPC カテゴリ区分。 |
| coefficient_i | DECIMAL(6,4) | NULL | 基礎係数 I。 |
| coefficient_ii | DECIMAL(6,4) | NULL | 基礎係数 II。 |
| is_dpc_hospital | BOOLEAN | NULL | DPC 対象病院フラグ。 |
| effective_from | DATE | NOT NULL | 適用開始日。 |
| effective_to | DATE | NULL | 適用終了日。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### ref.dim_dpc_code（DPC コードディメンション）
- **目的**: DPC コードと関連情報を保持するディメンション。
- **主キー**: `(dpc_code)`
- **DIST/SORT KEY**: `DISTSTYLE ALL`, `SORTKEY(dpc_code)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| dpc_code | CHAR(14) | NOT NULL | DPC コード。 |
| mdc_code | CHAR(2) | NULL | MDC（診断群分類）コード。 |
| mdc_name | VARCHAR(80) | NULL | MDC 名称。 |
| diagnosis_name | VARCHAR(160) | NULL | 傷病名。 |
| surgery_category | VARCHAR(80) | NULL | 手術区分。 |
| resource_level | VARCHAR(40) | NULL | 資源投入区分。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### ref.dim_icd10（ICD10 ディメンション）
- **目的**: ICD10 コード体系のマスタ情報を保持するディメンション。
- **主キー**: `(icd10_code)`
- **DIST/SORT KEY**: `DISTSTYLE ALL`, `SORTKEY(icd10_code)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| icd10_code | VARCHAR(10) | NOT NULL | ICD10 コード。 |
| block_code | VARCHAR(4) | NULL | ブロックコード。 |
| chapter_code | VARCHAR(2) | NULL | 章コード。 |
| japanese_name | VARCHAR(255) | NULL | 和名。 |
| english_name | VARCHAR(255) | NULL | 英名。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

### ref.dim_date（日付ディメンション）
- **目的**: 日付に関する派生属性を保持するカレンダーディメンション。
- **主キー**: `(date_key)`
- **DIST/SORT KEY**: `DISTSTYLE ALL`, `SORTKEY(date_key)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| date_key | DATE | NOT NULL | 日付キー（YYYY-MM-DD）。 |
| year | SMALLINT | NULL | 年。 |
| quarter | SMALLINT | NULL | 四半期（1-4）。 |
| month | SMALLINT | NULL | 月。 |
| day | SMALLINT | NULL | 日。 |
| year_month | CHAR(6) | NULL | 年月（YYYYMM）。 |
| week | SMALLINT | NULL | 週番号。 |
| weekday | SMALLINT | NULL | 曜日番号（0=日〜）。 |
| is_holiday | BOOLEAN | NULL | 祝日フラグ。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

## dq スキーマ

### dq.results_yyyymm（データ品質チェック結果）
- **目的**: 月次データ品質チェックの結果を保持する。Slack 通知やレポートに利用。
- **主キー**: `(result_id)`（IDENTITY）
- **DIST/SORT KEY**: `DISTSTYLE AUTO`, `SORTKEY(yyyymm, rule_id)`

| カラム名 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| result_id | BIGINT IDENTITY | NOT NULL | 結果 ID（サロゲートキー）。 |
| facility_cd | CHAR(9) | NOT NULL | 医療機関コード。 |
| yyyymm | CHAR(6) | NOT NULL | 対象年月（YYYYMM）。 |
| rule_id | VARCHAR(64) | NOT NULL | ルール識別子。 |
| severity | VARCHAR(10) | NOT NULL | 重大度レベル。 |
| cnt | INTEGER | NOT NULL | 検知件数。 |
| sample_keys | VARCHAR(500) | NULL | 代表的なキー例。 |
| note | VARCHAR(500) | NULL | コメント・補足。 |
| created_at | TIMESTAMP | NULL | レコード作成日時。 |

## 参照情報
- 本定義書は `docs/05_physical_ddl.md` と `ddl/core/*.sql` の整備状況に追随させること。変更が生じた場合は本書も更新すること。
