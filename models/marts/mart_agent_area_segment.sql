{{ config(materialized='table', enabled=(target.type == 'duckdb')) }}

-- Summary for the Dubai Property Advisor agent.
-- One row per area x property type (Apartment / Villa) x bedroom category.
-- Compares the 12 months to the latest sale date with the 12 months before.
-- Residential only. Sales use valid prices; rents use new, single-unit, valid contracts.
-- Yields need 30+ ready sales and 30+ leases; price and rent changes need 50+ in both periods.
-- Price change uses ready homes only, so shifts in the off-plan share do not distort it.

with as_of as (
    select max(transaction_date) as as_of_date
    from {{ ref('fct_transactions') }}
    where is_sale
),

bounds as (
    select
        as_of_date,
        cast(as_of_date - interval 12 month as date) as last_start,
        cast(as_of_date - interval 24 month as date) as prior_start
    from as_of
),

sales as (
    select
        t.area_id,
        case t.property_type_en when 'Unit' then 'Apartment' else 'Villa' end      as property_type,
        t.room_category,
        case when t.transaction_date > b.last_start then 'last' else 'prior' end    as period,
        t.is_off_plan,
        t.actual_worth_aed,
        t.procedure_area_sqm,
        t.price_per_sqm_aed
    from {{ ref('fct_transactions') }} t
    cross join bounds b
    where t.is_sale
      and t.is_price_valid
      and t.property_usage_en = 'Residential'
      and t.property_type_en in ('Unit', 'Villa')
      and t.room_category in ('Studio', '1 BR', '2 BR', '3 BR', '4 BR', '5+ BR')
      and t.transaction_date >  b.prior_start
      and t.transaction_date <= b.as_of_date
),

rents as (
    select
        r.area_id,
        case when trim(r.ejari_property_type_en) in ('Flat', 'Studio') then 'Apartment'
             else 'Villa' end                                                       as property_type,
        r.room_category,
        case when r.contract_start_date > b.last_start then 'last' else 'prior' end as period,
        r.annual_rent_aed,
        r.rent_per_sqm_aed
    from {{ ref('fct_rent_contracts') }} r
    cross join bounds b
    where r.is_new_contract
      and r.is_residential
      and r.is_single_property
      and r.is_rent_valid
      and trim(r.ejari_property_type_en) in ('Flat', 'Studio', 'Villa', 'Complex Villas')
      and r.room_category in ('Studio', '1 BR', '2 BR', '3 BR', '4 BR', '5+ BR')
      and r.contract_start_date >  b.prior_start
      and r.contract_start_date <= b.as_of_date
),

sales_agg as (
    select
        area_id, property_type, room_category,
        count_if(period = 'last')                                                         as sales_12m,
        count_if(period = 'last' and not is_off_plan)                                     as ready_sales_12m,
        count_if(period = 'last' and is_off_plan)                                         as offplan_sales_12m,
        median(actual_worth_aed)   filter (where period = 'last')                         as median_price_aed,
        median(actual_worth_aed)   filter (where period = 'last' and not is_off_plan)     as median_ready_price_aed,
        median(actual_worth_aed)   filter (where period = 'last' and is_off_plan)         as median_offplan_price_aed,
        median(procedure_area_sqm) filter (where period = 'last')                         as median_size_sqm,
        median(price_per_sqm_aed)  filter (where period = 'last')                         as median_price_per_sqm_aed,
        median(price_per_sqm_aed)  filter (where period = 'last' and not is_off_plan)     as median_ready_price_per_sqm_aed,
        count_if(period = 'prior' and not is_off_plan)                                    as ready_sales_prior_12m,
        median(price_per_sqm_aed)  filter (where period = 'prior' and not is_off_plan)    as median_ready_price_per_sqm_prior_aed
    from sales
    group by 1, 2, 3
),

rents_agg as (
    select
        area_id, property_type, room_category,
        count_if(period = 'last')                                       as rents_12m,
        median(annual_rent_aed)  filter (where period = 'last')         as median_annual_rent_aed,
        median(rent_per_sqm_aed) filter (where period = 'last')         as median_rent_per_sqm_aed,
        count_if(period = 'prior')                                      as rents_prior_12m,
        median(rent_per_sqm_aed) filter (where period = 'prior')        as median_rent_per_sqm_prior_aed
    from rents
    group by 1, 2, 3
),

service_charges as (
    select
        area_id,
        count(*)                                  as service_charge_projects,
        cast(median(rate_aed_per_sqm) as double)  as median_service_charge_per_sqm_aed
    from {{ ref('fct_service_charges') }}
    where is_latest_valid_year
      and area_id is not null
    group by 1
),

segments as (
    select area_id, property_type, room_category from sales_agg
    union
    select area_id, property_type, room_category from rents_agg
)

select
    b.as_of_date,
    k.area_id,
    a.area_display_name,
    k.property_type,
    k.room_category,
    case k.room_category when 'Studio' then 0 when '1 BR' then 1 when '2 BR' then 2
                         when '3 BR' then 3 when '4 BR' then 4 else 5 end                  as room_order,
    coalesce(s.sales_12m, 0)                                                            as sales_12m,
    coalesce(s.ready_sales_12m, 0)                                                      as ready_sales_12m,
    coalesce(s.offplan_sales_12m, 0)                                                    as offplan_sales_12m,
    round(s.median_price_aed, 0)                                                        as median_price_aed,
    round(s.median_ready_price_aed, 0)                                                  as median_ready_price_aed,
    round(s.median_offplan_price_aed, 0)                                                as median_offplan_price_aed,
    round(s.median_size_sqm, 1)                                                         as median_size_sqm,
    round(s.median_price_per_sqm_aed, 0)                                                as median_price_per_sqm_aed,
    coalesce(r.rents_12m, 0)                                                            as rents_12m,
    round(r.median_annual_rent_aed, 0)                                                  as median_annual_rent_aed,
    round(r.median_rent_per_sqm_aed, 0)                                                 as median_rent_per_sqm_aed,
    case when s.ready_sales_12m >= 50 and s.ready_sales_prior_12m >= 50
         then round((s.median_ready_price_per_sqm_aed / s.median_ready_price_per_sqm_prior_aed - 1) * 100, 1)
    end                                                                                 as ready_price_per_sqm_change_pct,
    case when r.rents_12m >= 50 and r.rents_prior_12m >= 50
         then round((r.median_rent_per_sqm_aed / r.median_rent_per_sqm_prior_aed - 1) * 100, 1)
    end                                                                                 as rent_per_sqm_change_pct,
    case when s.ready_sales_12m >= 30 and r.rents_12m >= 30
         then round(r.median_rent_per_sqm_aed / s.median_ready_price_per_sqm_aed * 100, 2)
    end                                                                                 as gross_yield_ready_pct,
    case when k.property_type = 'Apartment'
          and s.ready_sales_12m >= 30 and r.rents_12m >= 30 and sc.service_charge_projects >= 5
         then round((r.median_rent_per_sqm_aed - sc.median_service_charge_per_sqm_aed)
                    / s.median_ready_price_per_sqm_aed * 100, 2)
    end                                                                                 as net_yield_ready_pct
from segments k
cross join bounds b
left join sales_agg s        using (area_id, property_type, room_category)
left join rents_agg r        using (area_id, property_type, room_category)
left join service_charges sc on k.area_id = sc.area_id
left join {{ ref('dim_area') }} a on k.area_id = a.area_id
where coalesce(s.sales_12m, 0) + coalesce(r.rents_12m, 0) > 0
