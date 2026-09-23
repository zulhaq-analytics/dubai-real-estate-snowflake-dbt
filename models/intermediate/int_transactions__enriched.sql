with transactions as (

    select * from {{ ref('stg_dld__transactions') }}

),

procedures as (

    select
        trans_group_id,
        procedure_id,
        is_pre_registration
    from {{ ref('stg_dld__transaction_procedures') }}

),

enriched as (

    select
        t.transaction_id,
        t.transaction_date,
        date_trunc('month', t.transaction_date)                        as transaction_month,
        year(t.transaction_date)                                       as transaction_year,

        t.trans_group_id,
        t.trans_group_en,
        t.procedure_id,
        t.procedure_name_en,
        p.is_pre_registration,
        (t.trans_group_en ilike 'sales%')                              as is_sale,

        t.reg_type_id,
        t.reg_type_en,
        (t.reg_type_en ilike 'off%plan%')                              as is_off_plan,

        t.property_type_id,
        t.property_type_en,
        t.property_sub_type_id,
        t.property_sub_type_en,
        t.property_usage_en,
        t.rooms_en,
        {{ rooms_to_bedrooms('t.rooms_en') }}                          as bedrooms,
        {{ rooms_to_category('t.rooms_en') }}                          as room_category,
        t.has_parking,

        t.procedure_area_sqm,
        t.actual_worth_aed,
        t.actual_worth_aed / nullif(t.procedure_area_sqm, 0)           as price_per_sqm_aed,
        (
            t.actual_worth_aed >= 10000
            and t.procedure_area_sqm between 10 and 100000
        )                                                              as is_price_valid,

        t.no_of_parties_role_1,
        t.no_of_parties_role_2,
        t.no_of_parties_role_3,

        t.area_id,
        t.area_name_en,
        t.project_number,
        t.project_name_en,
        t.master_project_en,
        t.building_name_en,
        t.nearest_metro_en,
        t.nearest_mall_en,
        t.nearest_landmark_en,

        t._loaded_at

    from transactions t
    left join procedures p
        on  t.trans_group_id = p.trans_group_id
        and t.procedure_id   = p.procedure_id

)

select * from enriched