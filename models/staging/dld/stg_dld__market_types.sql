with source as (

    select * from {{ source('dld', 'lkp_market_types') }}

),

renamed as (

    select
        {{ to_int('market_type_id') }}             as market_type_id,
        name_en                                    as market_type_name_en,
        name_ar                                    as market_type_name_ar,
        {{ to_timestamp_safe('load_timestamp') }}  as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed