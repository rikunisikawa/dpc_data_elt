{{ config(
    materialized='table',
    tags=['layer:ref', 'domain:shared'],
    meta={'owner': 'data-eng', 'refresh_frequency': 'weekly'}
) }}

select
    facility_cd,
    facility_name,
    prefecture
from {{ ref('facility_master') }}
