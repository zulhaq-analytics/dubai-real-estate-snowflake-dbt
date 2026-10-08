{#
  Conversion helpers for DLD raw data.
  All raw columns are text; these turn them into proper types.
  Bad values become NULL instead of failing the run.
  Each helper has a Snowflake version (default__) and a DuckDB version (duckdb__);
  dbt picks the right one for the target.
#}

{% macro to_date_safe(col) -%}
    {{ return(adapter.dispatch('to_date_safe')(col)) }}
{%- endmacro %}

{% macro default__to_date_safe(col) -%}
    CASE
        WHEN TRY_TO_TIMESTAMP_NTZ({{ col }})::DATE BETWEEN '1960-01-01' AND '2035-12-31'
            THEN TRY_TO_TIMESTAMP_NTZ({{ col }})::DATE
    END
{%- endmacro %}

{% macro duckdb__to_date_safe(col) -%}
    case
        when try_cast({{ col }} as timestamp)::date between date '1960-01-01' and date '2035-12-31'
            then try_cast({{ col }} as timestamp)::date
    end
{%- endmacro %}


{% macro to_timestamp_safe(col) -%}
    {{ return(adapter.dispatch('to_timestamp_safe')(col)) }}
{%- endmacro %}

{% macro default__to_timestamp_safe(col) -%}
    TRY_TO_TIMESTAMP_NTZ({{ col }})
{%- endmacro %}

{% macro duckdb__to_timestamp_safe(col) -%}
    try_cast({{ col }} as timestamp)
{%- endmacro %}


{% macro to_decimal(col, scale=2) -%}
    {{ return(adapter.dispatch('to_decimal')(col, scale)) }}
{%- endmacro %}

{% macro default__to_decimal(col, scale=2) -%}
    TRY_TO_DECIMAL({{ col }}, 18, {{ scale }})
{%- endmacro %}

{% macro duckdb__to_decimal(col, scale=2) -%}
    try_cast({{ col }} as decimal(18, {{ scale }}))
{%- endmacro %}


{% macro to_int(col) -%}
    {{ return(adapter.dispatch('to_int')(col)) }}
{%- endmacro %}

{% macro default__to_int(col) -%}
    TRY_TO_NUMBER({{ col }})
{%- endmacro %}

{% macro duckdb__to_int(col) -%}
    try_cast({{ col }} as bigint)
{%- endmacro %}


{% macro to_flag(col) -%}
    {{ return(adapter.dispatch('to_flag')(col)) }}
{%- endmacro %}

{% macro default__to_flag(col) -%}
    TRY_TO_BOOLEAN({{ col }})
{%- endmacro %}

{% macro duckdb__to_flag(col) -%}
    try_cast({{ col }} as boolean)
{%- endmacro %}
