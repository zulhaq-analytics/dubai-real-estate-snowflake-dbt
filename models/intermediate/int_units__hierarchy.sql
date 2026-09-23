with units as (

    select * from {{ ref('stg_dld__units') }}

),

buildings as (

    select * from {{ ref('stg_dld__buildings') }}

),

land as (

    select * from {{ ref('stg_dld__land_registry') }}

),

projects as (

    select * from {{ ref('stg_dld__projects') }}

),

developers as (

    select developer_id, developer_name_en
    from {{ ref('stg_dld__developers') }}

),

joined as (

    select
        -- unit
        u.property_id                                               as unit_property_id,
        u.unit_number,
        u.floor,
        u.property_type_en,
        u.property_sub_type_en,
        u.rooms_en,
        {{ rooms_to_bedrooms('u.rooms_en') }}                       as bedrooms,
        {{ rooms_to_category('u.rooms_en') }}                       as room_category,
        u.actual_area_sqm,
        u.balcony_area_sqm,
        u.is_free_hold,
        u.is_registered,
        u.creation_date                                             as unit_creation_date,

        -- building (parent)
        b.property_id                                               as building_property_id,
        b.building_number,
        b.floors                                                    as building_floors,
        b.flats                                                     as building_flats,
        b.car_parks                                                 as building_car_parks,
        b.elevators                                                 as building_elevators,
        b.swimming_pools                                            as building_swimming_pools,

        -- land: grandparent, or parent when the unit sits directly on land (villas)
        coalesce(lg.property_id, lp.property_id)                    as land_property_id,
        coalesce(lg.parcel_id, lp.parcel_id, u.parcel_id)           as parcel_id,
        coalesce(lg.land_type_en, lp.land_type_en)                  as land_type_en,
        coalesce(lg.actual_area_sqm, lp.actual_area_sqm)            as land_area_sqm,

        -- project: the unit's own, else the building's
        coalesce(u.project_id, b.project_id)                        as project_id,
        p.project_number,
        p.project_name,
        p.project_status,
        p.percent_completed                                         as project_percent_completed,
        p.completion_date                                           as project_completion_date,

        -- developer (through the project)
        p.developer_id,
        d.developer_name_en,
        p.master_developer_id,
        p.master_developer_name,

        -- location
        u.area_id,
        u.area_name_en,
        u.master_project_en,

        -- hierarchy coverage flags
        (b.property_id is not null)                                 as has_building,
        (coalesce(lg.property_id, lp.property_id) is not null)      as has_land,
        (p.project_id is not null)                                  as has_project,
        (d.developer_id is not null)                                as has_developer

    from units u
    left join buildings b   on u.parent_property_id      = b.property_id
    left join land lg       on u.grandparent_property_id = lg.property_id
    left join land lp       on u.parent_property_id      = lp.property_id
    left join projects p    on coalesce(u.project_id, b.project_id) = p.project_id
    left join developers d  on p.developer_id            = d.developer_id

)

select * from joined