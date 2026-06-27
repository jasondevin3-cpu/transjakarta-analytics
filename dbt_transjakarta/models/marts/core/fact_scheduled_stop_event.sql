-- Purpose: apex fact — one row per scheduled stop visit for every realized
--          scheduled trip. Adds each stop's offset (relative to the trip's
--          first arrival) onto the trip's realized start time.
-- Grain:   (scheduled_trip_id, stop_sequence).
-- Material: table (marts_core).
-- Rows:    2,984,706 (snapshot 2026-04-30) — ~70k trips × ~42 stops/trip.
--
-- This powers every stop-level question — busiest stops, peak-hour density
-- per stop, per-stop arrival distributions, network throughput by hour.
--
-- Note: the per-stop offset step below used to live in its own intermediate
-- model (int_stop_times_with_offsets). It had exactly one consumer — this
-- model — so it was inlined here as a CTE to remove a single-use "phantom"
-- model. The shared calendar logic stays in int_service_calendar_unrolled.

WITH sched AS (
    SELECT * FROM {{ ref('fact_scheduled_trip') }}
),

stop_times AS (
    SELECT * FROM {{ ref('stg_gtfs__stop_times') }}
),

-- For each (trip_id, stop_sequence), compute the arrival/departure offset
-- (in seconds) relative to the trip's first-stop arrival. Adding this offset
-- to a realized departure gives the realized time at that stop. Example for
-- trip 10A-L02: stop 0 arrives 05:00:00 → offsets (0, 10); stop 1 arrives
-- 05:03:01 → offsets (181, 191). So a trip departing 06:00:00 reaches stop 1
-- at 06:00:00 + 181s = 06:03:01.
stop_offsets AS (
    SELECT
        trip_id,
        stop_id,
        stop_sequence,

        arrival_seconds_from_service_midnight
            - MIN(arrival_seconds_from_service_midnight) OVER (PARTITION BY trip_id)
            AS arrival_offset_seconds,

        departure_seconds_from_service_midnight
            - MIN(arrival_seconds_from_service_midnight) OVER (PARTITION BY trip_id)
            AS departure_offset_seconds,

        stop_headsign,
        shape_distance_traveled
    FROM stop_times
),

final AS (
    SELECT
        -- surrogate PK
        {{ dbt_utils.generate_surrogate_key([
            's.scheduled_trip_id',
            'so.stop_sequence'
        ]) }} AS scheduled_stop_event_id,

        -- foreign keys
        s.scheduled_trip_id,
        s.trip_id,
        s.route_id,
        s.service_id,
        so.stop_id,
        s.direction_id,

        -- position in the trip
        so.stop_sequence,

        -- realized times for this stop visit
        s.departure_seconds_from_service_midnight + so.arrival_offset_seconds
            AS arrival_seconds_from_service_midnight,
        s.departure_seconds_from_service_midnight + so.departure_offset_seconds
            AS departure_seconds_from_service_midnight,

        -- the trip's realized start time (helpful for grouping)
        s.departure_seconds_from_service_midnight
            AS trip_start_seconds_from_service_midnight,

        -- denormalized attributes for analyst convenience
        so.stop_headsign,
        so.shape_distance_traveled,
        s.route_short_name,
        s.route_long_name,
        s.route_service_category,
        s.service_name
    FROM sched s
    INNER JOIN stop_offsets so USING (trip_id)
)

SELECT * FROM final
