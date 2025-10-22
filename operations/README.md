# Operations Runbook (Minimal)

この Runbook は学習用環境における ELT パイプライン監視と一次対応の手順をまとめたものです。詳細設計は docs/09_operations.md に整理
されており、ここでは日常的な障害対応の流れだけを簡潔に記載します。

## 1. アラート受信後の一次切り分け
1. Slack の `#dpc-alerts` チャンネルで SNS (`dpc-learning-alerts`) 経由の通知を確認します。Lambda (`dpc-notify`) にも同じイベントが配信されます。
2. Step Functions 失敗アラームの場合は、AWS Step Functions コンソールで該当実行のエラー詳細を確認します。
3. Redshift RPU 利用率アラームの場合は、Redshift Serverless の Workgroup 画面で同時実行クエリと直近メトリクスを確認します。

## 2. 復旧フロー
- **Step Functions 実行失敗**
  - エラーログを確認し、データ不備が疑われる場合は S3 の原本を差し替えてから `StartExecution` で再実行します。
  - 再実行で改善しない場合は該当 Lambda / Glue ジョブのコードを確認し、修正後に再デプロイします。
- **Redshift RPU 利用率スパイク**
  - `SVL_QLOG` と `STV_RECENTS` を確認し、負荷の高いクエリを特定します。
  - 長時間実行クエリがあればキャンセルし、必要に応じて dbt モデルの実行順序を変更します。
- **dbt / モデル処理失敗**
  - CloudWatch Logs または dbt 実行ログを確認し、対象モデルのみ `dbt run --select <model>` で再実行後に全体バッチを再開します。

## 3. 二次対応とチーム共有
1. 必要に応じて S3 の成功アーカイブからデータを復旧し、再ロードを実施します。
2. Redshift の `VACUUM` / `ANALYZE` を手動実行し、統計情報を整えます。
3. 障害内容・原因・対策をチームへ共有し、事後レビューの議事録を残します。

## 4. 今後の改善アイデア
- `ELTExecutionDelay` などカスタムメトリクスの追加と通知連携。
- Redshift Workgroup のクエリモニタリングルール整備による自動キャンセル。
- dbt の `state:modified` 実行結果を CloudWatch Logs に出力し検索性を向上。

## 5. Runbook 管理ツール
本 Runbook は暫定的にリポジトリで管理しており、学習完了後に Confluence と Notion を比較検討して正式なナレッジベースを決定します。
