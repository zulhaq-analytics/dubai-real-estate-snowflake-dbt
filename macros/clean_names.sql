{#
  Display-name cleaning for DLD names.
  initcap_words:      title-cases text; capitalizes the letter after any of the given delimiters.
                      Snowflake has INITCAP built in; DuckDB gets an equivalent expression.
  proper_case:        title-cases names that are ALL CAPS or all lowercase; leaves mixed case untouched.
  strip_legal_suffix: removes one trailing company-form suffix (brackets and spaced letters allowed).
  brand_case:         restores known brand acronyms after title-casing. Extend the list as needed.
#}

{% macro initcap_words(expr, delimiters=none) -%}
    {{ return(adapter.dispatch('initcap_words')(expr, delimiters)) }}
{%- endmacro %}

{% macro default__initcap_words(expr, delimiters=none) -%}
    {%- if delimiters is none -%} initcap({{ expr }})
    {%- else -%} initcap({{ expr }}, {{ delimiters }})
    {%- endif -%}
{%- endmacro %}

{% macro duckdb__initcap_words(expr, delimiters=none) -%}
    {#- default delimiter set matches Snowflake INITCAP: whitespace and common punctuation -#}
    {%- set delims = delimiters if delimiters is not none else "' \t\n\r!?@\"^#$&~_,.:;+-*%/|\\[](){}<>'" -%}
    (
        select string_agg(
                   case when i = 1 or contains({{ delims }}, substr(s, i - 1, 1))
                        then upper(substr(s, i, 1))
                        else lower(substr(s, i, 1))
                   end, '' order by i)
        from (select {{ expr }} as s) t, range(1, length(s) + 1) r(i)
    )
{%- endmacro %}

{% macro proper_case(col) -%}
    case
        when {{ col }} is null then null
        when {{ col }} = upper({{ col }}) or {{ col }} = lower({{ col }}) then {{ initcap_words('trim(' ~ col ~ ')') }}
        else trim({{ col }})
    end
{%- endmacro %}

{% macro strip_legal_suffix(col) -%}
    {{ return(adapter.dispatch('strip_legal_suffix')(col)) }}
{%- endmacro %}

{% macro default__strip_legal_suffix(col) -%}
    trim(regexp_replace(
        {{ col }},
        '[ ,.-]+\\(?\\s*(P\\.?\\s*J\\.?\\s*S\\.?\\s*C|L\\.?\\s*L\\.?\\s*C|F\\.?\\s*Z\\.?\\s*E|F\\.?\\s*Z\\.?\\s*C\\.?\\s*O|F\\.?\\s*Z\\.?\\s*-?\\s*L\\.?\\s*L\\.?\\s*C|ONE PERSON COMPANY|COMPANY|CO|LTD|LIMITED|S\\.?\\s*P\\.?\\s*C)\\.?\\s*\\)?[ .]*$',
        '', 1, 0, 'i'
    ))
{%- endmacro %}

{% macro duckdb__strip_legal_suffix(col) -%}
    {#- DuckDB strings don't use backslash escapes, so the pattern has single backslashes -#}
    trim(regexp_replace(
        {{ col }},
        '[ ,.-]+\(?\s*(P\.?\s*J\.?\s*S\.?\s*C|L\.?\s*L\.?\s*C|F\.?\s*Z\.?\s*E|F\.?\s*Z\.?\s*C\.?\s*O|F\.?\s*Z\.?\s*-?\s*L\.?\s*L\.?\s*C|ONE PERSON COMPANY|COMPANY|CO|LTD|LIMITED|S\.?\s*P\.?\s*C)\.?\s*\)?[ .]*$',
        '', 'i'
    ))
{%- endmacro %}

{% macro brand_case(expr) -%}
    replace(replace(replace(replace(replace(
        {{ expr }},
        'Damac', 'DAMAC'),
        'T F G', 'TFG'),
        'Hre ', 'HRE '),
        'Mry', 'MRY'),
        'Dmcc', 'DMCC')
{%- endmacro %}
