# DPC 学習基盤 dbt プロジェクト設計

## 目的
Redshift を対象とする dbt プロジェクトの構造、命名規約、テスト、ドキュメンテーション運用を定義する。

## プロジェクト構成
```
├── dbt_project.yml
├── packages.yml
├── models/
│   ├── raw/
│   │   └── src_y1_inpatient.sql
│   ├── stage/
│   │   ├── stg_y1_case.sql
│   │   ├── stg_ef_inpatient_detail.sql
│   │   └── ...
│   ├── mart/
│   │   ├── fact_case_summary.sql
│   │   ├── fact_cost_monthly.sql
│   │   └── fact_dx_outcome.sql
│   └── ref/
│       ├── dim_facility.sql
│       └── dim_dpc_code.sql
├── seeds/
│   └── icd10_master.csv
├── macros/
│   └── util.sql
├── tests/
│   ├── schema/
│   └── data/
└── snapshots/ (任意)
```

## 命名規約
| レイヤ | プレフィックス | 例 |
| --- | --- | --- |
| raw (ソース) | `src_` | `src_y1_inpatient` |
| stage | `stg_` | `stg_y1_case` |
| mart（ファクト） | `fact_` | `fact_case_summary` |
| mart（ディメンション） | `dim_` | `dim_facility` |
| 断面ビュー | `int_`（中間） | `int_patient_readmit` |
| テスト | `test_` | `test_cost_totals` |

- モデルファイル名と生成テーブル名は一致させる。
- dbt タグで層・ドメインを明示。例: `tags: ['layer:stage', 'domain:inpatient']`
- `meta` フィールドで所有者、データ品質責任者を記載。

## モデル設定例
`models/stage/stg_y1_case.sql`
```sql
{{ config(
    materialized='incremental',
    unique_key=['facility_cd', 'data_id'],
    on_schema_change='sync_all_columns',
    tags=['layer:stage', 'domain:inpatient'],
    meta={'owner': 'data-eng', 'dq_owner': 'analytics'}
) }}

select
    facility_cd,
    data_id,
    admission_date,
    discharge_date,
    datediff(day, admission_date, discharge_date) + 1 as length_of_stay,
    sex_code as patient_sex,
    birth_date,
    age,
    dpc_code,
    main_icd10,
    surgery_flag,
    emergency_flag,
    outcome_code,
    insurance_type,
    current_timestamp as created_at
from {{ source('raw', 'y1_inpatient') }}
```

## テストポリシー
| テスト種別 | 適用例 |
| --- | --- |
| `not_null` | `stg_y1_case.facility_cd`, `fact_case_summary.total_points` |
| `unique` | `stg_y1_case` の `(facility_cd, data_id)` |
| `relationships` | `fact_case_summary.facility_cd` → `dim_facility.facility_cd` |
| `accepted_values` | `fact_case_summary.outcome_code` (例: `['01', '02', '99']`) |
| カスタム (SQL) | `fact_cost_monthly.total_points = sum(category_points)` |

### tests/schema/fact_case_summary.yml（抜粋）
```yaml
version: 2
models:
  - name: fact_case_summary
    description: "症例単位のサマリファクト"
    columns:
      - name: facility_cd
        tests:
          - not_null
          - relationships:
              to: ref('dim_facility')
              field: facility_cd
      - name: data_id
        tests:
          - not_null
          - unique:
              combination_of_columns: true
      - name: outcome_code
        tests:
          - accepted_values:
              values: ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '99']
```

## ドキュメンテーション
- `dbt docs generate` を日次バッチ後に実行し、`docs/` を S3 `processed/docs/` へアップロード。
- モデル記述 (`description`) は日本語 + 英語短文（任意）で記載。
- `meta` に SLA (`refresh_frequency`) や問い合わせ窓口 (`contact`) を追加。

## `dbt_project.yml` サンプル
```yaml
name: dpc_learning
version: 1.0.0
config-version: 2
defaults:
  target: dev
  outputs:
    dev:
      type: redshift
      host: {{ env_var('DPC_REDSHIFT_HOST') }}
      user: {{ env_var('DPC_REDSHIFT_USER') }}
      password: {{ env_var('DPC_REDSHIFT_PASSWORD') }}
      port: 5439
      dbname: dpc
      schema: stage
      threads: 6
      keepalives_idle: 240
models:
  +materialized: table
  raw:
    +schema: raw
    +materialized: view
  stage:
    +schema: stage
    +materialized: incremental
  mart:
    +schema: mart
    +materialized: table
  ref:
    +schema: ref
    +materialized: table
seeds:
  +schema: ref
  +column_types:
    icd10_code: varchar(10)
```

## `models.yml` サンプル
```yaml
version: 2
models:
  - name: stg_y1_case
    description: "様式1から症例単位の整形を行う"
    tags: ['layer:stage', 'domain:inpatient']
    meta:
      owner: data-eng
      dq_owner: analytics
      refresh_frequency: daily
    columns:
      - name: facility_cd
        description: "DPC提出施設コード"
        tests:
          - not_null
      - name: data_id
        description: "症例ID"
        tests:
          - not_null
          - unique:
              combination_of_columns: true
      - name: length_of_stay
        description: "入院日数"
        tests:
          - not_null
          - relationships:
              to: ref('dim_date')
              field: date_key
              field: date_key
              # 日付ディムは別途参照

  - name: fact_case_summary
    description: "症例単位の集計結果"
    tags: ['layer:mart', 'domain:inpatient']
    meta:
      owner: analytics
      dq_owner: analytics
      refresh_frequency: daily
      contact: dpc-analytics@example.jp
    columns:
      - name: facility_cd
        description: "施設コード"
        tests:
          - not_null
          - relationships:
              to: ref('dim_facility')
              field: facility_cd
      - name: total_points
        description: "包括+出来高点数の合計"
        tests:
          - not_null
      - name: readmit_30d_flag
        description: "30日以内再入院フラグ"
        tests:
          - accepted_values:
              values: [0, 1]
```

## CI / 実行フロー
1. `dbt deps` – パッケージ同期。
2. `dbt seed` – マスタのロード（icd10 等）。
3. `dbt run --select stage` – ステージング。
4. `dbt run --select mart` – mart 構築。
5. `dbt test` – スキーマテストとデータテスト。
6. `dbt docs generate` – ドキュメント生成。

## 決定事項 / 未決事項
- **決定事項**
  - モデル命名は `stg_`, `fact_`, `dim_` をプレフィックスとし、タグでレイヤとドメインを明示する。
  - `dbt docs generate` を日次で実行し、成果を S3 `processed/docs/` へ保存する。
  - `dbt test` の標準テスト（not_null, unique, relationships, accepted_values）を必須とする。
- **未決事項**
  - dbt 実行基盤を Lambda コンテナとするか CodeBuild とするか最終判断が必要。
  - `meta` 情報で管理する SLA 項目の標準フォーマット（例: `HH:MM`）が未定。
  - カスタムテストをどのレベルで共有 (packages) するか要検討。
