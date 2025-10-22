# DPC 学習基盤 観測・運用設計

## 目的
Redshift Serverless を中心とした学習基盤の監視指標、リソースポリシー、アラート、メンテナンス手順を定義する。サーバーレス構成で費用を抑えつつ、必要な可観測性を確保する。

## Redshift Serverless キャパシティ設計
- **ベース RPU**: 8 RPU（最小値）で起動。バッチ処理時のみスケーリングし、30 分アイドルで自動一時停止。
- **最大 RPU**: 32 RPU。Step Functions からの大規模 dbt 実行時にのみ増加を許可。
- **ワークグループポリシー**: `workgroup-usage-limit` を設定し、月次上限コストを可視化。閾値 80% 到達で通知。
- **クエリモニタリングルール (QMR)**: `execution_time > 600` 秒のクエリにタグ付けし、長時間クエリを通知。必要に応じて `abort` アクションを設定。

## 監視メトリクス
| カテゴリ | メトリクス | 説明 | 閾値 | アクション |
| --- | --- | --- | --- | --- |
| 取込遅延 | `ELTExecutionDelay` (自前カスタム) | 最終成功時刻との差分 (分) | > 90 分 | 通知後に Step Functions 再実行。 |
| COPY 失敗 | CloudWatch Metric Filter (`CopyErrorCount`) | `stl_load_errors` 件数 | >=1 | バッチ失敗、担当者呼び出し。 |
| クエリ失敗率 | `FailedQueryCount / TotalQueryCount` (Serverless) | 直近 1 時間 | > 5% | SQL レビュー・再実行。 |
| RPU 使用率 | `RPUConsumption` | 現在の消費 RPU | > 28 RPU が 5 分継続 | クエリ負荷を確認し、必要ならモデル調整。 |
| 自動一時停止 | `ServerlessDatabaseStatus` | `PAUSED` である時間 | < 30% | 無停止期間が長い場合はスケジュール見直し。 |
| ディストリビューション | `table_skew_percent` (system table) | ディストリビューション偏り | > 20% | DISTKEY 見直し。 |

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
        "title": "RPU Consumption",
        "metrics": [
          ["AWS/Redshift", "RPUConsumption", "Workgroup", "dpc-learning"],
          ["AWS/Redshift", "RPUCapacity", "Workgroup", "dpc-learning"]
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
        "title": "Query Success vs Fail",
        "metrics": [
          ["AWS/Redshift", "SuccessfulQueryCount", "Workgroup", "dpc-learning"],
          ["AWS/Redshift", "FailedQueryCount", "Workgroup", "dpc-learning"]
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
          ["AWS/Redshift", "UsedStorage", "Namespace", "dpc-learning"]
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
        "query": "SOURCE '/aws/redshift-serverless/workgroup/dpc-learning' | fields @timestamp, @message | filter @message like 'ERROR' | sort @timestamp desc | limit 20",
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
| `Alert-Storage-High` | `UsedStorage` が 90% 以上 | Slack, メール |
| `Alert-RPU-Spike` | `RPUConsumption > 28` が 5 分継続 | Slack |
| `Alert-Query-Failure` | `FailedQueryCount` が連続 3 回増加 | Slack |

通知は SNS トピック `arn:aws:sns:ap-northeast-1:<account>:dpc-alerts` 経由。

Terraform では `modules/operations` として CloudWatch ダッシュボード、メトリクスフィルタ、アラーム、SNS サブスクリプションを管理し、Pull Request で `terraform plan` を通過しない限り監視設定が変わらないよう統制する。

## メンテナンス手順
### 自動実行
- `ANALYZE`：Step Functions バッチ内で `ANALYZE` を実行。
- `VACUUM`：週次（日曜 04:00）で `VACUUM` を実行。Serverless でも手動 VACUUM が必要。
- `ANALYZE COMPRESSION`：月次で `ANALYZE COMPRESSION` を実行し推奨エンコードを確認。

### 手動トリガー条件
| 手順 | 条件 |
| --- | --- |
| `VACUUM FULL` | `stv_blocklist` で 20% 以上の未使用領域を検知した場合 |
| `ANALYZE` 再実行 | 大量データロード（1 億件以上）後、統計古さが懸念される場合 |
| `Adjust RPU Limit` | `RPUConsumption` が頻繁に上限に達する場合 |

## Runbook
1. **一次切り分け**
   - CloudWatch アラーム確認。
   - Step Functions 実行履歴で失敗ステップを特定。
   - Redshift `STL_LOAD_ERRORS`, `SVL_QLOG` を参照しエラー判定。
2. **復旧フロー**
   - `COPY` エラー: 原因ファイルを S3 から削除/再アップロードし、Step Functions を再実行。
   - `dbt` 失敗: ログを確認し SQL 修正。必要に応じ `dbt run --select <model>` を手動実行後、全体を再実行。
   - ストレージ逼迫: `UNLOAD` 済み古いデータを Spectrum へ退避し、`VACUUM` を実行。
   - RPU スパイク: 実行中クエリを特定し、必要に応じて QMR でキャンセル。
3. **事後対応**
   - Confluence / Notion に事象記録。
   - DQ 結果およびエラーサマリを共有。

## 決定事項 / 未決事項
- **決定事項**
  - Redshift Serverless のベース RPU を 8、最大 RPU を 32 に設定し、月次上限アラートを構成する。
  - CloudWatch ダッシュボードで RPU 消費、クエリ成功率、ストレージ、ELT 遅延を可視化し、SNS を通じてアラートを発報する。
  - `ANALYZE`, `VACUUM`, `ANALYZE COMPRESSION` の実行スケジュールを定義し、定期メンテナンスを自動化する。
- **未決事項**
  - `ELTExecutionDelay` の算出方法（Step Functions 実行完了時刻 vs mart テーブル更新時刻）の詳細設計が必要。
  - RPU 上限 32 の妥当性を学習データ量で検証し、必要なら再設定する。
  - Runbook をどのプラットフォームで管理するか（Confluence vs Notion）の決定が必要。
