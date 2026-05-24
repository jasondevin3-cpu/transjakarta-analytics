-- One row per route, with summary KPIs an analyst or dashboard would want
-- without further joins. No calendar expansion — these are abstract /
-- template-level numbers (e.g., "abstract departures per service day"),
-- not realized-by-date totals.
--
-- Grain: (route_id). ~253 rows.

with trip_summary as (
    select
        route_id,
        count(distinct trip_id)                          as distinct_trips_count,
        count(*)                                         as abstract_departures_count,
        count(distinct service_id)                       as distinct_services_count,
        avg(source_headway_seconds)                      as avg_headway_seconds,
        min(source_headway_seconds)                      as min_headway_seconds,
        max(source_headway_seconds)                      as max_headway_seconds,
        min(departure_seconds_from_service_midnight)     as first_departure_seconds,
        max(departure_seconds_from_service_midnight)     as last_departure_seconds
    from {{ ref('fact_scheduled_trip') }}
    group by route_id
),

stop_summary as (
    select
        route_id,
        count(distinct stop_id) as distinct_stops_served
    from {{ ref('fact_scheduled_stop_event') }}
    group by route_id
),

final as (
    select
        r.route_id,
        r.route_short_name,
        r.route_long_name,
        r.service_category,
        r.route_color_hex,

        coalesce(ts.distinct_trips_count, 0)         as distinct_trips_count,
        coalesce(ts.abstract_departures_count, 0)    as abstract_departures_count,
        coalesce(ss.distinct_stops_served, 0)        as distinct_stops_served,
        coalesce(ts.distinct_services_count, 0)      as distinct_services_count,

        round(ts.avg_headway_seconds, 0)             as avg_headway_seconds,
        ts.min_headway_seconds,
        ts.max_headway_seconds,
        round(ts.avg_headway_seconds / 60.0, 1)      as avg_headway_minutes,

        ts.first_departure_seconds,
        ts.last_departure_seconds,
        round((ts.last_departure_seconds - ts.first_departure_seconds) / 3600.0, 1)
            as service_window_hours
    from {{ ref('dim_route') }} r
    left join trip_summary ts using (route_id)
    left join stop_summary ss using (route_id)
)

select * from final
