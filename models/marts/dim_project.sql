with projects as (

    select * from {{ ref('stg_dld__projects') }}

),

developers as (

    select developer_id, developer_name_en
    from {{ ref('stg_dld__developers') }}

),

-- English project names: the most common name used in transactions for each project number
english_names as (

    select
        project_number,
        project_name_en
    from {{ ref('stg_dld__transactions') }}
    where project_number is not null
      and nullif(trim(project_name_en), '') is not null
    group by 1, 2
    qualify row_number() over (partition by project_number order by count(*) desc) = 1

)

select
    p.project_id,
    p.project_number,
        {{ proper_case('coalesce(en.project_name_en, p.project_name)') }}                    as project_name_en,
    coalesce(en.project_name_en, p.project_name)                                         as project_name_raw,
    p.project_name                                      as project_name_ar,
    p.project_status,
    p.project_status_label,
    p.percent_completed,
    p.project_start_date,
    p.project_end_date,
    p.completion_date,
    p.cancellation_date,
    p.developer_id,
    {{ brand_case(proper_case(strip_legal_suffix(strip_legal_suffix('coalesce(d.developer_name_en, p.developer_name)')))) }} as developer_name,
    coalesce(d.developer_name_en, p.developer_name)                                      as developer_name_legal,
    p.master_developer_id,
    p.master_developer_name,
    p.escrow_agent_name,
    p.area_id,
    p.area_name_en,
    p.master_project_en,
    p.no_of_lands,
    p.no_of_buildings,
    p.no_of_villas,
    p.no_of_units
from projects p
left join developers d
    on p.developer_id = d.developer_id
left join english_names en
    on p.project_number = en.project_number