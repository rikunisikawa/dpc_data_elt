# タスク 02: Redshift Serverless とスキーマ準備

## 目的
Terraform から Redshift Serverless ワークグループを最小構成で起動し、docs/01_architecture.md・docs/05_physical_ddl.md に記載されたスキーマと主要テーブルを作成します。

## 前提条件
- タスク01が完了し、KMS キーと `role-redshift-copy` が存在する。
- Terraform で foundation/iam モジュールがデプロイ済み。

## 手順
1. **redshift モジュールの実装**
   - `modules/redshift` を作成し、`aws_redshiftserverless_workgroup` と `aws_redshiftserverless_namespace` を定義します。
   - ワークグループはリージョン ap-northeast-1、RPU 8、IAM ロールに `role-redshift-copy` をアタッチ、暗号化に `alias/dpc-learning-kms` を指定します。
   - Namespace はデフォルト DB 名 `dpc_learning`、自動スナップショット保持 7 日、Data API を有効化します。
   - 既定 VPC のパブリックサブネットとセキュリティグループ（受信ルールなし）を Terraform で指定します。
   - ルートモジュールから redshift モジュールを呼び出し、`terraform apply` でデプロイします。
2. **スキーマ作成**
   - Terraform からは管理しにくいため、Redshift Data API を使ったブートストラップスクリプトを `scripts/bootstrap_redshift.sql` にまとめ、`aws_lambda_invocation` またはローカルスクリプトで適用します。
   - 以下の SQL を順に実行し、スキーマを作成します。
     ```sql
     create schema if not exists raw;
     create schema if not exists stage;
     create schema if not exists mart;
     create schema if not exists ref;
     create schema if not exists dq;
     ```
3. **DDL 適用（最小）**
   - docs/05_physical_ddl.md のうち、学習で必須となるテーブル（raw の COPY 先と mart の参照先）を選定し、`ddl/core/*.sql` として整理します。
   - Data API 経由で CREATE TABLE / VIEW 文を適用します。再入院フラグなど高度な派生列は後続タスクで実装します。

## 完了条件
- Redshift Serverless ワークグループおよび Namespace が起動済みで Data API 接続が確認できる。
- raw/stage/mart/ref/dq スキーマが存在する。
- raw と mart の主要テーブルが作成済みで、`information_schema.tables` に確認できる。
