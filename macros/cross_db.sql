{#
  Small date helpers where Snowflake and DuckDB spell things differently.
#}

{% macro year_month_text(col) -%}
    {{ return(adapter.dispatch('year_month_text')(col)) }}
{%- endmacro %}
{% macro default__year_month_text(col) -%} to_char({{ col }}, 'YYYY-MM') {%- endmacro %}
{% macro duckdb__year_month_text(col) -%} strftime({{ col }}, '%Y-%m') {%- endmacro %}

{% macro month_name_short(col) -%}
    {{ return(adapter.dispatch('month_name_short')(col)) }}
{%- endmacro %}
{% macro default__month_name_short(col) -%} monthname({{ col }}) {%- endmacro %}
{% macro duckdb__month_name_short(col) -%} strftime({{ col }}, '%b') {%- endmacro %}

{% macro iso_day_of_week(col) -%}
    {{ return(adapter.dispatch('iso_day_of_week')(col)) }}
{%- endmacro %}
{% macro default__iso_day_of_week(col) -%} dayofweekiso({{ col }}) {%- endmacro %}
{% macro duckdb__iso_day_of_week(col) -%} isodow({{ col }}) {%- endmacro %}
