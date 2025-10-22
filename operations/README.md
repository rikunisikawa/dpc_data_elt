# Operations Runbook (Minimal)

この Runbook は学習用環境での ELT パイプライン監視と一次対応をまとめたものです。docs/09_operations.md の詳細設計を簡易化し、すぐに参照できる手順を提供します。

## 1. アラート受信後の一次切り分け
1. CloudWatch アラームの内容を確認します。`dpc-learning-alerts` SNS トピック経由で Slack と Lambda (`dpc-notify`) に通知されます。
2. Step Functions 失敗アラームの場合は、AWS Step Functions コンソールで該当実行の失敗ステートを特定します。
3. Redshift RPU 利用率アラームの場合は、Redshift Serverless コンソールで現在の Workgroup 状況と同時実行クエリを確認します。

## 2. 復旧フロー
- **Step Functions 実行失敗**
  - エラー内容を確認し、リトライ可能な場合は `StartExecution` で再実行します。
  - 入力データに起因する失敗（例: S3 マニフェスト破損）の場合は、該当ファイルを差し替えたうえで再実行します。
- **Redshift RPU 利用率スパイク**
  - `SVL_QLOG` や `STV_RECENTS` を参照し、負荷の高いクエリを特定します。
  - 長時間実行クエリがある場合はキャンセルし、必要に応じて dbt モデルの再実行順序を調整します。
- **dbt / モデル処理の失敗**
  - dbt Cloud もしくは ECS タスクのログを確認し、該当モデルのみを `dbt run --select <model>` で再実行後、全体バッチを再実行します。

## 3. 二次対応と共有
1. 必要に応じて S3 の原本データを過去の成功バージョンに差し替え、`COPY` を再実行します。
2. Redshift の `VACUUM` / `ANALYZE` を手動実行して統計情報を整えます。
3. 障害内容と対応状況をチームに共有し、事後レビューの議事録を作成します。

## 4. 将来の改善アイデア
- カスタムメトリクス（例: `ELTExecutionDelay`）の実装とアラート連携。
- dbt の `state:modified` 実行結果を CloudWatch Logs へエクスポートして検索性を向上。

## 5. Runbook 管理ツール
現時点では本リポジトリで Runbook を管理し、学習完了後に Confluence と Notion を比較して正式なナレッジベースを選定します。

