with source as (

    select * from {{ source('dld', 'lkp_transaction_groups') }}

),

renamed as (

    select
        {{ to_int('group_id') }}                   as trans_group_id,
        name_en                                    as trans_group_name_en,
        name_ar                                    as trans_group_name_ar,
        {{ to_timestamp_safe('load_timestamp') }}  as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed