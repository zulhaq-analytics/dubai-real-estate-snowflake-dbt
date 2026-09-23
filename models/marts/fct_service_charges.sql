with rates as (

    select * from {{ ref('int_service_charges__project_rates') }}

),

projects as (

    select project_id, area_id
    from {{ ref('stg_dld__projects') }}

)

select
    r.project_id,
    p.area_id,
    r.budget_year,
    r.category_count,
    r.rate_aed_per_sqft,
    r.rate_aed_per_sqm,
    r.is_rate_valid,
    r.is_latest_valid_year
from rates r
left join projects p
    on r.project_id = p.project_id