select
    procedure_number,
    procedure_year,
    valuation_date,
    date_trunc('month', valuation_date)                          as valuation_month,
    year(valuation_date)                                         as valuation_year,
    area_id,
    procedure_name_en,
    property_type_en,
    property_sub_type_en,
    procedure_area_sqm,
    actual_area_sqm,
    actual_worth_aed,
    property_total_value_aed,
    actual_worth_aed / nullif(procedure_area_sqm, 0)             as value_per_sqm_aed,
    (
        actual_worth_aed >= 10000
        and procedure_area_sqm between 10 and 100000
    )                                                            as is_value_valid
from {{ ref('stg_dld__valuations') }}