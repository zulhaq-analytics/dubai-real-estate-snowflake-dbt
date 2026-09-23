with source as (

    select * from {{ source('dld', 'offices') }}

),

renamed as (

    select
        {{ to_int('real_estate_id') }}                   as office_id,
        real_estate_number                               as office_number,
        {{ to_int('main_office_id') }}                   as main_office_id,
        {{ to_flag('is_branch') }}                       as is_branch,
        {{ to_int('participant_id') }}                   as participant_id,
        license_number,
        {{ to_int('license_source_id') }}                as license_source_id,
        license_source_en,
        license_source_ar,
        {{ to_date_safe('license_issue_date') }}         as license_issue_date,
        {{ to_date_safe('license_expiry_date') }}        as license_expiry_date,
        {{ to_int('activity_type_id') }}                 as activity_type_id,
        activity_type_en,
        activity_type_ar,
        ded_activity_code,
        phone,
        fax,
        webpage,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed