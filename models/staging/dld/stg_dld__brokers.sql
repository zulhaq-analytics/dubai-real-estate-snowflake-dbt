with source as (

    select * from {{ source('dld', 'brokers') }}

),

renamed as (

    select
        {{ to_int('real_estate_broker_id') }}            as broker_id,
        broker_number,
        broker_name_en,
        broker_name_ar,
        gender,
        {{ to_int('real_estate_id') }}                   as office_id,
        real_estate_number                               as office_number,
        {{ to_int('participant_id') }}                   as participant_id,
        {{ to_date_safe('license_start_date') }}         as license_start_date,
        {{ to_date_safe('license_end_date') }}           as license_end_date,
        phone,
        fax,
        webpage,
        {{ to_timestamp_safe('load_timestamp') }}        as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed