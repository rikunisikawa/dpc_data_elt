# DPC 学習基盤 データ品質（DQ）ルール設計

## 目的
DPC 学習基盤で実施するデータ品質チェックを重大度別に整理し、SQL サンプル、結果格納テーブル、通知フローを定義する。

## チェック分類
| 重大度 | 説明 |
| --- | --- |
| 重大 (Critical) | データロード停止・再提出が必要な異常。バッチを失敗として扱う。 |
| 警告 (Warning) | 分析影響が限定的な異常。バッチは継続するが通知し調査する。 |

## 重大ルール
### 1. 主キー重複
- **対象**: `stage.y1_case`, `stage.ef_inpatient_detail`, `stage.d_inclusive_detail`
- **SQL サンプル**
```sql
INSERT INTO dq.results_yyyymm (facility_cd, yyyymm, rule_id, severity, cnt, sample_keys, note)
SELECT
    facility_cd,
    :yyyymm AS yyyymm,
    'PK_DUPLICATE_Y1' AS rule_id,
    'CRITICAL' AS severity,
    COUNT(*) AS cnt,
    LISTAGG(data_id, ',') WITHIN GROUP (ORDER BY data_id) AS sample_keys,
    '様式1 主キー重複' AS note
FROM (
    SELECT facility_cd, data_id
    FROM stage.y1_case
    WHERE yyyymm = :yyyymm
    GROUP BY facility_cd, data_id
    HAVING COUNT(*) > 1
) t;
```

### 2. 入退院日整合性 (退院日 < 入院日)
```sql
INSERT INTO dq.results_yyyymm (...)
SELECT
    facility_cd,
    :yyyymm,
    'DATE_INCONSISTENCY',
    'CRITICAL',
    COUNT(*),
    LISTAGG(data_id, ',') WITHIN GROUP (ORDER BY data_id) AS sample_keys,
    '退院日が入院日より前'
FROM stage.y1_case
WHERE discharge_date < admission_date
  AND yyyymm = :yyyymm;
```

### 3. 件数未一致（様式1 vs K）
```sql
WITH y1 AS (
  SELECT facility_cd, COUNT(*) AS cnt
  FROM stage.y1_case
  WHERE yyyymm = :yyyymm
  GROUP BY facility_cd
),
k AS (
  SELECT facility_cd, COUNT(*) AS cnt
  FROM raw.k_common_id
  WHERE to_char(created_at, 'YYYYMM') = :yyyymm
  GROUP BY facility_cd
)
INSERT INTO dq.results_yyyymm (...)
SELECT
  y1.facility_cd,
  :yyyymm,
  'CASE_K_COUNT_MISMATCH',
  'CRITICAL',
  ABS(y1.cnt - k.cnt),
  NULL,
  '様式1とKファイル件数不一致'
FROM y1
FULL OUTER JOIN k USING (facility_cd)
WHERE COALESCE(y1.cnt,0) <> COALESCE(k.cnt,0);
```

## 警告ルール
### 4. 円点区分不整合
```sql
INSERT INTO dq.results_yyyymm (...)
SELECT
  facility_cd,
  :yyyymm,
  'YEN_POINT_FLAG_MISMATCH',
  'WARNING',
  COUNT(*),
  LISTAGG(seq_no || '-' || detail_no, ',') WITHIN GROUP (ORDER BY seq_no) AS sample_keys,
  '円・点区分と金額の矛盾'
FROM stage.ef_inpatient_detail
WHERE (yen_flag = '1' AND points IS NULL)
   OR (yen_flag = '0' AND points IS NULL)
  AND yyyymm = :yyyymm;
```

### 5. 辞書未一致 (診療行為コード)
```sql
INSERT INTO dq.results_yyyymm (...)
SELECT
  facility_cd,
  :yyyymm,
  'SERVICE_CODE_NOT_FOUND',
  'WARNING',
  COUNT(*),
  NULL,
  '診療行為コード未整合'
FROM stage.ef_inpatient_detail d
LEFT JOIN ref.dim_service_code s ON d.master_code = s.service_code
WHERE s.service_code IS NULL
  AND d.yyyymm = :yyyymm;
```

### 6. ゼロ費用症例
```sql
INSERT INTO dq.results_yyyymm (...)
SELECT
  facility_cd,
  :yyyymm,
  'ZERO_COST_CASE',
  'WARNING',
  COUNT(*),
  LISTAGG(data_id, ',') WITHIN GROUP (ORDER BY data_id) AS sample_keys,
  '包括+出来高とも0点'
FROM mart.fact_case_summary
WHERE total_points = 0
  AND yyyymm = :yyyymm;
```

## 結果テーブル運用
- テーブル: `dq.results_yyyymm`
- 主キー: `result_id`（IDENTITY）
- 1 バッチ（yyyymm × facility）ごとに複数行登録可。
- ロード開始時に対象年月・施設の既存レコードを削除し冪等性を確保。

### 挿入テンプレート
```sql
DELETE FROM dq.results_yyyymm
 WHERE yyyymm = :yyyymm
   AND facility_cd = :facility_cd;

-- 各ルール SQL (上記)
```

