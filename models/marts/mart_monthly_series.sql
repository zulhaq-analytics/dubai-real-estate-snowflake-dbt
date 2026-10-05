{{ config(materialized='table') }}

-- Monthly series used to train the forecaster: Jan 2015 to the last complete month.
-- Price and rent are per sq m (Power BI converts to sq ft).

with cutoff as (

    select date_trunc('month', max(transaction_date)) as cutoff_month
    from {{ ref('int_transactions__enriched') }}

),

sales as (

    select
        'Sales per month'                         as series,
        date_trunc('month', t.transaction_date)   as month_start,
        count(*)::float                           as value
    from {{ ref('int_transactions__enriched') }} t
    cross join cutoff c
    where t.is_sale
      and t.transaction_date >= '2015-01-01'
      and t.transaction_date <  c.cutoff_month
    group by 1, 2

),

price as (

    select
        'Price per sq m'                          as series,
        date_trunc('month', t.transaction_date)   as month_start,
        median(t.price_per_sqm_aed)::float        as value
    from {{ ref('int_transactions__enriched') }} t
    cross join cutoff c
    where t.is_sale
      and t.is_price_valid
      and t.property_usage_en = 'Residential'
      and t.transaction_date >= '2015-01-01'
      and t.transaction_date <  c.cutoff_month
    group by 1, 2

),

rent as (

    select
        'Rent per sq m'                             as series,
        date_trunc('month', r.contract_start_date)  as month_start,
        median(r.rent_per_sqm_aed)::float           as value
    from {{ ref('int_rent_contracts__enriched') }} r
    cross join cutoff c
    where r.is_new_contract
      and r.is_rent_valid
      and r.is_residential
      and r.contract_start_date >= '2015-01-01'
      and r.contract_start_date <  c.cutoff_month
    group by 1, 2

)

select series, month_start::timestamp_ntz as month_start, value from sales
union all
select series, month_start::timestamp_ntz, value from price
union all
select series, month_start::timestamp_ntz, value from rent