# タスク 05: S3 命名規約と手動取込運用の整備

## 目的
docs/03_s3_naming.md・docs/07_elt_pipeline.md を参照し、学習者が手動で DPC ファイルを S3 raw プレフィックスへアップロードできるよう運用手順を整備します。

## 前提条件
- タスク01で S3 バケットが作成済み。
- ローカルにアップロード対象の DPC サンプルファイルがある。

## 手順
1. **ローカル前処理テンプレートの用意**
   - `tools/prepare_upload.sh` などのスクリプトを作成し、`yyyymm` ディレクトリとファイル命名（`{facility}_{yyyymm}_{type}_{seq}.csv`）を自動生成できるようにします。
2. **マニフェスト作成**
   - docs/03_s3_naming.md の JSON スキーマを参考に `_manifest.json` を生成する Python またはシェルスクリプトを用意します。
   - `notes` 項目は任意入力のままとし、標準化は不要です。
3. **S3 アップロード**
   - AWS CLI (`aws s3 cp --recursive`) を使用し、`raw/yyyymm=<YYYY-MM>/<file_type>/` にファイルと `_manifest.json` をアップロードします。
   - アップロード後に `aws s3 ls` でファイル数を確認し、マニフェストの `records` 数が整合しているかチェックします。
4. **バリデーションテスト**
   - Step Functions を手動起動し、`validate_manifest` が成功することを確認します。
   - 失敗時は CloudWatch Logs を参照し、スキーマ・命名エラーを修正します。

## 完了条件
- `raw/yyyymm=<YYYY-MM>/` 配下に命名規約どおりのファイルと `_manifest.json` が配置されている。
- Step Functions 実行が manifest チェックを通過し、`CopyRaw` ステップまで進む。
- アップロード手順書またはスクリプトがリポジトリに保存されている。
