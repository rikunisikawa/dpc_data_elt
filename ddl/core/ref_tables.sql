-- Core reference schema tables required by mart fact tables
-- Source: docs/05_physical_ddl.md

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
