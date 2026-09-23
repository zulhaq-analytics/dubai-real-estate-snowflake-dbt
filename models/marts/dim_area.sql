select
    area_id,
    area_name_en,
    area_name_ar,
    municipality_number
from {{ ref('stg_dld__areas') }}