with projects as (

    select * from {{ ref('stg_dld__projects') }}

),

developers as (

    select developer_id, developer_name_en
    from {{ ref('stg_dld__developers') }}

)

select
    p.project_id,
    p.project_number,
    p.project_name,
    p.project_status,
    p.percent_completed,
    p.project_start_date,
    p.project_end_date,
    p.completion_date,
    p.cancellation_date,
    p.developer_id,
    coalesce(d.developer_name_en, p.developer_name)     as developer_name,
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