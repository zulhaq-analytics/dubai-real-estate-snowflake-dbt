with source as (

    select * from {{ source('dld', 'transactions') }}

),

renamed as (

    select
        transaction_id,
        {{ to_date_safe('instance_date') }}              as transaction_date,
        {{ to_int('trans_group_id') }}                   as trans_group_id,
        trans_group_en,
        trans_group_ar,
        {{ to_int('procedure_id') }}                     as procedure_id,
        procedure_name_en,
        procedure_name_ar,
        {{ to_int('reg_type_id') }}                      as reg_type_id,
        reg_type_en,
        reg_type_ar,
        {{ to_int('property_type_id') }}                 as property_type_id,
        property_type_en,
        property_type_ar,
        {{ to_int('property_sub_type_id') }}             as property_sub_type_id,
        property_sub_type_en,
        property_sub_type_ar,
        property_usage_en,
        property_usage_ar,
        rooms_en,
        rooms_ar,
        {{ to_flag('has_parking') }}                     as has_parking,
        {{ to_decimal('procedure_area', 2) }}            as procedure_area_sqm,
        {{ to_decimal('actual_worth', 2) }}              as actual_worth_aed,
        {{ to_decimal('meter_sale_price', 2) }}          as meter_sale_price_aed,
        {{ to_decimal('rent_value', 2) }}                as rent_value_aed,
        {{ to_decimal('meter_rent_price', 2) }}          as meter_rent_price_aed,
        {{ to_int('no_of_parties_role_1') }}             as no_of_parties_role_1,
        {{ to_int('no_of_parties_role_2') }}             as no_of_parties_role_2,
        {{ to_int('no_of_parties_role_3') }}             as no_of_parties_role_3,
        {{ to_int('area_id') }}                          as area_id,
        area_name_en,
        area_name_ar,
        {{ to_int('project_number') }}                 as project_number,
        project_name_en,
        project_name_ar,
        master_project_en,
        master_project_ar,
        building_name_en,
        building_name_ar,
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