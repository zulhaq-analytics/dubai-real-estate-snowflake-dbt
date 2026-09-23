with rents as (

    select * from {{ ref('stg_dld__rent_contracts') }}

),

enriched as (

    select
        contract_id,
        line_number,
        contract_reg_type_en,
        (contract_reg_type_en ilike 'new%')                            as is_new_contract,

        contract_start_date,
        contract_end_date,
        date_trunc('month', contract_start_date)                       as start_month,
        year(contract_start_date)                                      as start_year,
        datediff('day', contract_start_date, contract_end_date) + 1    as contract_days,

        contract_amount_aed,
        annual_amount_aed,
        coalesce(
            annual_amount_aed,
            contract_amount_aed * 365
                / nullif(datediff('day', contract_start_date, contract_end_date) + 1, 0)
        )                                                              as annual_rent_aed,

        no_of_properties,
        (no_of_properties = 1)                                         as is_single_property,
        actual_area_sqm,

        ejari_property_type_en,
        ejari_property_sub_type_en,
        ejari_bus_property_type_en,
        property_usage_en,
        (property_usage_en = 'Residential')                            as is_residential,
        tenant_type_en,
        is_free_hold,

        area_id,
        area_name_en,
        project_number,
        project_name_en,
        master_project_en,
        nearest_metro_en,
        nearest_mall_en,
        nearest_landmark_en,

        _loaded_at

    from rents

),

final as (

    select
        *,
        annual_rent_aed / nullif(actual_area_sqm, 0)                   as rent_per_sqm_aed,
        (
            annual_rent_aed >= 1000
            and actual_area_sqm between 10 and 100000
            and contract_days >= 28
        )                                                              as is_rent_valid
    from enriched

)

select * from final