with source as (

    select * from {{ source('dld', 'lkp_transaction_procedures') }}

),

renamed as (

    select
        {{ to_int('procedure_id') }}               as procedure_id,
        {{ to_int('group_id') }}                   as trans_group_id,
        name_en                                    as procedure_name_en,
        name_ar                                    as procedure_name_ar,
        {{ to_flag('is_pre_registration') }}       as is_pre_registration,
        {{ to_timestamp_safe('load_timestamp') }}  as dld_load_timestamp,
        _source_file,
        _loaded_at

    from source

)

select * from renamed