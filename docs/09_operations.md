# DPC 学習基盤 観測・運用設計

## 目的
Redshift を中心とした学習基盤の監視指標、WLM 設定、アラート、メンテナンス手順を定義する。

## WLM 設計
| キュー名 | 用途 | スロット | Concurrency Scaling | 優先度 | 備考 |
| --- | --- | --- | --- | --- | --- |
| `batch` | 日次 ELT（dbt run, COPY） | 50% | 有効 | 高 | Step Functions からのみ実行。クエリキュータイムアウト 2 時間。 |
| `adhoc` | 学習者の分析クエリ | 30% | 無効 | 中 | 同時実行 5 件まで、タイムアウト 30 分。 |
| `admin` | DQ チェック、メンテ | 20% | 有効 | 最高 | Lambda (DQ, VACUUM) 専用。 |

- Short Query Acceleration (SQA) を有効化し、`admin` キューからの短時間クエリを優先。
- WLM パラメータ: `max_concurrency`、`user_group` マッピングを IAM ロール単位で設定。

## 監視メトリクス
| カテゴリ | メトリクス | 説明 | 閾値 | アクション |
| --- | --- | --- | --- | --- |
| 取込遅延 | `ELTExecutionDelay` (自前カスタム) | 最終成功時刻との差分 (分) | > 90 分 | 通知後に Step Functions 再実行。 |
| COPY 失敗 | CloudWatch Metric Filter (`CopyErrorCount`) | `stl_load_errors` 件数 | >=1 | バッチ失敗、担当者呼び出し。 |
| クエリ失敗率 | `WLMRejectedQueries` / `WLMAttemptedQueries` | 直近 1 時間 | > 5% | WLM 再調整、SQL レビュー。 |
| スロット逼迫 | `WLMQueueLength` | `batch` キューの待機数 | > 10 | クエリ優先順位見直し。 |
| テーブルスキュー | `table_skew_percent` (system table) | ディストリビューション偏り | > 20% | DISTKEY 見直し。 |
| ストレージ使用 | `RedshiftStorageCapacity` | RA3 ストレージ使用率 | > 80% | VACUUM / Spectrum 退避。 |

## CloudWatch ダッシュボード構成
```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Redshift WLM Queue Length",
        "metrics": [
          ["AWS/Redshift", "WLMQueueLength", "QueueName", "batch", {"stat": "Sum"}],
          ["AWS/Redshift", "WLMQueueLength", "QueueName", "adhoc", {"stat": "Sum"}]
        ],
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Concurrency Scaling Usage",
        "metrics": [
          ["AWS/Redshift", "ConcurrencyScalingActiveClusters", "ClusterIdentifier", "dpc-learning"]
        ],
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Storage Utilization",
        "metrics": [
          ["AWS/Redshift", "PercentageDiskSpaceUsed", "ClusterIdentifier", "dpc-learning"]
        ],
        "period": 3600,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ELT Execution Delay",
        "metrics": [
          ["Custom/DPC", "ELTExecutionDelay", "Environment", "prod"]
        ],
        "period": 300,
        "stat": "Maximum"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 12,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/redshift/cluster/dpc-learning' | fields @timestamp, @message | filter @message like 'ERROR' | sort @timestamp desc | limit 20",
        "title": "Redshift Error Logs"
      }
    }
  ]
}
```

## アラート設定
| アラート | 条件 | 通知先 |
| --- | --- | --- |
| `Alert-ELT-Delay` | `ELTExecutionDelay > 90` 分が 2 データポイント連続 | Slack `#dpc-alerts`, PagerDuty |
| `Alert-COPY-Error` | `CopyErrorCount >= 1` | Slack, OpsGenie |
| `Alert-Storage-High` | `PercentageDiskSpaceUsed > 80%` を 3 回連続 | Slack, メール |
| `Alert-WLM-Queue` | `WLMQueueLength (batch) > 10` が 10 分継続 | Slack |
| `Alert-Query-Failure` | `WLMRejectedQueries/WLMAttemptedQueries > 0.05` | Slack |

通知は SNS トピック `arn:aws:sns:ap-northeast-1:<account>:dpc-alerts` 経由。

## メンテナンス手順
### 自動実行
- `ANALYZE`：Step Functions バッチ内で `analyze compression` とは別に `ANALYZE stage.*` を実行。
- `VACUUM`：週次（日曜 04:00）で `VACUUM REINDEX` を実行。時間が掛かる場合は `VACUUM DELETE` のみ自動。
- `ANALYZE COMPRESSION`：月次で `ANALYZE COMPRESSION` を実行し推奨エンコードを確認。

### 手動トリガー条件
| 手順 | 条件 |
| --- | --- |
| `VACUUM FULL` | `stv_blocklist` で 20% 以上の未使用領域を検知した場合 |
| `ANALYZE` 再実行 | 大量データロード（1 億件以上）後、統計古さが懸念される場合 |
| `Resize Cluster` | ストレージ使用率 90% 超 or WLM 待機が日常化 |

## Runbook
1. **一次切り分け**
   - CloudWatch アラーム確認。
   - Step Functions 実行履歴で失敗ステップを特定。
   - Redshift `STL_LOAD_ERRORS`, `SVL_QLOG` を参照しエラー判定。
2. **復旧フロー**
   - `COPY` エラー: 原因ファイルを S3 から削除/再アップロードし、Step Functions を再実行。
   - `dbt` 失敗: ログを確認し SQL 修正。必要に応じ `dbt run --select <model>` を手動実行後、全体を再実行。
   - ストレージ逼迫: `UNLOAD` 済み古いデータを Spectrum へ退避し、`VACUUM` を実行。
   - WLM キュー過多: 一時的に `adhoc` キューを停止し `batch` を優先。
3. **事後対応**
   - Confluence / Notion に事象記録。
   - DQ 結果およびエラーサマリを共有。

## 決定事項 / 未決事項
- **決定事項**
  - WLM を `batch` / `adhoc` / `admin` の 3 キューに分割し、ELT 優先度を確保する。
  - CloudWatch ダッシュボードで WLM、ストレージ、ELT 遅延を可視化し、SNS を通じてアラートを発報する。
  - `ANALYZE`, `VACUUM`, `ANALYZE COMPRESSION` の実行スケジュールを定義し、定期メンテナンスを自動化する。
- **未決事項**
  - `ELTExecutionDelay` の算出方法（Step Functions 実行完了時刻 vs mart テーブル更新時刻）の詳細設計が必要。
  - WLM スロット比率 (50/30/20) の妥当性検証を実データ負荷で実施する必要がある。
  - Runbook をどのプラットフォームで管理するか（Confluence vs Notion）の決定が必要。
