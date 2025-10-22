# DPC 学習基盤 データ提供（学習用エクスポート）設計

## 目的
mart 層から匿名化された集計データを CSV / Parquet 形式でエクスポートし、学習成果として提供する手順とフォーマットを定義する。

## 対象データ
| マート | 粒度 | 出力項目 |
| --- | --- | --- |
| `mart.fact_case_summary` | 症例単位 | facility_cd, data_id, dpc_code, length_of_stay, total_points, readmit_30d_flag, acuity_avg |
| `mart.fact_cost_monthly` | 施設×月 | facility_cd, year_month, inpatient_points, outpatient_points, inclusive_points, total_points |
| `mart.fact_dx_outcome` | 施設×月×DPC | facility_cd, year_month, dpc_code, cases, avg_los, mortality_rate, readmit_30d_rate |

## 出力形式
- **形式**: Parquet (Snappy) を標準、必要に応じて CSV。
- **出力先**: `s3://dpc-learning-data-<env>/processed/yyyymm=<YYYY-MM>/`
- **ファイル構成例**:
  - `case_summary/part-0000.parquet`
  - `cost_monthly/part-0000.parquet`
  - `dx_outcome/part-0000.parquet`
  - `metadata/data_dictionary.md`
  - `_SUCCESS`

## Export クエリ例
```sql
UNLOAD ('
    SELECT facility_cd, data_id, dpc_code, length_of_stay, total_points, readmit_30d_flag, acuity_avg
    FROM mart.fact_case_summary
    WHERE yyyymm = :yyyymm
')
TO 's3://dpc-learning-data-:env/processed/yyyymm=:yyyymm/case_summary/case_summary_'
IAM_ROLE 'arn:aws:iam::<account>:role/redshift-unload-role'
FORMAT AS PARQUET
PARTITION BY (facility_cd)
ALLOWOVERWRITE;
```

```sql
UNLOAD ('
    SELECT facility_cd, year_month, inpatient_points, outpatient_points, inclusive_points, total_points
    FROM mart.fact_cost_monthly
    WHERE year_month BETWEEN :yyyymm_start AND :yyyymm_end
')
TO 's3://dpc-learning-data-:env/processed/yyyymm=:yyyymm_end/cost_monthly/cost_'
IAM_ROLE 'arn:aws:iam::<account>:role/redshift-unload-role'
FORMAT AS PARQUET
ALLOWOVERWRITE;
```

## Lambda サンプル
`lambda_export.py`
```python
import os
import json
import datetime

import boto3

redshift = boto3.client("redshift-data")
s3 = boto3.client("s3")

ROLE_ARN = os.environ["REDSHIFT_UNLOAD_ROLE"]
BUCKET = os.environ["EXPORT_BUCKET"]


def handler(event, _):
    yyyymm = event["yyyymm"]
    env = event.get("env", "dev")
    prefix = f"processed/yyyymm={yyyymm}"

    statements = [
        (
            "case_summary",
            f"UNLOAD ('SELECT facility_cd, data_id, dpc_code, length_of_stay, total_points, readmit_30d_flag, acuity_avg "
            f"FROM mart.fact_case_summary WHERE yyyymm = ''{yyyymm}''') "
            f"TO ''s3://{BUCKET}/{prefix}/case_summary/case_summary_'' IAM_ROLE ''{ROLE_ARN}'' FORMAT AS PARQUET ALLOWOVERWRITE"
        ),
        (
            "cost_monthly",
            f"UNLOAD ('SELECT facility_cd, year_month, inpatient_points, outpatient_points, inclusive_points, total_points "
            f"FROM mart.fact_cost_monthly WHERE year_month = ''{yyyymm}''') "
            f"TO ''s3://{BUCKET}/{prefix}/cost_monthly/cost_'' IAM_ROLE ''{ROLE_ARN}'' FORMAT AS PARQUET ALLOWOVERWRITE"
        )
    ]

    for name, sql in statements:
        resp = redshift.execute_statement(
            ClusterIdentifier=os.environ["REDSHIFT_CLUSTER"],
            Database=os.environ["REDSHIFT_DB"],
            Sql=sql
        )
        redshift.get_statement_result(Id=resp["Id"])

    write_metadata(prefix, yyyymm, env)
    return {"status": "SUCCESS", "prefix": prefix}


def write_metadata(prefix: str, yyyymm: str, env: str):
    dictionary = {
        "generated_at": datetime.datetime.utcnow().isoformat(),
        "yyyymm": yyyymm,
        "environment": env,
        "datasets": [
            {
                "name": "case_summary",
                "columns": [
                    {"name": "facility_cd", "type": "CHAR(9)", "description": "施設コード"},
                    {"name": "data_id", "type": "CHAR(10)", "description": "症例ID"},
                    {"name": "dpc_code", "type": "CHAR(14)", "description": "DPCコード"},
                    {"name": "length_of_stay", "type": "INTEGER", "description": "入院日数"},
                    {"name": "total_points", "type": "INTEGER", "description": "総点数"},
                    {"name": "readmit_30d_flag", "type": "BOOLEAN", "description": "30日以内再入院フラグ"},
                    {"name": "acuity_avg", "type": "DECIMAL(6,3)", "description": "平均重症度"}
                ]
            },
            {
                "name": "cost_monthly",
                "columns": [
                    {"name": "facility_cd", "type": "CHAR(9)", "description": "施設コード"},
                    {"name": "year_month", "type": "CHAR(6)", "description": "年月"},
                    {"name": "inpatient_points", "type": "INTEGER", "description": "入院出来高点数"},
                    {"name": "outpatient_points", "type": "INTEGER", "description": "外来出来高点数"},
                    {"name": "inclusive_points", "type": "INTEGER", "description": "包括点数"},
                    {"name": "total_points", "type": "INTEGER", "description": "総点数"}
                ]
            }
        ]
    }

    s3.put_object(
        Bucket=BUCKET,
        Key=f"{prefix}/metadata/data_dictionary.json",
        Body=json.dumps(dictionary, ensure_ascii=False, indent=2).encode("utf-8")
    )
```

