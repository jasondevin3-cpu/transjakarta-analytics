WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'trips') }}
),

renamed AS (
    SELECT
        CAST(trip_id AS STRING) AS trip_id,
        CAST(route_id AS STRING) AS route_id,
        CAST(service_id AS STRING) AS service_id,
        CAST(trip_headsign AS STRING) AS trip_headsign,
        CAST(trip_short_name AS STRING) AS trip_short_name,
        CAST(direction_id AS INT64) AS direction_id,
        CAST(block_id AS STRING) AS block_id,
        CAST(shape_id AS STRING) AS shape_id,
        CAST(wheelchair_accessible AS INT64) AS wheelchair_accessible_code,
        CAST(bikes_allowed AS INT64) AS bikes_allowed_code
    FROM source
)

SELECT * FROM renamed
