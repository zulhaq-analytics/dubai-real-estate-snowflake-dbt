{{ config(materialized='table') }}

-- One row per project: off-plan launch absorption.
-- Off-plan sales include some resales before handover, so absorption is measured
-- over each project's first 12 months (when resales are rare) and capped at 100%.

with sales as (

    select project_number, transaction_date
    from {{ ref('fct_transactions') }}
    where is_sale
      and is_off_plan
      and project_number is not null

),

as_of as (

    select max(transaction_date) as as_of_date
    from {{ ref('fct_transactions') }}

),

projects as (

    select
        project_number,
        project_name_en,
        developer_name,
        area_id,
        area_name_en,
        project_status,
        project_status_label,
        no_of_units
    from {{ ref('dim_project') }}
    where project_number is not null
    qualify row_number() over (partition by project_number order by no_of_units desc nulls last) = 1

),

ranked as (

    select
        project_number,
        transaction_date,
        row_number() over (partition by project_number order by transaction_date) as sale_seq
    from sales

),

launch as (

    select
        project_number,
        min(transaction_date) as first_sale_date,
        count(*)              as total_offplan_sales
    from sales
    group by 1

),

first_year as (

    select
        l.project_number,
        count_if(r.transaction_date < {{ dbt.dateadd('month', 12, 'l.first_sale_date') }}) as sales_first_12m
    from launch l
    join ranked r
      on r.project_number = l.project_number
    group by 1

),

half_sold as (

    select
        r.project_number,
        min(r.transaction_date) as half_sold_date
    from ranked r
    join projects p
      on p.project_number = r.project_number
    where p.no_of_units > 0
      and r.sale_seq >= p.no_of_units * 0.5
    group by 1

)

select
    p.project_number,
    p.project_name_en,
    p.developer_name,
    p.area_id,
    p.area_name_en,
    p.project_status,
    p.project_status_label,
    p.no_of_units,
    l.first_sale_date,
    year(l.first_sale_date)                                          as launch_year,
    l.total_offplan_sales,
    f.sales_first_12m,
    least(f.sales_first_12m / nullif(p.no_of_units, 0), 1)           as first_year_absorption,
    h.half_sold_date,
    datediff('month', l.first_sale_date, h.half_sold_date)           as months_to_half_sold,
    (
        p.no_of_units >= 20
        and l.first_sale_date >= '2015-01-01'
        and l.first_sale_date <= {{ dbt.dateadd('month', -12, 'a.as_of_date') }}
    )                                                                as is_absorption_eligible
from projects p
join launch l      on l.project_number = p.project_number
join first_year f  on f.project_number = p.project_number
left join half_sold h on h.project_number = p.project_number
cross join as_of a