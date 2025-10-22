# タスク 04: dbt プロジェクトの初期化

## 目的
docs/06_dbt_project.md と docs/05_physical_ddl.md に沿って、Redshift 向け dbt プロジェクトを最小構成で初期化し、ECS タスクから実行できるようにします。

## 前提条件
- タスク02で Redshift スキーマが作成済み。
- Git リポジトリ（CodeCommit/GitHub）を利用できる。

## 手順
1. **dbt プロジェクト作成**
   - `dbt init dpc_learning` を実行し、Profile は Redshift Serverless Data API を使用するよう設定します。
   - `profiles.yml` には Secrets Manager のクレデンシャルを参照する環境変数（例: `DBT_RS_SECRET_ARN`）を使用します。
2. **モデルの配置**
   - `models/raw/` に COPY 後の外部参照用ビュー、`models/stage/` と `models/mart/` に最小限の変換ロジックを作成します。
   - 初期段階では `select * from {{ source('raw', 'y1') }}` などのパススルーモデルから開始し、徐々に集計ロジックを追加します。
3. **sources と seeds**
   - docs/03_s3_naming.md の規約に基づき、`sources.yml` を作成して raw スキーマのテーブルを宣言します。
   - 学習に必要な辞書データがあれば `data/` 配下に seed CSV を置き、`dbt seed` でロードします。
4. **tests とメタ情報**
   - 主要キーに対する `unique`, `not_null` テストを追加します。
   - `schema.yml` の `meta` には当面 `owner: "data-eng"` 程度の最小情報のみ記載し、SLA 詳細は後続の拡張に任せます。
5. **コンテナ実行向け設定**
   - `packages.yml` や `requirements.txt` を整備し、ECS コンテナビルド時にインストールします。
   - `dbt_project.yml` の `target-path` を `/tmp` など書き込み可能な場所に設定し、ECS タスクで権限エラーを避けます。

## 完了条件
- Git リポジトリに dbt プロジェクトがコミットされている。
- `dbt deps`, `dbt seed`, `dbt run`, `dbt test` がローカルまたは ECS タスクで完了する。
- Redshift 上に dbt モデルで生成されたビュー/テーブルが作成されている。
