WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'routes') }}
),

renamed AS (
    SELECT
        CAST(route_id AS STRING) AS route_id,
        CAST(agency_id AS STRING) AS agency_id,
        CAST(route_short_name AS STRING) AS route_short_name,
        CAST(route_long_name AS STRING) AS route_long_name,
        CAST(route_desc AS STRING) AS route_description,
        CAST(route_type AS INT64) AS route_type_code,
        CASE CAST(route_type AS INT64)
            WHEN 0 THEN 'tram'
            WHEN 1 THEN 'subway'
            WHEN 2 THEN 'rail'
            WHEN 3 THEN 'bus'
            WHEN 4 THEN 'ferry'
            WHEN 5 THEN 'cable_tram'
            WHEN 6 THEN 'aerial_lift'
            WHEN 7 THEN 'funicular'
            WHEN 11 THEN 'trolleybus'
            WHEN 12 THEN 'monorail'
            ELSE 'unknown'
        END AS route_type_name,
        CAST(route_url AS STRING) AS route_url,
        CAST(route_color AS STRING) AS route_color_hex,
        CAST(route_text_color AS STRING) AS route_text_color_hex
    FROM source
)

SELECT * FROM renamed
