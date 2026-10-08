with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('1960-01-01' as date)",
        end_date="cast('2036-01-01' as date)"
    ) }}

)

select
    date_day::date                              as date_day,
    year(date_day)                              as year,
    quarter(date_day)                           as quarter,
    month(date_day)                             as month,
    {{ month_name_short('date_day') }}       as month_name_short,
    {{ year_month_text('date_day') }}        as year_month,
    date_trunc('month', date_day)::date         as month_start,
    {{ iso_day_of_week('date_day') }}        as day_of_week,
    (date_day <= current_date)                  as is_past
from spine