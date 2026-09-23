with source as (

    select * from {{ source('dld', 'valuation') }}

),

renamed as (

    select
        procedure_number,
        {{ to_int('procedure_year') }}                   as procedure_year,
        {{ to_int('procedure_id') }}                     as procedure_id,
        procedure_name_en,
        procedure_name_ar,
        {{ to_date_safe('instance_date') }}              as valuation_date,
        {{ to_int('property_type_id') }}                 as property_type_id,
        property_type_en,
        property_type_ar,
        {{ to_int('property_sub_type_id') }}             as property_sub_type_id,
        property_sub_type_en,
        property_sub_type_ar,
        {{ to_decimal('procedure_area', 2) }}            as procedure_area_sqm,
        {{ to_decimal('actual_area', 2) }}               as actual_area_sqm,
        {{ to_decimal('actual_worth', 2) }}              as actual_worth_aed,
        {{ to_decimal('property_total_value', 2) }}      as property_total_value_aed,
        {{ to_int('area_id') }}                          as area_id,
        area_name_en,
        area_name_ar,
        row_status_code,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed