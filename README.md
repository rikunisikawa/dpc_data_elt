# dpc_data_elt

DPC データ学習基盤の設計ドキュメントと IaC 定義を管理するリポジトリです。Terraform により AWS 上の最小構成を構築し、学習用 ELT パイプラ
インの検証土台を提供します。

## ディレクトリ構成

- `docs/` – アーキテクチャ設計、運用方針などのドキュメント。
- `plans/` – タスク別の実装計画。
- `infra/terraform/` – 環境ごとの Terraform ルートモジュールと共通モジュール。
- `tools/` – 開発補助スクリプト（必要に応じて追加）。

## Terraform 初期化と運用ルール

1. AWS CLI で認証情報 (`AdministratorAccess` 相当) を設定します。
2. Terraform 実行環境で以下のコマンドを順に実行します。
   ```bash
   cd infra/terraform/dev
   terraform init
   terraform fmt
   terraform validate
   terraform plan
   ```
3. `dev` 環境は Terraform の `default` ワークスペースを利用します。他環境を作成する場合は `terraform workspace new <env>` を利用し、バッ
   クエンドの `key` 規約（`<env>/terraform.tfstate`）に従ってください。
4. リソースを適用する際は `terraform apply` を利用し、変更内容を確認してから承認します。

> **補足**: S3 バックエンド (`dpc-learning-tfstate`) と DynamoDB ロックテーブル (`terraform-lock`) は初回のみ手動で作成するか、学習アカ
> ウント側で既存のものを再利用してください。

## 提供される AWS リソース

タスク 01 の Terraform 定義により以下のリソースが作成されます。

- KMS CMK (`alias/dpc-learning-kms`) および環境共通タグ。
- データレイヤー用 S3 バケット (`dpc-learning-data-<env>`) のバージョニング・暗号化・パブリックアクセスブロック設定。
- 管理イベントと S3 `raw/` データイベントを記録する AWS CloudTrail。
- Secrets Manager におけるプレースホルダシークレット（Redshift 認証情報、Slack 通知）。
- Lambda、Step Functions、Redshift COPY/UNLOAD 用の IAM ロールと最小権限ポリシー。

Terraform の状態一覧は `terraform state list` で確認し、不要な手動変更が含まれていないか定期的にチェックしてください。
