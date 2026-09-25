{#
  Display-name cleaning for DLD names.
  proper_case:        title-cases names that are ALL CAPS or all lowercase; leaves mixed case untouched.
  strip_legal_suffix: removes one trailing company-form suffix (brackets and spaced letters allowed).
  brand_case:         restores known brand acronyms after title-casing. Extend the list as needed.
#}

{% macro proper_case(col) -%}
    case
        when {{ col }} is null then null
        when {{ col }} = upper({{ col }}) or {{ col }} = lower({{ col }}) then initcap(trim({{ col }}))
        else trim({{ col }})
    end
{%- endmacro %}

{% macro strip_legal_suffix(col) -%}
    trim(regexp_replace(
        {{ col }},
        '[ ,.-]+\\(?\\s*(P\\.?\\s*J\\.?\\s*S\\.?\\s*C|L\\.?\\s*L\\.?\\s*C|F\\.?\\s*Z\\.?\\s*E|F\\.?\\s*Z\\.?\\s*C\\.?\\s*O|F\\.?\\s*Z\\.?\\s*-?\\s*L\\.?\\s*L\\.?\\s*C|ONE PERSON COMPANY|COMPANY|CO|LTD|LIMITED|S\\.?\\s*P\\.?\\s*C)\\.?\\s*\\)?[ .]*$',
        '', 1, 0, 'i'
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