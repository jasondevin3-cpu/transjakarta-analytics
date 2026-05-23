-- One row per realized abstract scheduled trip — i.e., one row per
-- (trip_id, realized departure time). Built by joining the
-- frequency-expanded departures with the trip metadata and denormalizing
-- in the most analyst-useful route / service attributes.
--
-- "Abstract" here means we do NOT enumerate service dates — that explosion
-- happens downstream in fact_scheduled_stop_event. Querying total daily
-- departures from this table requires a join with dim_service to know
-- which dates each trip's service_id is active.
--
-- Grain: (trip_id, departure_seconds_from_service_midnight).
-- Expected size: ~23k rows.

with expanded as (
    select * from {{ ref('int_frequencies_expanded') }}
),

trips as (
    select * from {{ ref('stg_gtfs__trips') }}
),

routes as (
    select * from {{ ref('dim_route') }}
),

services as (
    select * from {{ ref('dim_service') }}
),

final as (
    select
        -- stable surrogate key for the realized abstract departure
        {{ dbt_utils.generate_surrogate_key([
            't.trip_id',
            'e.departure_seconds_from_service_midnight'
        ]) }}                                          as scheduled_trip_id,

        -- core identifiers
        t.trip_id,
        t.route_id,
        t.service_id,
        t.direction_id,
        t.trip_headsign,
        t.trip_short_name,
        t.shape_id,

        -- realized departure
        e.departure_seconds_from_service_midnight,
        e.window_start_seconds                         as source_window_start_seconds,
        e.window_end_seconds                           as source_window_end_seconds,
        e.source_headway_seconds,
        e.is_exact_times,

        -- denormalized route attributes
        r.service_category                             as route_service_category,
        r.route_short_name,
        r.route_long_name,
        r.route_color_hex,

        -- denormalized service attributes
        s.service_name,
        s.active_days_count                            as service_active_days_count
    from expanded e
    inner join trips t using (trip_id)
    left  join routes r using (route_id)
    left  join services s using (service_id)
)

select * from final
