with source as (

    select * from {{ source('dld', 'oa_service_charges') }}

),

renamed as (

    select
        {{ to_int('project_id') }}                       as project_id,
        project_name,
        {{ to_int('budget_year') }}                      as budget_year,
        {{ to_int('master_community_id') }}              as master_community_id,
        master_community_name_en,
        master_community_name_ar,
        {{ to_int('management_company_id') }}            as management_company_id,
        management_company_name_en,
        management_company_name_ar,
        {{ to_int('property_group_id') }}                as property_group_id,
        property_group_name_en,
        property_group_name_ar,
        {{ to_int('service_category_id') }}              as service_category_id,
        service_category_name_en,
        service_category_name_ar,
        {{ to_int('usage_id') }}                         as usage_id,
        usage_name_en,
        usage_name_ar,
        {{ to_decimal('service_cost', 2) }}              as service_cost,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed