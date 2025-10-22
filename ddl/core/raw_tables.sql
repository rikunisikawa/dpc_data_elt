-- Core raw schema tables required for COPY operations
-- Source: docs/05_physical_ddl.md

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
