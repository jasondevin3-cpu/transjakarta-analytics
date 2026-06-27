-- Purpose: route dimension — clean route attributes plus a derived
--          service_category (BRT, Mikrotrans, Royaltrans, …) from route_desc.
-- Grain:   route_id.
-- Material: table (marts_core).
-- Rows:    253 (snapshot 2026-04-30).

WITH source AS (
    SELECT * FROM {{ ref('stg_gtfs__routes') }}
),

final AS (
    SELECT
        route_id,
        route_short_name,
        route_long_name,
        route_description,
        -- TJ uses route_desc as a service-tier label (BRT, Mikrotrans, Royaltrans,
        -- Transjabodetabek, Rusun, Shuttle, Bus Wisata, Angkutan Umum Integrasi).
        -- Surface it as service_category so analysts don't have to guess.
        COALESCE(NULLIF(route_description, ''), 'Unknown') AS service_category,
        route_type_code,
        route_type_name,
        route_color_hex,
        route_text_color_hex,
        agency_id
    FROM source
)

SELECT * FROM final
