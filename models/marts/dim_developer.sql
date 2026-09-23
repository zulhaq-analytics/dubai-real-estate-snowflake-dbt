select
    developer_id,
    developer_number,
    developer_name_en,
    developer_name_ar,
    legal_status_en,
    license_type_en,
    license_issue_date,
    license_expiry_date,
    registration_date
from {{ ref('stg_dld__developers') }}