{{ config(materialized='view') }}

-- GTFS arrival/departure times use the "service day" convention:
-- values can exceed 24:00:00 for trips that cross midnight (e.g. 25:15:00 = 01:15 the next day).
-- We preserve the raw string for fidelity and also expose seconds-from-midnight
-- as an int64 for arithmetic. Trip-level service date attachment happens
-- in the intermediate layer (int_service_calendar_unrolled + a join).

WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'stop_times') }}
),

renamed AS (
    SELECT
        CAST(trip_id AS STRING) AS trip_id,
        CAST(stop_id AS STRING) AS stop_id,
        CAST(stop_sequence AS INT64) AS stop_sequence,
        CAST(arrival_time AS STRING) AS arrival_time_str,
        CAST(departure_time AS STRING) AS departure_time_str,
        {{ gtfs_time_to_seconds('arrival_time') }}   AS arrival_seconds_from_service_midnight,
        {{ gtfs_time_to_seconds('departure_time') }} AS departure_seconds_from_service_midnight,
        CAST(stop_headsign AS STRING) AS stop_headsign,
        CAST(pickup_type AS INT64) AS pickup_type_code,
        CAST(drop_off_type AS INT64) AS drop_off_type_code,
        CAST(shape_dist_traveled AS FLOAT64) AS shape_distance_traveled
    FROM source
)

SELECT * FROM renamed
