-- Core mart schema tables for downstream analytics
-- Source: docs/05_physical_ddl.md

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
