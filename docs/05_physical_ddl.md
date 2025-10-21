# DPC 学習基盤 物理データモデル設計（Amazon Redshift DDL）

## 方針
- スキーマ: `raw`, `stage`, `mart`, `ref`, `dq`。
- 文字列は可能な限り `VARCHAR` 指定、原本仕様に合わせて固定長は `CHAR`。
- 主要ファクトは `DISTKEY(facility_cd)`、`SORTKEY` は症例キーや日付を組み合わせる。
- PRIMARY KEY / FOREIGN KEY は `NOT ENFORCED` で宣言し、クエリ最適化ヒントとして活用。
- `ENCODE AUTO` を採用し、初期ロード後に `ANALYZE COMPRESSION` を実施。

## raw スキーマ DDL
```sql
-- raw スキーマ作成
CREATE SCHEMA IF NOT EXISTS raw;

-- 様式1 (退院患者調査票)
CREATE TABLE IF NOT EXISTS raw.y1_inpatient (
    facility_cd       CHAR(9)   NOT NULL,
    data_id           CHAR(10)  NOT NULL,
    admission_date    DATE,
    discharge_date    DATE,
    sex_code          CHAR(1),
    birth_date        DATE,
    age               SMALLINT,
    dpc_code          CHAR(14),
    main_icd10        VARCHAR(10),
    outcome_code      CHAR(2),
    emergency_flag    CHAR(1),
    surgery_flag      CHAR(1),
    height_cm         DECIMAL(5,2),
    weight_kg         DECIMAL(5,2),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE raw.y1_inpatient
    ADD PRIMARY KEY (facility_cd, data_id) NOT ENFORCED;

-- 様式3 (施設情報)
CREATE TABLE IF NOT EXISTS raw.y3_facility (
    facility_cd       CHAR(9)  NOT NULL,
    report_year       CHAR(4)  NOT NULL,
    facility_name     VARCHAR(120),
    bed_function_code CHAR(2),
    hospital_group    VARCHAR(40),
    pref_code         CHAR(2),
    city_code         CHAR(5),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE ALL
SORTKEY(facility_cd)
ENCODE AUTO;
ALTER TABLE raw.y3_facility
    ADD PRIMARY KEY (facility_cd, report_year) NOT ENFORCED;

-- 様式4 (非保険症例)
CREATE TABLE IF NOT EXISTS raw.y4_noncovered (
    facility_cd        CHAR(9)  NOT NULL,
    data_id            CHAR(10) NOT NULL,
    noncovered_reason  CHAR(2),
    noncovered_amount  INTEGER,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE raw.y4_noncovered
    ADD PRIMARY KEY (facility_cd, data_id) NOT ENFORCED;

-- EF (入院)
CREATE TABLE IF NOT EXISTS raw.ef_inpatient (
    facility_cd       CHAR(9)  NOT NULL,
    data_id           CHAR(10) NOT NULL,
    seq_no            INTEGER  NOT NULL,
    detail_no         INTEGER  NOT NULL,
    service_date      DATE,
    service_code      VARCHAR(12),
    unit_code         VARCHAR(3),
    qty               DECIMAL(10,3),
    points            INTEGER,
    yen_flag          CHAR(1),
    doctor_code       VARCHAR(10),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id, seq_no)
ENCODE AUTO;
ALTER TABLE raw.ef_inpatient
    ADD PRIMARY KEY (facility_cd, data_id, seq_no, detail_no) NOT ENFORCED;

-- EF (外来)
CREATE TABLE IF NOT EXISTS raw.ef_outpatient (
    facility_cd       CHAR(9)  NOT NULL,
    data_id           CHAR(10) NOT NULL,
    seq_no            INTEGER  NOT NULL,
    detail_no         INTEGER  NOT NULL,
    visit_date        DATE,
    service_code      VARCHAR(12),
    qty               DECIMAL(10,3),
    points            INTEGER,
    yen_flag          CHAR(1),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id, seq_no)
ENCODE AUTO;
ALTER TABLE raw.ef_outpatient
    ADD PRIMARY KEY (facility_cd, data_id, seq_no, detail_no) NOT ENFORCED;

-- D ファイル
CREATE TABLE IF NOT EXISTS raw.d_inclusive (
    facility_cd        CHAR(9)  NOT NULL,
    data_id            CHAR(10) NOT NULL,
    segment_no         SMALLINT NOT NULL,
    dpc_code           CHAR(14),
    start_date         DATE,
    end_date           DATE,
    inclusive_points   INTEGER,
    adjust_points      INTEGER,
    reason_code        CHAR(2),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE raw.d_inclusive
    ADD PRIMARY KEY (facility_cd, data_id, segment_no) NOT ENFORCED;

-- H ファイル
CREATE TABLE IF NOT EXISTS raw.h_daily (
    facility_cd     CHAR(9)  NOT NULL,
    data_id         CHAR(10) NOT NULL,
    eval_date       DATE     NOT NULL,
    seq_no          SMALLINT NOT NULL,
    item_code       VARCHAR(6),
    severity_score  SMALLINT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id, eval_date)
ENCODE AUTO;
ALTER TABLE raw.h_daily
    ADD PRIMARY KEY (facility_cd, data_id, eval_date, seq_no) NOT ENFORCED;

-- K ファイル
CREATE TABLE IF NOT EXISTS raw.k_common_id (
    facility_cd       CHAR(9)  NOT NULL,
    data_id           CHAR(10) NOT NULL,
    common_patient_id VARCHAR(40) NOT NULL,
    birth_month       DATE,
    insurer_no        VARCHAR(8),
    subscriber_no     VARCHAR(8),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE raw.k_common_id
    ADD PRIMARY KEY (facility_cd, data_id) NOT ENFORCED;
```

## stage スキーマ DDL
```sql
CREATE SCHEMA IF NOT EXISTS stage;

-- 様式1 クレンジングビュー相当テーブル
CREATE TABLE IF NOT EXISTS stage.y1_case (
    facility_cd        CHAR(9)   NOT NULL,
    data_id            CHAR(10)  NOT NULL,
    admission_date     DATE,
    discharge_date     DATE,
    length_of_stay     INTEGER,
    patient_sex        CHAR(1),
    birth_date         DATE,
    age                SMALLINT,
    dpc_code           CHAR(14),
    main_icd10         VARCHAR(10),
    surgery_flag       CHAR(1),
    emergency_flag     CHAR(1),
    outcome_code       CHAR(2),
    insurance_type     VARCHAR(4),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE stage.y1_case
    ADD PRIMARY KEY (facility_cd, data_id) NOT ENFORCED;

-- EF 統合テーブル (E × F)
CREATE TABLE IF NOT EXISTS stage.ef_inpatient_detail (
    facility_cd        CHAR(9)   NOT NULL,
    data_id            CHAR(10)  NOT NULL,
    seq_no             INTEGER   NOT NULL,
    detail_no          INTEGER   NOT NULL,
    service_date       DATE,
    master_code        VARCHAR(12),
    category_code      VARCHAR(4),
    unit_code          VARCHAR(3),
    qty                DECIMAL(12,3),
    order_count        DECIMAL(12,3),
    total_qty          DECIMAL(12,3),
    points             INTEGER,
    yen_flag           CHAR(1),
    points_yen         DECIMAL(12,2),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id, seq_no)
ENCODE AUTO;
ALTER TABLE stage.ef_inpatient_detail
    ADD PRIMARY KEY (facility_cd, data_id, seq_no, detail_no) NOT ENFORCED;
ALTER TABLE stage.ef_inpatient_detail
    ADD FOREIGN KEY (facility_cd, data_id) REFERENCES stage.y1_case NOT ENFORCED;

-- D 包括テーブル
CREATE TABLE IF NOT EXISTS stage.d_inclusive_detail (
    facility_cd        CHAR(9)  NOT NULL,
    data_id            CHAR(10) NOT NULL,
    segment_no         SMALLINT NOT NULL,
    dpc_code           CHAR(14),
    inclusive_points   INTEGER,
    adjust_points      INTEGER,
    reason_code        CHAR(2),
    bundle_days        INTEGER,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE stage.d_inclusive_detail
    ADD PRIMARY KEY (facility_cd, data_id, segment_no) NOT ENFORCED;

-- H 集約テーブル
CREATE TABLE IF NOT EXISTS stage.h_daily_score (
    facility_cd       CHAR(9)  NOT NULL,
    data_id           CHAR(10) NOT NULL,
    eval_date         DATE     NOT NULL,
    severity_score    SMALLINT,
    acuity_flag       BOOLEAN,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id, eval_date)
ENCODE AUTO;
ALTER TABLE stage.h_daily_score
    ADD PRIMARY KEY (facility_cd, data_id, eval_date) NOT ENFORCED;

-- 患者ディメンション候補
CREATE TABLE IF NOT EXISTS stage.patient_dim_seed (
    common_patient_id VARCHAR(40) NOT NULL,
    facility_cd       CHAR(9)     NOT NULL,
    data_id           CHAR(10)    NOT NULL,
    birth_month       DATE,
    sex_code          CHAR(1),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
```

## mart スキーマ DDL
```sql
CREATE SCHEMA IF NOT EXISTS mart;

-- 症例サマリファクト
CREATE TABLE IF NOT EXISTS mart.fact_case_summary (
    case_sk            BIGINT IDENTITY(1,1),
    facility_cd        CHAR(9)   NOT NULL,
    data_id            CHAR(10)  NOT NULL,
    common_patient_id  VARCHAR(40),
    admission_date     DATE,
    discharge_date     DATE,
    length_of_stay     INTEGER,
    dpc_code           CHAR(14),
    main_icd10         VARCHAR(10),
    sex_code           CHAR(1),
    age                SMALLINT,
    surgery_flag       CHAR(1),
    emergency_flag     CHAR(1),
    outcome_code       CHAR(2),
    total_points       INTEGER,
    inclusive_points   INTEGER,
    ffs_points         INTEGER,
    noncovered_flag    BOOLEAN,
    readmit_7d_flag    BOOLEAN,
    readmit_30d_flag   BOOLEAN,
    acuity_avg         DECIMAL(6,3),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, data_id)
ENCODE AUTO;
ALTER TABLE mart.fact_case_summary
    ADD PRIMARY KEY (facility_cd, data_id) NOT ENFORCED;
ALTER TABLE mart.fact_case_summary
    ADD FOREIGN KEY (facility_cd) REFERENCES ref.dim_facility(facility_cd) NOT ENFORCED;
ALTER TABLE mart.fact_case_summary
    ADD FOREIGN KEY (dpc_code) REFERENCES ref.dim_dpc_code(dpc_code) NOT ENFORCED;

-- 月次コストファクト
CREATE TABLE IF NOT EXISTS mart.fact_cost_monthly (
    facility_cd        CHAR(9)   NOT NULL,
    year_month         CHAR(6)   NOT NULL,
    inpatient_points   INTEGER,
    outpatient_points  INTEGER,
    inclusive_points   INTEGER,
    drug_points        INTEGER,
    material_points    INTEGER,
    surgery_points     INTEGER,
    other_points       INTEGER,
    total_points       INTEGER,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, year_month)
ENCODE AUTO;
ALTER TABLE mart.fact_cost_monthly
    ADD PRIMARY KEY (facility_cd, year_month) NOT ENFORCED;
ALTER TABLE mart.fact_cost_monthly
    ADD FOREIGN KEY (facility_cd) REFERENCES ref.dim_facility(facility_cd) NOT ENFORCED;

-- 疾患別アウトカムファクト
CREATE TABLE IF NOT EXISTS mart.fact_dx_outcome (
    facility_cd        CHAR(9)   NOT NULL,
    year_month         CHAR(6)   NOT NULL,
    dpc_code           CHAR(14)  NOT NULL,
    cases              INTEGER,
    avg_los            DECIMAL(6,2),
    mortality_rate     DECIMAL(5,2),
    readmit_30d_rate   DECIMAL(5,2),
    avg_acuity         DECIMAL(6,3),
    surgery_ratio      DECIMAL(5,2),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTKEY(facility_cd)
SORTKEY(facility_cd, dpc_code)
ENCODE AUTO;
ALTER TABLE mart.fact_dx_outcome
    ADD PRIMARY KEY (facility_cd, year_month, dpc_code) NOT ENFORCED;
ALTER TABLE mart.fact_dx_outcome
    ADD FOREIGN KEY (facility_cd) REFERENCES ref.dim_facility(facility_cd) NOT ENFORCED;
ALTER TABLE mart.fact_dx_outcome
    ADD FOREIGN KEY (dpc_code) REFERENCES ref.dim_dpc_code(dpc_code) NOT ENFORCED;
```

## ref スキーマ DDL
```sql
CREATE SCHEMA IF NOT EXISTS ref;

-- 施設ディメンション
CREATE TABLE IF NOT EXISTS ref.dim_facility (
    facility_cd        CHAR(9)  NOT NULL,
    facility_name      VARCHAR(120),
    facility_name_kana VARCHAR(180),
    bed_function_code  CHAR(2),
    hospital_group     VARCHAR(40),
    pref_code          CHAR(2),
    medical_region     VARCHAR(10),
    dpc_category       VARCHAR(20),
    coefficient_i      DECIMAL(6,4),
    coefficient_ii     DECIMAL(6,4),
    is_dpc_hospital    BOOLEAN,
    effective_from     DATE,
    effective_to       DATE,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE ALL
SORTKEY(facility_cd)
ENCODE AUTO;
ALTER TABLE ref.dim_facility
    ADD PRIMARY KEY (facility_cd, effective_from) NOT ENFORCED;

-- DPC コードディメンション
CREATE TABLE IF NOT EXISTS ref.dim_dpc_code (
    dpc_code           CHAR(14) NOT NULL,
    mdc_code           CHAR(2),
    mdc_name           VARCHAR(80),
    diagnosis_name     VARCHAR(160),
    surgery_category   VARCHAR(80),
    resource_level     VARCHAR(40),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE ALL
SORTKEY(dpc_code)
ENCODE AUTO;
ALTER TABLE ref.dim_dpc_code
    ADD PRIMARY KEY (dpc_code) NOT ENFORCED;

-- ICD10 ディメンション
CREATE TABLE IF NOT EXISTS ref.dim_icd10 (
    icd10_code         VARCHAR(10) NOT NULL,
    block_code         VARCHAR(4),
    chapter_code       VARCHAR(2),
    japanese_name      VARCHAR(255),
    english_name       VARCHAR(255),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE ALL
SORTKEY(icd10_code)
ENCODE AUTO;
ALTER TABLE ref.dim_icd10
    ADD PRIMARY KEY (icd10_code) NOT ENFORCED;

-- 日付ディメンション
CREATE TABLE IF NOT EXISTS ref.dim_date (
    date_key           DATE NOT NULL,
    year               SMALLINT,
    quarter            SMALLINT,
    month              SMALLINT,
    day                SMALLINT,
    year_month         CHAR(6),
    week               SMALLINT,
    weekday            SMALLINT,
    is_holiday         BOOLEAN,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE ALL
SORTKEY(date_key)
ENCODE AUTO;
ALTER TABLE ref.dim_date
    ADD PRIMARY KEY (date_key) NOT ENFORCED;
```

## dq スキーマ DDL
```sql
CREATE SCHEMA IF NOT EXISTS dq;

CREATE TABLE IF NOT EXISTS dq.results_yyyymm (
    result_id     BIGINT IDENTITY(1,1),
    facility_cd   CHAR(9)   NOT NULL,
    yyyymm        CHAR(6)   NOT NULL,
    rule_id       VARCHAR(64) NOT NULL,
    severity      VARCHAR(10) NOT NULL,
    cnt           INTEGER NOT NULL,
    sample_keys   VARCHAR(500),
    note          VARCHAR(500),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTSTYLE AUTO
SORTKEY(yyyymm, rule_id);
```

## 設計注記
- raw 層はソース項目をそのまま保持。NULL 許容はソースに合わせ柔軟に定義。
- stage 層の `total_qty` は `qty * order_count` を算出して格納し、下流での再計算を不要にする。
- mart 層は分析で頻繁に利用する派生指標（再入院フラグ、重症度平均）を事前計算。
- ref 層は DIM テーブルの変遷管理を想定し、`effective_from` / `effective_to` を設けて SCD2 に対応可能。
- dq スキーマは月次単位で結果を保持し、Slack 通知時に参照する。

## 決定事項 / 未決事項
- **決定事項**
  - ファクト系テーブルは `DISTKEY(facility_cd)` を採用し、施設単位でノード局所性を確保する。
  - ソートキーは `facility_cd + data_id`（症例）または `facility_cd + year_month` を基本とし、時系列クエリ性能を優先。
  - DDL は `ENCODE AUTO` を標準とし、初回ロード後に圧縮推奨値を適用する。
- **未決事項**
  - stage 層に設ける派生列（例: 点数→円換算）の種類と範囲を部門と調整する必要がある。
  - mart 層で保持する再入院フラグの判定期間（7日, 30日 以外）の追加要望を確認する必要がある。
  - `dq.results_yyyymm` の保持期間（例: 24 か月）とアーカイブ方式が未定。
