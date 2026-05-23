-- Apex fact of the model: one row per scheduled stop visit for every
-- realized scheduled trip. Built by joining fact_scheduled_trip with the
-- per-trip stop-time template from int_stop_times_with_offsets and adding
-- the template offset to the realized trip start.
--
-- This is what powers every stop-level analytical question — busiest
-- stops, peak-hour density at each stop, per-stop arrival distributions,
-- network throughput by hour, etc.
--
-- Grain: (scheduled_trip_id, stop_sequence).
-- Expected size: ~70k scheduled_trips × ~37 stops/trip ≈ 2.6M rows.

with sched as (
    select * from {{ ref('fact_scheduled_trip') }}
),

stop_offsets as (
    select * from {{ ref('int_stop_times_with_offsets') }}
),

final as (
    select
        -- surrogate PK
        {{ dbt_utils.generate_surrogate_key([
            's.scheduled_trip_id',
            'so.stop_sequence'
        ]) }}                                              as scheduled_stop_event_id,

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
            as arrival_seconds_from_service_midnight,
        s.departure_seconds_from_service_midnight + so.departure_offset_seconds
            as departure_seconds_from_service_midnight,

        -- the trip's realized start time (helpful for grouping)
        s.departure_seconds_from_service_midnight
            as trip_start_seconds_from_service_midnight,

        -- denormalized attributes for analyst convenience
        so.stop_headsign,
        so.shape_distance_traveled,
        s.route_short_name,
        s.route_long_name,
        s.route_service_category,
        s.service_name
    from sched s
    inner join stop_offsets so using (trip_id)
)

select * from final
