with source as (

    select * from {{ source('dld', 'land_registry') }}

),

renamed as (

    select
        {{ to_int('parcel_id') }}                        as parcel_id,
        {{ to_int('property_id') }}                      as property_id,
        land_number,
        land_sub_number,
        munc_number,
        munc_zip_code,
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
        {{ to_decimal('actual_area', 2) }}               as actual_area_sqm,
        {{ to_flag('is_free_hold') }}                    as is_free_hold,
        {{ to_flag('is_registered') }}                   as is_registered,
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
        separated_from,
        separated_reference,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed