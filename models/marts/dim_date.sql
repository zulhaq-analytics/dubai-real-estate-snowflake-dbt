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
    monthname(date_day)                         as month_name_short,
    to_char(date_day, 'YYYY-MM')                as year_month,
    date_trunc('month', date_day)::date         as month_start,
    dayofweekiso(date_day)                      as day_of_week,
    (date_day <= current_date)                  as is_past
from spine