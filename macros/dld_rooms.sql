{#
  Room parsing for DLD rooms_en values.
  bedrooms      : 0 for studios, the leading number for "N B/R", "N bed rooms+hall",
                  "Nbed room+Hall", "N + Terrace"; NULL otherwise.
  room_category : grouped label for reporting.
#}

{% macro rooms_to_bedrooms(col) -%}
    case
        when lower(trim({{ col }})) = 'studio' then 0
        else try_to_number(
                 regexp_substr({{ col }}, '^ *([0-9]+) *(B/R|bed ?rooms?|[+] *Terrace)', 1, 1, 'ie', 1)
             )
    end
{%- endmacro %}

{% macro rooms_to_category(col) -%}
    case
        when {{ col }} is null or upper(trim({{ col }})) in ('', 'NA')           then 'Unknown'
        when lower(trim({{ col }})) = 'studio'                                     then 'Studio'
        when {{ rooms_to_bedrooms(col) }} between 1 and 4
            then {{ rooms_to_bedrooms(col) }}::varchar || ' BR'
        when {{ rooms_to_bedrooms(col) }} >= 5                                     then '5+ BR'
        when lower(trim({{ col }})) like 'penthouse%'                              then 'Penthouse'
        when lower(trim({{ col }})) in ('single room', 'room', 'room in labor camp',
                                        'labor camp', 'staff accommodatoion',
                                        'portacabin rooms')                         then 'Room / Staff housing'
        when lower(trim({{ col }})) in ('duplex', 'hotel apartments')              then 'Other residential'
        else 'Commercial / Other'
    end
{%- endmacro %}