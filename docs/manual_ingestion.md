# 手動アップロード運用ガイド

このガイドでは、学習用 DPC データを S3 `raw/` プレフィックスへ配置するための手順を説明します。`docs/03_s3_naming.md` の命名規約に沿ってファイルを整理し、マニフェストを生成するために `tools/prepare_upload.sh` と `tools/generate_manifest.py` を利用します。

## 前提条件
- AWS CLI で対象バケットへアップロードできる IAM 認証情報を保有していること。
- ローカルにアップロード対象の DPC サンプルファイルが存在すること。
- Python 3.8 以上と Bash が利用できること。

## 1. ディレクトリとファイル名の整備
`tools/prepare_upload.sh` はファイルを命名規約に合わせて配置する補助スクリプトです。

```bash
# 例: 131000123 施設の 2025 年 4 月分 y1 を整備
./tools/prepare_upload.sh \
  --facility 131000123 \
  --month 2025-04 \
  --file-type y1 \
  --input ~/Downloads/y1_202504.csv \
  --dest ./upload_work
```

実行すると、`upload_work/raw/yyyymm=2025-04/y1/131000123_202504_y1_001.csv` のような構造が作成されます。既存ファイルがある場合は連番を自動採番します。`--dry-run` を指定するとコピーを行わずに結果だけ確認できます。

## 2. `_manifest.json` の生成
`tools/generate_manifest.py` で監査マニフェストを作成します。

```bash
./tools/generate_manifest.py upload_work/raw/yyyymm=2025-04/y1 \
  --facility 131000123 \
  --yyyymm 202504 \
  --file-type y1 \
  --data-file upload_work/raw/yyyymm=2025-04/y1/131000123_202504_y1_001.csv \
  --has-header \
  --notes "2025年度1Q診療分"
```

- `--data-file` を指定するとファイルのレコード数とハッシュ値を自動算出します。ハッシュアルゴリズムは既定で `SHA256` です。別ファイルを集計した場合は `--records` や `--hash-value` を手動で渡せます。
- `_manifest.json` が既に存在する場合は `--overwrite` を付与してください。
- ディレクトリ構造が命名規約 (`raw/yyyymm=<YYYY-MM>/<file_type>/`) と異なる場合は警告が表示されます。チェックを厳格化したい場合は `--strict-path` を付けるとエラー扱いになります。

生成されたマニフェストは命名規約に準拠した JSON になり、Lambda の検証にそのまま利用できます。

## 3. S3 へのアップロード
準備したディレクトリを AWS CLI でアップロードします。

```bash
aws s3 cp ./upload_work/raw/ s3://dpc-learning-data-dev/raw/ --recursive
```

アップロード後はファイル数と `_manifest.json` の `records` が整合しているかを確認します。

```bash
aws s3 ls s3://dpc-learning-data-dev/raw/yyyymm=2025-04/y1/
```

## 4. Step Functions の手動実行
S3 への配置後、Step Functions で `validate_manifest` ステップを手動起動し、検証結果を確認してください。失敗時は CloudWatch Logs を参照し、命名やマニフェストの修正を実施します。

## 付録: よくあるエラー
| 事象 | 対処 |
| --- | --- |
| `Facility code must be 9 digits` | 9 桁ゼロ埋めになっているか確認する。|
| `Month must be in YYYYMM or YYYY-MM format` | `202504` か `2025-04` で指定する。|
| `Target sequence already exists` | 同じ施設・月・ファイル種別で連番が重複していないか確認する。|
| `Error: --records or --data-file must be provided.` | マニフェスト生成時に `--records` を入力するか対象ファイルを `--data-file` で指定する。|

これらの手順を用いることで、docs/03_s3_naming.md の命名規約を満たした状態で手動アップロードを実施できます。
