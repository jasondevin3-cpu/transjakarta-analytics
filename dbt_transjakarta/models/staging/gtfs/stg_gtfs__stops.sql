WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'stops') }}
),

renamed AS (
    SELECT
        CAST(stop_id AS STRING) AS stop_id,
        CAST(stop_code AS STRING) AS stop_code,
        CAST(stop_name AS STRING) AS stop_name,
        CAST(stop_desc AS STRING) AS stop_description,
        CAST(stop_lat AS FLOAT64) AS stop_latitude,
        CAST(stop_lon AS FLOAT64) AS stop_longitude,
        CAST(zone_id AS STRING) AS zone_id,
        CAST(stop_url AS STRING) AS stop_url,
        CAST(location_type AS INT64) AS location_type,
        CAST(parent_station AS STRING) AS parent_station_id,
        CAST(wheelchair_boarding AS INT64) AS wheelchair_boarding_code
    FROM source
)

SELECT * FROM renamed
