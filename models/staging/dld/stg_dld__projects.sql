with source as (

    select * from {{ source('dld', 'projects') }}

),

renamed as (

    select
        {{ to_int('project_id') }}                       as project_id,
        {{ to_int('project_number') }}                 as project_number,
        project_name,
        project_description_en,
        project_description_ar,
        {{ to_int('project_type_id') }}                  as project_type_id,
        project_type_ar,
        {{ to_int('project_classification_id') }}        as project_classification_id,
        project_classification_ar,
                case project_status
            when 'FRIEZED' then 'FROZEN'          -- DLD source typo
            else project_status
        end                                              as project_status,
        initcap ( replace (
            case project_status when 'FRIEZED' then 'FROZEN' else project_status end,
            '_', ' ' ) )                                 as project_status_label,
        project_status_ar,
        {{ to_decimal('percent_completed', 2) }}         as percent_completed,
        {{ to_date_safe('project_start_date') }}         as project_start_date,
        {{ to_date_safe('project_end_date') }}           as project_end_date,
        {{ to_date_safe('completion_date') }}            as completion_date,
        {{ to_date_safe('cancellation_date') }}          as cancellation_date,
        {{ to_int('developer_id') }}                     as developer_id,
        developer_number,
        developer_name,
        {{ to_int('master_developer_id') }}              as master_developer_id,
        master_developer_number,
        master_developer_name,
        {{ to_int('escrow_agent_id') }}                  as escrow_agent_id,
        escrow_agent_name,
        {{ to_int('area_id') }}                          as area_id,
        area_name_en,
        area_name_ar,
        master_project_en,
        master_project_ar,
        {{ to_int('property_id') }}                      as property_id,
        {{ to_int('zoning_authority_id') }}              as zoning_authority_id,
        zoning_authority_en,
        zoning_authority_ar,
        {{ to_int('no_of_lands') }}                      as no_of_lands,
        {{ to_int('no_of_buildings') }}                  as no_of_buildings,
        {{ to_int('no_of_villas') }}                     as no_of_villas,
        {{ to_int('no_of_units') }}                      as no_of_units,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed