{{ config(
    materialized='view',
    tags=['layer:raw', 'domain:inpatient'],
    meta={'owner': 'data-eng'}
) }}

select *
from {{ source('raw', 'y1_inpatient') }}
