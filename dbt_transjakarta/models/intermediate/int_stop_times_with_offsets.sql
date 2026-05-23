-- For each (trip_id, stop_sequence) in stg_gtfs__stop_times, compute the
-- arrival/departure offset (in seconds) relative to the trip's first-stop
-- arrival time. This is the per-stop "template" that, added to a realized
-- scheduled departure, gives the realized arrival/departure at that stop.
--
-- Example for trip 10A-L02:
--   stop_sequence=0  arrival=05:00:00  departure=05:00:10  → offsets (0, 10)
--   stop_sequence=1  arrival=05:03:01  departure=05:03:11  → offsets (181, 191)
--
-- So when fact_scheduled_trip says "this trip departs at 06:00:00",
-- fact_scheduled_stop_event will compute stop 1's arrival as
--   06:00:00 + 181 sec = 06:03:01
--
-- Grain: (trip_id, stop_sequence) — same as stg_gtfs__stop_times.
-- Materialization: ephemeral.

with stop_times as (
    select * from {{ ref('stg_gtfs__stop_times') }}
),

with_offsets as (
    select
        trip_id,
        stop_id,
        stop_sequence,
        arrival_seconds_from_service_midnight   as template_arrival_seconds,
        departure_seconds_from_service_midnight as template_departure_seconds,

        -- offset from trip's first-stop arrival
        arrival_seconds_from_service_midnight
            - min(arrival_seconds_from_service_midnight) over (partition by trip_id)
            as arrival_offset_seconds,

        departure_seconds_from_service_midnight
            - min(arrival_seconds_from_service_midnight) over (partition by trip_id)
            as departure_offset_seconds,

        stop_headsign,
        shape_distance_traveled
    from stop_times
)

select * from with_offsets
