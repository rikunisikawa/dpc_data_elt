{{ config(
    materialized='table',
    tags=['layer:mart', 'domain:inpatient'],
    meta={'owner': 'analytics', 'dq_owner': 'analytics', 'refresh_frequency': 'daily'}
) }}

with cases as (
    select
        facility_cd,
        data_id,
        length_of_stay,
        total_points,
        case when length_of_stay <= 30 then 1 else 0 end as readmit_30d_flag
    from {{ ref('stg_y1_case') }}
)

select
    c.facility_cd,
    f.facility_name,
    count(distinct c.data_id) as case_count,
    sum(c.total_points) as total_points,
    avg(c.length_of_stay) as avg_length_of_stay,
    sum(c.readmit_30d_flag) as readmit_30d_cases
from cases c
left join {{ ref('dim_facility') }} f on c.facility_cd = f.facility_cd
group by 1, 2
