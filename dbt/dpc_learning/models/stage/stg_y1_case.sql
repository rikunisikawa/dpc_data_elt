{{ config(
    materialized='incremental',
    unique_key=['facility_cd', 'data_id'],
    on_schema_change='sync_all_columns',
    tags=['layer:stage', 'domain:inpatient'],
    meta={'owner': 'data-eng', 'dq_owner': 'analytics'}
) }}

with base as (
    select
        facility_cd,
        data_id,
        admission_date,
        discharge_date,
        datediff(day, admission_date, discharge_date) + 1 as length_of_stay,
        sex_code,
        birth_date,
        dpc_code,
        main_icd10,
        total_points,
        current_timestamp as ingested_at
    from {{ ref('src_y1_inpatient') }}
)

select
    facility_cd,
    data_id,
    admission_date,
    discharge_date,
    length_of_stay,
    sex_code,
    birth_date,
    dpc_code,
    main_icd10,
    total_points,
    ingested_at
from base
{% if is_incremental() %}
where ingested_at > (select coalesce(max(ingested_at), '1900-01-01') from {{ this }})
{% endif %}