## dbt tests との連携（最小構成）
- `models/**/schema.yml` で主キーや参照整合性のチェックを `unique`, `not_null`, `accepted_values` などの dbt generic test として宣言する。
- 各テストには以下のメタ情報を付与し、DQ 結果テーブル登録に必要な属性を埋める。
  ```yaml
  tests:
    - unique:
        meta:
          dq_rule_id: PK_DUPLICATE_Y1
          dq_severity: CRITICAL
          dq_note: "様式1 主キー重複"
          dq_facility_column: facility_cd
          dq_sample_key_columns: [data_id]
  ```
- `tools/run_dbt_dq.py` を `dpc-dbt-tests` ECS タスク（もしくは Lambda からの Fargate 実行）で呼び出し、`dbt test --store-failures` を実行する。
  ```bash
  python tools/run_dbt_dq.py \
    --yyyymm 202504 \
    --project-dir /workspace/dbt \
    --workgroup-name dpc-rs \
    --database dpc \
    --secret-arn arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:dbt-redshift \
    --slack-webhook-url https://hooks.slack.com/services/T000/B000/XXXX
  ```
- スクリプトは `target/run_results.json` と `target/manifest.json` から失敗したテストを抽出し、`dq.results_yyyymm` へ `INSERT` する。`dq_facility_column` が指定されたテストでは `dbt test --store-failures` が作成した失敗テーブルを Redshift Data API で読み出し、施設単位の件数とサンプルキーを集約する。
- Slack Webhook URL を指定すると重大度別サマリとルール ID を含むメッセージを送信する。Webhook を指定しない場合は格納のみ行う。

### Lambda/ECS 連携メモ
1. Lambda (`dq_check`) から `dpc-dbt-tests` タスクを起動し、環境変数で `--yyyymm` や Secrets Manager ARN を引き渡す。
2. ECS タスク内で上記スクリプトを実行し、終了コード 0/1 をハンドリングする。テスト失敗があっても結果は Redshift に記録されるため、Lambda は終了コード 0 を期待する。
3. Slack 通知を受信したら、学習者自身が最初のエスカレーション先として調査する。`ref.dim_service_code` の更新頻度は未定のため、Slack 通知後に必要に応じて手動で辞書を更新する。

## しきい値
| ルール ID | 重大度 | しきい値 | 対応 |
| --- | --- | --- | --- |
| PK_DUPLICATE_Y1 | CRITICAL | 1 件でも検出 | バッチ停止、再提出依頼 |
| DATE_INCONSISTENCY | CRITICAL | 1 件 | バッチ停止、ロジック・入力見直し |
| CASE_K_COUNT_MISMATCH | CRITICAL | 1 件 | バッチ停止、Kファイル再取得 |
| YEN_POINT_FLAG_MISMATCH | WARNING | 5 件以上で通知強調 | 施設に確認、ETL 計算ロジック調査 |
| SERVICE_CODE_NOT_FOUND | WARNING | 10 件以上 | マスタ更新検討 |
| ZERO_COST_CASE | WARNING | 施設症例の 2% 超 | 非保険フラグ確認、様式4連携 |

> **TODO**: `ZERO_COST_CASE` の割合算出は現段階では実装していない。将来の拡張で施設別分母を含む検証ロジックを追加する。

## Slack 通知擬似コード
```python
def notify_slack(results: List[Dict]):
    summary = defaultdict(lambda: {'critical': 0, 'warning': 0})
    for row in results:
        sev = row['severity'].lower()
        facility = row['facility_cd']
        summary[facility][sev] += row['cnt']

    blocks = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*DPC DQ 結果 {results[0]['yyyymm']}*"
            }
        },
        {"type": "divider"}
    ]

    for facility, counts in summary.items():
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"施設 {facility}: :rotating_light: {counts['critical']} 件 / :warning: {counts['warning']} 件"
            }
        })

    payload = {"blocks": blocks}
    requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=5)
```

## 運用フロー
1. `compute_readmit` 後に `dq_check` Lambda を実行し、上記 SQL を順次発行。
2. `dq.results_yyyymm` に結果格納。
3. `dpc-notify` から Slack へ概要通知。重大がある場合はバッチ失敗扱いとし Step Functions は `NotifyFailure` をトリガー。
4. 分析チームは結果を QuickSight または Redshift から参照。

## 決定事項 / 未決事項
- **決定事項**
  - DQ 結果は `dq.results_yyyymm` に統一し、Slack 通知で概要を共有する。
  - 主キー重複・日付不整合・件数未一致を重大ルールとしてバッチ停止条件とする。
  - 警告ルールは閾値を超えた場合にのみ Slack 通知メッセージ内で強調表示する。
- **未決事項**
  - `ref.dim_service_code` を自動更新する頻度が未定のため、辞書未一致のエスカレーション先を確定する必要がある。
  - `ZERO_COST_CASE` の許容割合（2%）が妥当か、運用部門と合意が必要。
  - DQ 結果を可視化する QuickSight ダッシュボードの実装タイミングが未定。
