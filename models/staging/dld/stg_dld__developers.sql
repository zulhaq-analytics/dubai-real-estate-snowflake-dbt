with source as (

    select * from {{ source('dld', 'developers') }}

),

renamed as (

    select
        {{ to_int('developer_id') }}                     as developer_id,
        developer_number,
        {{ to_int('participant_id') }}                   as participant_id,
        developer_name_en,
        developer_name_ar,
        legal_status,
        legal_status_en,
        legal_status_ar,
        license_number,
        {{ to_int('license_type_id') }}                  as license_type_id,
        license_type_en,
        license_type_ar,
        {{ to_int('license_source_id') }}                as license_source_id,
        license_source_en,
        license_source_ar,
        {{ to_date_safe('license_issue_date') }}         as license_issue_date,
        {{ to_date_safe('license_expiry_date') }}        as license_expiry_date,
        {{ to_date_safe('registration_date') }}          as registration_date,
        chamber_of_commerce_no,
        phone,
        fax,
        webpage,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed