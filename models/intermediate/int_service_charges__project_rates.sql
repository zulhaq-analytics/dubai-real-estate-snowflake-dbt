with charges as (

    select * from {{ ref('stg_dld__service_charges') }}
    where usage_name_en = 'Residential'
      and project_id is not null

),

project_year as (

    select
        project_id,
        budget_year,
        count(*)                                           as category_count,
        sum(service_cost)                                  as rate_aed_per_sqft
    from charges
    group by 1, 2

),

flagged as (

    select
        project_id,
        budget_year,
        category_count,
        rate_aed_per_sqft,
        rate_aed_per_sqft * 10.7639                        as rate_aed_per_sqm,
        (rate_aed_per_sqft between 1 and 100)              as is_rate_valid
    from project_year

)

select
    f.*,
    (
        f.is_rate_valid
        and f.budget_year = max(case when f.is_rate_valid then f.budget_year end)
                                over (partition by f.project_id)
    )                                                      as is_latest_valid_year
from flagged f
