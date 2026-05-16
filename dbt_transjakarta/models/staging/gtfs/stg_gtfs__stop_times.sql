{{ config(materialized='view') }}

-- GTFS arrival/departure times use the "service day" convention:
-- values can exceed 24:00:00 for trips that cross midnight (e.g. 25:15:00 = 01:15 the next day).
-- We preserve the raw string for fidelity and also expose seconds-from-midnight
-- as an int64 for arithmetic. Trip-level service date attachment happens
-- in the intermediate layer (int_service_calendar_unrolled + a join).

with source as (
    select * from {{ source('raw_gtfs', 'stop_times') }}
),

renamed as (
    select
        cast(trip_id as string)              as trip_id,
        cast(stop_id as string)              as stop_id,
        cast(stop_sequence as int64)         as stop_sequence,
        cast(arrival_time as string)         as arrival_time_str,
        cast(departure_time as string)       as departure_time_str,
        {{ gtfs_time_to_seconds('arrival_time') }}   as arrival_seconds_from_service_midnight,
        {{ gtfs_time_to_seconds('departure_time') }} as departure_seconds_from_service_midnight,
        cast(stop_headsign as string)        as stop_headsign,
        cast(pickup_type as int64)           as pickup_type_code,
        cast(drop_off_type as int64)         as drop_off_type_code,
        cast(shape_dist_traveled as float64) as shape_distance_traveled
    from source
)

select * from renamed
