with source as (

    select * from {{ source('dld', 'lkp_areas') }}

),

renamed as (

    select
        {{ to_int('area_id') }}                    as area_id,
        municipality_number,
        name_en                                    as area_name_en,
        name_ar                                    as area_name_ar,
        {{ to_timestamp_safe('load_timestamp') }}  as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed