# タスク 01: AWS 基盤初期設定

## 目的
学習用途の最小構成で利用する AWS リソース（S3 バケット、KMS、基本 IAM ロール）を Terraform で構築し、以降の作業に共通する土台を整えます。docs/01_architecture.md と docs/02_network_security.md の決定事項に基づきます。

## 前提条件
- 管理コンソールへアクセスできる学習用 AWS アカウント。
- AdministratorAccess 相当の権限。
- Terraform v1.5 以上と AWS CLI がローカルにセットアップ済み。

## 手順
1. **Terraform ワークスペースの用意**
   - `infra/terraform/dev` ディレクトリを作成し、`versions.tf` で AWS プロバイダー (ap-northeast-1) と必要なバージョン制約を定義します。
   - `backend` 設定で S3 バケット `dpc-learning-tfstate`（なければ初回のみ手動作成）と DynamoDB テーブル `terraform-lock` を指定します。
   - `terraform init` で初期化し、`fmt` と `validate` を実行してベース設定を確認します。
2. **foundation モジュールの実装**
   - `modules/foundation` を作成し、KMS CMK、S3 バケット、CloudTrail を定義します。
   - CMK は `alias/dpc-learning-kms`、S3 バケットは `dpc-learning-data-<env>` を作成し、暗号化に KMS を指定、バージョニングとパブリックアクセスブロックを有効化します。
   - CloudTrail は管理イベント + S3 データイベント（`raw/` プレフィックス）を `logs/cloudtrail/` に書き込みます。
   - ルートモジュールから foundation モジュールを呼び出し、`terraform apply` でリソースを作成します。
3. **Secrets Manager プレースホルダの作成**
   - `modules/secrets` を作成し、`aws_secretsmanager_secret` として `dpc/redshift/credentials`、`dpc/notifications/slack` の 2 つを定義します。
   - タグで利用目的を明示し、値は空 JSON `{}` をデフォルトバージョンとして登録します。
4. **IAM ロールモジュールの実装**
   - `modules/iam` で `role-lambda-dpc`、`role-stepfunctions-dpc`、`role-redshift-copy` を作成し、信頼ポリシーに各サービスプリンシパルを設定します。
   - 最小権限のインラインポリシーを Terraform で定義し、S3/KMS/Redshift Data API/CloudWatch Logs へのアクセスを付与します。
   - Lambda や Step Functions が利用する IAM ロール ARN を `outputs.tf` でエクスポートし、後続タスクで再利用できるようにします。
5. **Terraform 実行の検証**
   - `terraform plan` で差分がないことを確認し、`terraform state list` で主要リソース（KMS、S3、IAM、CloudTrail、Secrets）が管理対象になっていることを確認します。
   - `README.md` などに初期化手順と `terraform workspace` 運用ルールを追記します。

## 完了条件
- Terraform ステート（S3 + DynamoDB）が構成されている。
- CMK、S3 バケット、主要 IAM ロール、CloudTrail、Secrets が Terraform で作成済み。
- IAM ロールが想定するサービスプリンシパルから引き受け可能であり、KMS キーポリシーに含まれている。
- バケットの暗号化とパブリックアクセスブロックが有効化されている。
