with source as (

    select * from {{ source('dld', 'buildings') }}

),

renamed as (

    select
        {{ to_int('property_id') }}                      as property_id,
        {{ to_int('parent_property_id') }}               as parent_property_id,
        {{ to_int('parcel_id') }}                        as parcel_id,
        building_number,
        land_number,
        land_sub_number,
        pre_registration_number,
        {{ to_int('land_type_id') }}                     as land_type_id,
        land_type_en,
        land_type_ar,
        {{ to_int('property_type_id') }}                 as property_type_id,
        property_type_en,
        property_type_ar,
        {{ to_int('property_sub_type_id') }}             as property_sub_type_id,
        property_sub_type_en,
        property_sub_type_ar,
        {{ to_int('rooms') }}                            as rooms,
        rooms_en,
        rooms_ar,
        {{ to_int('floors') }}                           as floors,
        {{ to_int('bld_levels') }}                       as bld_levels,
        {{ to_int('flats') }}                            as flats,
        {{ to_int('offices') }}                          as offices,
        {{ to_int('shops') }}                            as shops,
        {{ to_int('car_parks') }}                        as car_parks,
        {{ to_int('elevators') }}                        as elevators,
        {{ to_int('swimming_pools') }}                   as swimming_pools,
        {{ to_decimal('actual_area', 2) }}               as actual_area_sqm,
        {{ to_decimal('built_up_area', 2) }}             as built_up_area_sqm,
        {{ to_decimal('common_area', 2) }}               as common_area_sqm,
        {{ to_decimal('actual_common_area', 2) }}        as actual_common_area_sqm,
        {{ to_flag('is_free_hold') }}                    as is_free_hold,
        {{ to_flag('is_lease_hold') }}                   as is_lease_hold,
        {{ to_flag('is_registered') }}                   as is_registered,
        {{ to_date_safe('creation_date') }}              as creation_date,
        {{ to_int('area_id') }}                          as area_id,
        area_name_en,
        area_name_ar,
        {{ to_int('zone_id') }}                          as zone_id,
        {{ to_int('project_id') }}                       as project_id,
        project_name_en,
        project_name_ar,
        {{ to_int('master_project_id') }}                as master_project_id,
        master_project_en,
        master_project_ar,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed