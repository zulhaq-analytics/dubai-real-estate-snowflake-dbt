with areas as (

    select * from {{ ref('stg_dld__areas') }}

),

community_counts as (

    select
        area_id,
        master_project_en,
        count(*)                                           as n,
        sum(count(*)) over (partition by area_id)          as area_total
    from {{ ref('int_transactions__enriched') }}
        where nullif(trim(master_project_en), '') is not null
    group by 1, 2

),

dominant_community as (

    select
        area_id,
        master_project_en                                  as community_name,
        n / area_total                                     as community_share
    from community_counts
    qualify row_number() over (partition by area_id order by n desc) = 1

)

select
    a.area_id,
    a.area_name_en,
    a.area_name_ar,
    a.municipality_number,
    case when d.community_share >= 0.5 then d.community_name end          as community_name,
    round(d.community_share, 3)                                           as community_share,
    coalesce(
        case when d.community_share >= 0.5 then d.community_name end,
        a.area_name_en
    )                                                                     as area_display_name
from areas a
left join dominant_community d
    on a.area_id = d.area_id