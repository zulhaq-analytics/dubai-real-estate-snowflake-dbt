{#
  Conversion helpers for DLD raw data.
  All raw columns are text; these turn them into proper types.
  TRY_ functions return NULL for bad values instead of failing the run.
#}

{% macro to_date_safe(col) -%}
    CASE
        WHEN TRY_TO_TIMESTAMP_NTZ({{ col }})::DATE BETWEEN '1960-01-01' AND '2035-12-31'
            THEN TRY_TO_TIMESTAMP_NTZ({{ col }})::DATE
    END
{%- endmacro %}

{% macro to_timestamp_safe(col) -%}
    TRY_TO_TIMESTAMP_NTZ({{ col }})
{%- endmacro %}

{% macro to_decimal(col, scale=2) -%}
    TRY_TO_DECIMAL({{ col }}, 18, {{ scale }})
{%- endmacro %}

{% macro to_int(col) -%}
    TRY_TO_NUMBER({{ col }})
{%- endmacro %}

{% macro to_flag(col) -%}
    TRY_TO_BOOLEAN({{ col }})
{%- endmacro %}