# タスク 03: Step Functions / Lambda / ECS による ELT パイプライン構築

## 目的
docs/07_elt_pipeline.md のフローを、最小限の学習用途に合わせて Terraform で構築します。Lambda は軽量処理に限定し、dbt は ECS Fargate タスクで実行します。

## 前提条件
- タスク01〜02が完了し、S3 バケットと Redshift が利用可能。
- IAM ロール `role-lambda-dpc`、`role-stepfunctions-dpc` が存在する。
- Terraform で `modules/pipeline` を追加できる準備が整っている。

## 手順
1. **pipeline モジュール骨子の作成**
   - `modules/pipeline` ディレクトリを新設し、以下の Terraform リソースを定義します。
     - Lambda（`aws_lambda_function`）: `dpc-validate-manifest`, `dpc-copy-raw`, `dpc-compute-readmit`, `dpc-export-parquet`, `dpc-notify`。
       - 依存パッケージは `lambda_layers` で管理し、`role-lambda-dpc` を実行ロールに設定します。
       - 環境変数でターゲット S3 パスや Secrets ARN を参照できるようにします。
     - ECR リポジトリと ECS タスク定義: dbt ランナー用コンテナイメージを push し、タスク実行ロールに Redshift Data API アクセスを付与します。
2. **Step Functions + EventBridge の Terraform 定義**
   - `aws_sfn_state_machine` を Terraform で作成し、docs/07_elt_pipeline.md のステートに従いつつ、dbt ステージを `arn:aws:states:::ecs:runTask.sync` で記述します。
   - `RollbackStage` は通知のみの `Pass` 状態に差し替え、必要なときにだけ TRUNCATE を Terraform 変数で切り替え可能にします。
   - `aws_cloudwatch_event_rule` と `aws_cloudwatch_event_target` で 1 日 1 回のスケジュールを定義し、手動実行 IAM ポリシーは `aws_iam_policy` として出力します。
3. **SNS / 通知経路の定義**
   - `aws_sns_topic` と `aws_sns_topic_subscription`（Lambda エンドポイント）を Terraform に追加し、`dpc-notify` から Publish できるよう権限を付与します。
   - Slack Webhook 呼び出しは Lambda 内コードで Secrets Manager から取得する実装とし、Terraform の環境変数でシークレット ARN を渡します。
4. **Terraform 適用と動作検証**
   - `terraform apply` でパイプライン一式をデプロイし、Lambda/ECS/Step Functions/EventBridge/SNS が作成されたことを確認します。
   - Step Functions の `StartExecution` を手動実行し、サンプルの `_manifest.json` で S3 → Redshift → dbt → export のフローが通ることを確認します。

## 完了条件
- Lambda 関数がデプロイされ、実行ロールに必要な権限が付与されている。
- ECS タスク定義と ECR イメージが存在し、テスト実行で dbt コマンドが完了する。
- Step Functions ステートマシンが有効化され、EventBridge からのトリガー設定が完了している。
