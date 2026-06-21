WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'frequencies') }}
),

renamed AS (
    SELECT
        CAST(trip_id AS STRING) AS trip_id,
        CAST(start_time AS STRING) AS start_time_str,
        CAST(end_time AS STRING) AS end_time_str,
        {{ gtfs_time_to_seconds('start_time') }} AS start_seconds_from_service_midnight,
        {{ gtfs_time_to_seconds('end_time') }}   AS end_seconds_from_service_midnight,
        CAST(headway_secs AS INT64) AS headway_seconds,
        CAST(exact_times AS INT64) = 1 AS is_exact_times
    FROM source
)

SELECT * FROM renamed
