with source as (

    select * from {{ source('dld', 'rent_contracts') }}

),

renamed as (

    select
        contract_id,
        {{ to_int('line_number') }}                      as line_number,
        {{ to_int('contract_reg_type_id') }}             as contract_reg_type_id,
        contract_reg_type_en,
        contract_reg_type_ar,
        {{ to_date_safe('contract_start_date') }}        as contract_start_date,
        {{ to_date_safe('contract_end_date') }}          as contract_end_date,
        {{ to_decimal('contract_amount', 2) }}           as contract_amount_aed,
        {{ to_decimal('annual_amount', 2) }}             as annual_amount_aed,
        {{ to_int('no_of_prop') }}                       as no_of_properties,
        {{ to_decimal('actual_area', 2) }}               as actual_area_sqm,
        {{ to_int('ejari_property_type_id') }}           as ejari_property_type_id,
        ejari_property_type_en,
        ejari_property_type_ar,
        {{ to_int('ejari_property_sub_type_id') }}       as ejari_property_sub_type_id,
        ejari_property_sub_type_en,
        ejari_property_sub_type_ar,
        {{ to_int('ejari_bus_property_type_id') }}       as ejari_bus_property_type_id,
        ejari_bus_property_type_en,
        ejari_bus_property_type_ar,
        property_usage_en,
        property_usage_ar,
        {{ to_int('tenant_type_id') }}                   as tenant_type_id,
        tenant_type_en,
        tenant_type_ar,
        {{ to_flag('is_free_hold') }}                    as is_free_hold,
        {{ to_int('area_id') }}                          as area_id,
        area_name_en,
        area_name_ar,
        project_number,
        project_name_en,
        project_name_ar,
        master_project_en,
        master_project_ar,
        nearest_metro_en,
        nearest_metro_ar,
        nearest_mall_en,
        nearest_mall_ar,
        nearest_landmark_en,
        nearest_landmark_ar,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed