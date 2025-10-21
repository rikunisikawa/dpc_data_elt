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
