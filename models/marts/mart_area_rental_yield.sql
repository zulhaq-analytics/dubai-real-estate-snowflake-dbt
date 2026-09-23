with sales as (

    select
        area_id,
        transaction_year                                             as year,
        count(*)                                                     as sales_count,
        median(price_per_sqm_aed)                                    as median_price_per_sqm_aed,
        count_if(not is_off_plan)                                    as ready_sales_count,
        median(case when not is_off_plan then price_per_sqm_aed end) as median_ready_price_per_sqm_aed
    from {{ ref('fct_transactions') }}
    where is_sale
      and is_price_valid
      and property_usage_en = 'Residential'
    group by 1, 2

),

rents as (

    select
        area_id,
        start_year                                                   as year,
        count(*)                                                     as rent_count,
        median(rent_per_sqm_aed)                                     as median_rent_per_sqm_aed
    from {{ ref('fct_rent_contracts') }}
    where is_new_contract
      and is_rent_valid
      and is_residential
      and is_single_property
    group by 1, 2

),

service_charges as (

    select
        area_id,
        count(*)                                                     as service_charge_projects,
        median(rate_aed_per_sqm)                                     as median_service_charge_per_sqm_aed
    from {{ ref('fct_service_charges') }}
    where is_latest_valid_year
      and area_id is not null
    group by 1

),

combined as (

    select
        coalesce(s.area_id, r.area_id)                               as area_id,
        coalesce(s.year, r.year)                                     as year,
        s.sales_count,
        s.median_price_per_sqm_aed,
        s.ready_sales_count,
        s.median_ready_price_per_sqm_aed,
        r.rent_count,
        r.median_rent_per_sqm_aed
    from sales s
    full outer join rents r
        on  s.area_id = r.area_id
        and s.year    = r.year

)

select
    c.area_id,
    a.area_display_name,
    a.area_name_en,
    c.year,
    c.sales_count,
    c.median_price_per_sqm_aed,
    c.ready_sales_count,
    c.median_ready_price_per_sqm_aed,
    c.rent_count,
    c.median_rent_per_sqm_aed,
    sc.service_charge_projects,
    sc.median_service_charge_per_sqm_aed,
    case
        when c.sales_count >= 30 and c.rent_count >= 30
            then c.median_rent_per_sqm_aed / nullif(c.median_price_per_sqm_aed, 0)
    end                                                              as gross_rental_yield,
    case
        when c.ready_sales_count >= 30 and c.rent_count >= 30
            then c.median_rent_per_sqm_aed / nullif(c.median_ready_price_per_sqm_aed, 0)
    end                                                              as gross_rental_yield_ready,
    case
        when c.ready_sales_count >= 30 and c.rent_count >= 30 and sc.service_charge_projects >= 5
            then (c.median_rent_per_sqm_aed - sc.median_service_charge_per_sqm_aed)
                 / nullif(c.median_ready_price_per_sqm_aed, 0)
    end                                                              as net_rental_yield_ready
from combined c
left join {{ ref('dim_area') }} a
    on c.area_id = a.area_id
left join service_charges sc
    on c.area_id = sc.area_id