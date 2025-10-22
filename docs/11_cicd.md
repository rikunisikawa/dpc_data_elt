# DPC 学習基盤 CI/CD & 環境昇格設計

## 目的
dbt モデルおよび Redshift DDL の変更を Git ベースで管理し、dev→stg→prod の環境昇格とロールバック手順を定義する。

## Git 運用ポリシー
- リポジトリ: GitHub `dpc-learning`。
- ブランチ戦略:
  - `main`：prod と同期。
  - `develop`：stg 相当。feature ブランチはここから切る。
  - `feature/<ticket-id>`：個別開発。
- Pull Request には以下のチェックを必須:
  - `dbt run --models state:modified`（dev）
  - `dbt test --models state:modified`
  - `terraform fmt -check && terraform validate && terraform plan`（foundation/pipeline/operations モジュール）
  - SQLFluff (任意)
- レビュー承認 2 名以上。

## 環境構成
| 環境 | Redshift クラスター | S3 バケット | dbt Target | 備考 |
| --- | --- | --- | --- | --- |
| dev | `dpc-learning-dev` | `dpc-learning-data-dev` | `dev` | 開発者が自由に実行。 |
| stg | `dpc-learning-stg` | `dpc-learning-data-stg` | `stg` | リリース前検証。 |
| prod | `dpc-learning-prod` | `dpc-learning-data-prod` | `prod` | 本番相当。 |

## GitHub Actions ワークフロー雛形
`.github/workflows/dbt-deploy.yml`
```yaml
name: dbt Deploy

on:
  push:
    branches:
      - develop
      - main
  pull_request:
    branches:
      - develop

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    env:
      DBT_PROFILES_DIR: .github/profiles
    steps:
      - uses: actions/checkout@v4
      - name: Terraform setup
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.6
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Terraform fmt & validate
        run: |
          terraform -chdir=infra/terraform/dev fmt -check
          terraform -chdir=infra/terraform/dev validate
      - name: Terraform plan (no apply)
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_REGION: ap-northeast-1
        run: terraform -chdir=infra/terraform/dev plan -input=false
      - name: Install dependencies
        run: |
          pip install dbt-redshift==1.7.8 sqlfluff
      - name: Configure profile
        run: |
          mkdir -p .github/profiles
          cat <<'EOP' > .github/profiles/profiles.yml
          dpc_learning:
            target: dev
            outputs:
              dev:
                type: redshift
                host: ${{ secrets.DPC_DEV_HOST }}
                user: ${{ secrets.DPC_DEV_USER }}
                password: ${{ secrets.DPC_DEV_PASSWORD }}
                port: 5439
                dbname: dpc
                schema: stage
                threads: 4
          EOP
      - name: dbt deps
        run: dbt deps
      - name: dbt run (modified models)
        run: dbt run --models state:modified
      - name: dbt test (modified models)
        run: dbt test --models state:modified
      - name: sqlfluff lint
        run: sqlfluff lint models

  deploy-stg:
    needs: build-and-test
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Apply DDL to stg
        env:
          REDSHIFT_SECRET_ARN: ${{ secrets.DPC_STG_SECRET_ARN }}
        run: |
          python scripts/apply_ddl.py --secret $REDSHIFT_SECRET_ARN --path docs/05_physical_ddl.sql
      - name: dbt run stg
        run: dbt run --target stg
      - name: dbt test stg
        run: dbt test --target stg

  deploy-prod:
    needs: deploy-stg
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Apply DDL to prod
        env:
          REDSHIFT_SECRET_ARN: ${{ secrets.DPC_PROD_SECRET_ARN }}
        run: |
          python scripts/apply_ddl.py --secret $REDSHIFT_SECRET_ARN --path docs/05_physical_ddl.sql
      - name: dbt run prod
        run: dbt run --target prod
      - name: dbt test prod
        run: dbt test --target prod
      - name: dbt docs generate
        run: dbt docs generate --target prod
      - name: Upload docs to S3
        run: aws s3 sync target/catalog s3://dpc-learning-data-prod/processed/docs/
```

## Secrets / 環境変数一覧
| キー | 用途 |
| --- | --- |
| `DPC_DEV_HOST`, `DPC_DEV_USER`, `DPC_DEV_PASSWORD` | dev Redshift 接続情報 |
| `DPC_STG_SECRET_ARN`, `DPC_PROD_SECRET_ARN` | Secrets Manager 上の Data API 資格情報 |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | Actions での AWS CLI 利用 |
| `SLACK_WEBHOOK_URL` | 通知用（必要時） |
| `DBT_ENV_SECRET_env` | dbt vars (例: `current_yyyymm`) |

## 破壊的変更ガード
- `scripts/apply_ddl.py` で以下をチェック:
  - `DROP TABLE` / `ALTER TABLE DROP COLUMN` を検知したら実行停止しレビュー要求。
  - `ALTER TABLE ... TYPE` は互換性チェック（Numeric 幅縮小など禁止）。
- dbt の `state:modified` チェックを `--warn-error` で実行。
- `git diff` で `docs/05_physical_ddl.md` が更新された際は PR テンプレートで影響確認項目を必須入力。

## ロールバック手順
1. **dbt モデル**: `git revert` で該当コミットを戻し、`dbt run --models <target>` で再適用。
2. **DDL**: `scripts/apply_ddl.py --rollback` を使用し、バックアップテーブル（`_bkp`）から `INSERT SELECT` で戻す。
3. **データ**: S3 `processed/` から直近成功バッチのエクスポートを再ロードし、mart を再構築。
4. **Terraform**: `terraform rollback` は存在しないため、`terraform apply` を逆差分で再実行するか、`terraform state` から対象リソースを削除し再適用する。必要に応じて `git revert` で IaC の変更を戻す。
5. **通知**: Slack で復旧ステータスを共有し、障害報告書に記録。

## 決定事項 / 未決事項
- **決定事項**
  - GitHub Actions を用いて dev→stg→prod の自動デプロイを実施し、Data API で Redshift DDL を適用する。
  - 破壊的変更は `apply_ddl.py` による検知と人間レビューを必須とする。
  - Secrets は GitHub Secrets / AWS Secrets Manager で管理し、コードに直書きしない。
- **未決事項**
  - stg 環境を常設するか、リリース前のみ起動するかコスト検討が必要。
  - `sqlfluff` のルールセット（標準 vs DPC カスタム）を決定する必要がある。
  - `docs/05_physical_ddl.sql` など DDL ファイルの自動生成方法（dbt run-operation vs 手書き）が未定。
