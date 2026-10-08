-- Reconcile v2 (DuckDB) against v1 (Snowflake): the same checks on both engines.
-- Replace MARTS_SCHEMA with  main_marts            on DuckDB
--                       or   ANALYTICS.PROD_MARTS  on Snowflake
-- Checks use data up to 2025 so the newer API records in v2 don't affect them.

select 1 as n, 'Sales 2025 (count)' as check_name,
       cast(count(*) as double) as value
from MARTS_SCHEMA.fct_transactions where is_sale and transaction_year = 2025
union all
select 2, 'Sales 2025 (AED bn)', cast(sum(actual_worth_aed) / 1e9 as double)
from MARTS_SCHEMA.fct_transactions where is_sale and transaction_year = 2025
union all
select 3, 'Off-plan share of sales 2025', avg(case when is_off_plan then 1.0 else 0.0 end)
from MARTS_SCHEMA.fct_transactions where is_sale and transaction_year = 2025
union all
select 4, 'Median price per sq m 2025 (residential)', cast(median(price_per_sqm_aed) as double)
from MARTS_SCHEMA.fct_transactions
where is_sale and is_price_valid and property_usage_en = 'Residential' and transaction_year = 2025
union all
select 5, 'All transactions to 2025 (count)', cast(count(*) as double)
from MARTS_SCHEMA.fct_transactions where transaction_date <= '2025-12-31'
union all
select 6, 'New rent contracts 2025 (count)', cast(count(*) as double)
from MARTS_SCHEMA.fct_rent_contracts where is_new_contract and start_year = 2025
union all
select 7, 'Median new rent per sq m 2025', cast(median(rent_per_sqm_aed) as double)
from MARTS_SCHEMA.fct_rent_contracts
where is_new_contract and is_rent_valid and is_residential and is_single_property and start_year = 2025
union all
select 8, 'All rent contracts to 2025 (count)', cast(count(*) as double)
from MARTS_SCHEMA.fct_rent_contracts where contract_start_date <= '2025-12-31'
union all
select 9, 'Valuations to 2025 (count)', cast(count(*) as double)
from MARTS_SCHEMA.fct_valuations where valuation_date <= '2025-12-31'
union all
select 10, 'Gross yield, ready homes 2025 (avg of areas)', avg(gross_rental_yield_ready)
from MARTS_SCHEMA.mart_area_rental_yield where year = 2025
union all
select 11, 'Areas with a net yield 2025', cast(count(net_rental_yield_ready) as double)
from MARTS_SCHEMA.mart_area_rental_yield where year = 2025
union all
select 12, 'First-year absorption, 2022 launches', avg(first_year_absorption)
from MARTS_SCHEMA.mart_project_absorption where is_absorption_eligible and launch_year = 2022
union all
select 13, 'Projects (count)', cast(count(*) as double) from MARTS_SCHEMA.dim_project
union all
select 14, 'Units (count)', cast(count(*) as double) from MARTS_SCHEMA.dim_unit
union all
select 15, 'Areas (count)', cast(count(*) as double) from MARTS_SCHEMA.dim_area
union all
select 16, 'Developers (count)', cast(count(*) as double) from MARTS_SCHEMA.dim_developer
union all
select 17, 'Service charge rows (count)', cast(count(*) as double) from MARTS_SCHEMA.fct_service_charges
order by 1
