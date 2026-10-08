{# v1 forecast (Snowflake ML). Runs only on the Snowflake target; the DuckDB target uses mart_forecasts.py. #}
{{ config(
    enabled         = target.type == 'snowflake',
    alias           = 'mart_forecasts',
    materialized    = 'table',
    static_analysis = 'off',
    pre_hook        = "create or replace snowflake.ml.forecast {{ this.database }}.{{ this.schema }}.fcst_dubai_monthly (
                           input_data        => table({{ ref('mart_monthly_series') }}),
                           series_colname    => 'SERIES',
                           timestamp_colname => 'MONTH_START',
                           target_colname    => 'VALUE'
                       )"
) }}

-- depends_on: {{ ref('mart_monthly_series') }}

with forecast as (

    select
        series::string       as series,
        ts::date             as month_start,
        forecast::float      as forecast_value,
        lower_bound::float   as lower_bound,
        upper_bound::float   as upper_bound
    from table(
        {{ this.database }}.{{ this.schema }}.fcst_dubai_monthly!forecast(
            forecasting_periods => 12,
            config_object       => {'prediction_interval': 0.95}
        )
    )

),

actuals as (

    select
        series,
        month_start::date as month_start,
        value
    from {{ ref('mart_monthly_series') }}

)

select
    series,
    month_start,
    value              as actual_value,
    null::float        as forecast_value,
    null::float        as lower_bound,
    null::float        as upper_bound,
    false              as is_forecast
from actuals

union all

select
    series,
    month_start,
    null::float        as actual_value,
    forecast_value,
    lower_bound,
    upper_bound,
    true               as is_forecast
from forecast