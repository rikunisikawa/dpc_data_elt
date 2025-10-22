# タスク 07: 運用監視と通知のセットアップ

## 目的
docs/09_operations.md・docs/11_cicd.md を参考に、学習環境で必要最小限の運用監視と通知を Terraform で構成します。

## 前提条件
- タスク03の Step Functions / Lambda が稼働済み。
- Slack Webhook シークレットが登録済み。
- `modules/pipeline` がデプロイされ、SNS / Lambda 実装が存在する。

## 手順
1. **operations モジュールの作成**
   - `modules/operations` を新設し、CloudWatch アラームと通知経路を Terraform で管理します。
   - Step Functions 実行失敗数 (`ExecutionsFailed`) と Redshift `RPUUtilization` の 2 種類のアラームを `aws_cloudwatch_metric_alarm` で定義し、SNS トピックをアクションに設定します。
2. **SNS 通知の強化**
   - 既存の `dpc-learning-alerts` トピックに対し、`modules/operations` で Lambda サブスクリプションと将来のメール受信者を変数で追加できるようにします。
   - Terraform で `aws_lambda_permission` を設定し、CloudWatch Alarms から `dpc-notify` を呼び出せるようにします。
3. **運用 Runbook (簡易版)**
   - README もしくは `operations/README.md` に、失敗時の対応手順（再実行、S3 差し替え、dbt ログ確認）を記載します。
   - Runbook 管理ツールの選定（Confluence vs Notion）は学習完了後に検討する旨を明記します。
4. **CI/CD 簡易設定**
   - GitHub Actions または CodeBuild で `terraform fmt -check`、`terraform validate`、`terraform plan` を追加し、IaC の整合性を Pull Request で検証します。
   - 既存の `dbt deps && dbt compile` ワークフローも併せて実行し、`sqlfluff` 等の高度なリンター導入は後回しにし、必要になった時点で再検討します。

## 完了条件
- Step Functions / Redshift の主要メトリクスにアラームが設定されている。
- SNS → Slack の通知経路が動作する。
- 運用 Runbook（簡易版）がリポジトリに存在し、対応フローが記載されている。
- CI/CD で Terraform チェックと dbt コンパイルチェックが自動実行される。
