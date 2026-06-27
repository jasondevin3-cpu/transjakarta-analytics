-- Purpose: stop dimension — clean stop attributes; decodes location_type and
--          wheelchair_boarding; adds an is_station flag.
-- Grain:   stop_id.
-- Material: table (marts_core).
-- Rows:    8,216 (snapshot 2026-04-30).

WITH source AS (
    SELECT * FROM {{ ref('stg_gtfs__stops') }}
),

final AS (
    SELECT
        stop_id,
        stop_code,
        stop_name,
        stop_description,
        stop_latitude,
        stop_longitude,
        zone_id,
        parent_station_id,
        location_type,
        CASE location_type
            WHEN 0 THEN 'stop_or_platform'
            WHEN 1 THEN 'station'
            WHEN 2 THEN 'entrance_or_exit'
            WHEN 3 THEN 'generic_node'
            WHEN 4 THEN 'boarding_area'
            ELSE 'unknown'
        END AS location_type_name,
        location_type = 1 AS is_station,
        wheelchair_boarding_code,
        CASE wheelchair_boarding_code
            WHEN 0 THEN 'unknown'
            WHEN 1 THEN 'accessible'
            WHEN 2 THEN 'not_accessible'
            ELSE 'unknown'
        END AS wheelchair_boarding_name
    FROM source
)

SELECT * FROM final
