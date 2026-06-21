-- One row per route, with summary KPIs an analyst or dashboard would want
-- without further joins. No calendar expansion — these are abstract /
-- template-level numbers (e.g., "abstract departures per service day"),
-- not realized-by-date totals.
--
-- Grain: (route_id). ~253 rows.

WITH trip_summary AS (
    SELECT
        route_id,
        COUNT(DISTINCT trip_id) AS distinct_trips_count,
        COUNT(*) AS abstract_departures_count,
        COUNT(DISTINCT service_id) AS distinct_services_count,
        AVG(source_headway_seconds) AS avg_headway_seconds,
        MIN(source_headway_seconds) AS min_headway_seconds,
        MAX(source_headway_seconds) AS max_headway_seconds,
        MIN(departure_seconds_from_service_midnight) AS first_departure_seconds,
        MAX(departure_seconds_from_service_midnight) AS last_departure_seconds
    FROM {{ ref('fact_scheduled_trip') }}
    GROUP BY route_id
),

stop_summary AS (
    SELECT
        route_id,
        COUNT(DISTINCT stop_id) AS distinct_stops_served
    FROM {{ ref('fact_scheduled_stop_event') }}
    GROUP BY route_id
),

final AS (
    SELECT
        r.route_id,
        r.route_short_name,
        r.route_long_name,
        r.service_category,
        r.route_color_hex,

        COALESCE(ts.distinct_trips_count, 0) AS distinct_trips_count,
        COALESCE(ts.abstract_departures_count, 0) AS abstract_departures_count,
        COALESCE(ss.distinct_stops_served, 0) AS distinct_stops_served,
        COALESCE(ts.distinct_services_count, 0) AS distinct_services_count,

        ROUND(ts.avg_headway_seconds, 0) AS avg_headway_seconds,
        ts.min_headway_seconds,
        ts.max_headway_seconds,
        ROUND(ts.avg_headway_seconds / 60.0, 1) AS avg_headway_minutes,

        ts.first_departure_seconds,
        ts.last_departure_seconds,
        ROUND((ts.last_departure_seconds - ts.first_departure_seconds) / 3600.0, 1)
            AS service_window_hours
    FROM {{ ref('dim_route') }} r
    LEFT JOIN trip_summary ts USING (route_id)
    LEFT JOIN stop_summary ss USING (route_id)
)

SELECT * FROM final
