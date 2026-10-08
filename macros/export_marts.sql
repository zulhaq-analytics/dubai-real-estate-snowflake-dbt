{#
  After each DuckDB run, write every successfully built mart to a Parquet file
  that Power BI imports. Does nothing on Snowflake.
#}

{% macro export_marts_to_parquet(results) %}
    {% if execute and target.type == 'duckdb' %}
        {% set path = var('parquet_export_path') %}
        {% for res in results %}
            {% set node = res.node %}
            {% if node.resource_type == 'model'
                  and 'marts' in node.fqn
                  and res.status == 'success'
                  and node.config.materialized == 'table' %}
                {% set target_file = path ~ '/' ~ node.alias ~ '.parquet' %}
                {% do run_query("copy (select * from " ~ node.relation_name ~ ") to '" ~ target_file ~ "' (format parquet, compression zstd)") %}
                {% do log("Exported " ~ node.alias ~ " to " ~ target_file, info=true) %}
            {% endif %}
        {% endfor %}
    {% endif %}
{% endmacro %}
