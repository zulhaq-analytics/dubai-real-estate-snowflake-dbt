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
                {{ rooms_to_bedrooms('ejari_property_sub_type_en') }}          as bedrooms,
        {{ rooms_to_category('ejari_property_sub_type_en') }}          as room_category,
        case {{ rooms_to_category('ejari_property_sub_type_en') }}
            when 'Studio' then 1 when '1 BR' then 2 when '2 BR' then 3 when '3 BR' then 4
            when '4 BR' then 5 when '5+ BR' then 6 when 'Penthouse' then 7
            when 'Other residential' then 8 when 'Room / Staff housing' then 9
            when 'Commercial / Other' then 10 else 11
        end                                                            as room_order,
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
                actual_area_sqm * 10.7639                                      as actual_area_sqft,
        case
            when actual_area_sqm is null or actual_area_sqm <= 0   then null
            when actual_area_sqm * 10.7639 < 450                   then 'XS · ≈ Studio'
            when actual_area_sqm * 10.7639 < 850                   then 'S · ≈ 1 BR'
            when actual_area_sqm * 10.7639 < 1300                  then 'M · ≈ 2 BR'
            when actual_area_sqm * 10.7639 < 1900                  then 'L · ≈ 3 BR'
            else 'XL · ≈ 4 BR+'
        end                                                            as size_band,
        case
            when actual_area_sqm is null or actual_area_sqm <= 0   then null
            when actual_area_sqm * 10.7639 < 450                   then 1
            when actual_area_sqm * 10.7639 < 850                   then 2
            when actual_area_sqm * 10.7639 < 1300                  then 3
            when actual_area_sqm * 10.7639 < 1900                  then 4
            else 5
        end                                                            as size_band_order,
        (
            annual_rent_aed >= 1000
            and actual_area_sqm between 10 and 100000
            and contract_days >= 28
        )                                                              as is_rent_valid
    from enriched

)

select * from final