## データ辞書テンプレート
`metadata/data_dictionary.md`
```markdown
# DPC 学習基盤 学習用データ辞書

- 生成日時: {{ generated_at }}
- 対象年月: {{ yyyymm }}
- 環境: {{ environment }}

## case_summary
| 列名 | 型 | 説明 |
| --- | --- | --- |
| facility_cd | CHAR(9) | 施設コード（匿名化なし） |
| data_id | CHAR(10) | 症例ID（内部連番） |
| dpc_code | CHAR(14) | DPCコード |
| length_of_stay | INTEGER | 入院日数 |
| total_points | INTEGER | 包括＋出来高の総点数 |
| readmit_30d_flag | BOOLEAN | 30日以内再入院フラグ |
| acuity_avg | DECIMAL(6,3) | 平均重症度 |

## cost_monthly
| 列名 | 型 | 説明 |
| --- | --- | --- |
| facility_cd | CHAR(9) | 施設コード |
| year_month | CHAR(6) | 集計年月 |
| inpatient_points | INTEGER | 入院出来高点数 |
| outpatient_points | INTEGER | 外来出来高点数 |
| inclusive_points | INTEGER | 包括点数 |
| total_points | INTEGER | 合計点数 |

## バージョン管理
- 出力ごとにタグ `vYYYYMMDD-HHmm` を付与し、S3 `processed/` 内に `VERSION` ファイルを生成。
- Git リポジトリに `exports/<yyyymm>/metadata.json` を保存し、再現性を担保。

## 決定事項 / 未決事項
- **決定事項**
  - エクスポートは Redshift `UNLOAD` を利用し、Snappy Parquet で `processed/yyyymm=` 配下に格納する。
  - データ辞書 (JSON/Markdown) を同一プレフィックスに格納し、利用者が内容を確認できるようにする。
  - Lambda により定期的にエクスポートを実行し、Slack で完了通知を行う。
- **未決事項**
  - CSV 出力が必要な場合の文字コード（UTF-8 vs Shift_JIS）の選定が未確定。
  - 施設コードの匿名化要否（ハッシュ化するか）について利用部門と合意が必要。
  - バージョンタグと Git 管理の連携ルール（タグ命名規則など）の最終決定が未定。

## 学習環境向けミニマム実装ガイド

docs/07_elt_pipeline.md で定義した Step Functions から呼び出される `export_parquet` Lambda をベースに、学習環境で必要最小限のデー
タエクスポートと可視化準備を行う際の具体的な手順をまとめる。

### Parquet エクスポートの運用

- **出力タイミング**: ELT パイプラインの最終ステップで `dbt test` 成功後に実行する。リトライ上限に達した場合は Step Functions から失敗通知を送り、S3 の不完全な出力は運用 Runbook に従って削除する。
- **入力パラメータ**: Lambda のイベントには `yyyymm`（対象年月）、`env`（`dev`/`stg`/`prod` など）を渡す。Step Functions ではインプットの `yyyymm` をそのまま Lambda に引き継ぎ、デフォルトで最新バッチ年月が設定されるようにする。
- **環境変数**: `REDSHIFT_UNLOAD_ROLE`、`EXPORT_BUCKET`、`REDSHIFT_CLUSTER`、`REDSHIFT_DB` を Lambda の環境変数に登録し、コードを環境ごとに分岐させない。実行ロールは Redshift Data API・S3 書き込み権限・KMS 暗号化キー（必要に応じて）の利用権限を付与する。
- **UNLOAD 設定**: `FORMAT AS PARQUET` に加えて `PARQUETCOMPRESSION ZSTD` を指定し、学習環境でも本番相当のサイズ削減を実現する。フォルダ構成は `processed/yyyymm=<YYYY-MM>/<dataset>/` で統一し、書き出し完了後に `_SUCCESS` ファイルを作成して Athena 等の検証ジョブが idempotent に動作するようにする。
- **メタデータ出力**: `metadata/data_dictionary.json` を JSON 形式で同一プレフィックスに保存し、生成日時・対象年月・利用可能なデータセットとカラム定義を格納する。docs/10_performance.md の「データ量・性能要件」を参考に、利用者にレコード件数や予想ファイルサイズを伝えたい場合は同 JSON に補足情報を追加する。

### 任意の CSV エクスポート

- **用途**: 研修参加者が Excel などで軽量検証をしたいケースを想定し、Parquet に加えて一部データセット（例: `fact_cost_monthly`）を CSV として出力できるようにする。
- **フォーマット**: UTF-8（BOM なし）、カンマ区切り、ヘッダ行ありを標準とし、S3 では `processed/yyyymm=<YYYY-MM>/<dataset>/csv/` 配下に配置する。Lambda からの UNLOAD では `FORMAT AS CSV` と `ALLOWOVERWRITE` を指定し、列区切りや NULL 文字列は Redshift のデフォルト値を利用する。
- **施設コードの扱い**: 学習用途では匿名化せずに原本の施設コードを維持する。今後匿名化が求められた場合に備えて、カラムマスキング処理を別関数化し、Lambda の環境変数で有効化できるようにしておく。
- **バリデーション**: CSV を出力した場合は、`text/csv` で S3 に保存されているか、ダウンロード後に `nkf --guess` や `file` コマンドで文字コードを確認する。Excel で開いて文字化けしないことも確認ポイントとする。

### QuickSight 連携準備

- **IAM ロール**: QuickSight から Redshift に接続するため、`role-quicksight-dpc` に `AmazonQuickSightAccess` と対象 Redshift の `GetClusterCredentials`、S3 `processed/` バケットへの読み取り権限を付与する。QuickSight 側ではこのロールをデータソース作成時に指定する。
- **データソース**: QuickSight のデータソースは 2 系統を用意する。1 つ目は Redshift 直接接続で、mart スキーマを参照する。2 つ目は S3 ベースで、`processed/` 配下の Parquet を `manifest.json` 経由でロードできるようにする（現段階では SPICE 取り込みは不要）。
- **データセット定義**: ダッシュボード作成は後工程とし、今は QuickSight 上でデータセットのスキーマを登録するのみとする。S3 データセットでは `metadata/data_dictionary.json` を参照し、列型を手動で設定する。
- **アクセス管理**: QuickSight の共有設定やユーザー作成は行わず、管理者アカウントのみが接続確認を実施する。SPICE 容量やダッシュボード公開方針は ELT が安定稼働した後に決定する。

### エクスポート成果物の検証

- **Athena 検証**: S3 `processed/` バケットを対象に Glue テーブルを作成し、Athena で `SELECT COUNT(*)` や `SELECT * LIMIT 10` を実行して mart テーブルの件数・列構成と一致するか確認する。検証クエリの例は運用 Runbook に追記し、初回以降は Athena Workgroup のクエリ履歴を再利用する。
- **ローカル検証**: 研修環境では `aws s3 cp --recursive` で Parquet を取得し、`pyarrow` あるいは `pandas` を利用して行数・欠損値の有無をチェックする。CSV の場合は `wc -l` で件数を確認し、mart テーブルの件数と突合する。
- **自動チェック**: 将来的に Step Functions の最後に Athena クエリを実行する Lambda を追加し、エクスポート直後に件数検証を自動化する余地がある。現段階では手動チェックの手順を README に記載し、再現性を確保する。
