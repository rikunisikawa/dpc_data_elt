# タスク 08: エクスポートと可視化準備

## 目的
docs/07_elt_pipeline.md・docs/10_performance.md・docs/13_data_export.md の内容から、学習環境で必要最小限のデータエクスポートと可視化準備を行います。

## 前提条件
- タスク03で `export_parquet` Lambda が実装済み。
- QuickSight を利用する場合の権限 (IAM ロール `role-quicksight-dpc`) が作成済み。

## 手順
1. **Parquet エクスポート**
   - `export_parquet` Lambda で `UNLOAD` コマンドを実行し、`processed/yyyymm=<YYYY-MM>/` 配下に出力します。
   - 圧縮形式は `PARQUET` + `ZSTD` など標準設定で十分です。パーティションは `yyyymm` のみを利用します。
2. **CSV エクスポート（任意）**
   - docs/13_data_export.md に従い、UTF-8 (BOM なし) を採用します。
   - 施設コードの匿名化は学習用途では実施せず、原本のまま出力します。
3. **QuickSight 準備（後工程）**
   - 現段階では QuickSight の SPICE 容量や共有設定は決めず、Redshift へ接続できるロールのみに設定します。
   - ELT が安定稼働した後に SPICE データセットを作成し、ダッシュボード作成は後回しにします。
4. **成果物検証**
   - エクスポートしたファイルを Athena またはローカルツールで確認し、列数・件数が mart テーブルと一致するかチェックします。

## 完了条件
- `processed/` 配下に最新月の Parquet ファイルが生成されている。
- 必要に応じた CSV エクスポートが完了し、UTF-8 で正しく開ける。
- QuickSight への接続準備（ロール割当とデータソース作成）が完了しているが、ダッシュボードは未作成のまま保留されている。
