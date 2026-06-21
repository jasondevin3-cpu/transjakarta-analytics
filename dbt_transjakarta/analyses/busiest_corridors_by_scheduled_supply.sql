-- Insight: Which Transjakarta corridors get the most scheduled service?
--
-- "Scheduled supply" = abstract departures per service day (every realized
-- departure the timetable promises, before calendar expansion). This is the
-- cleanest single measure of how much bus the network commits to a corridor.
--
-- Compiled, not materialized (dbt analysis). Run with:
--   dbt compile -s analysis:busiest_corridors_by_scheduled_supply
-- then paste target/compiled/.../busiest_corridors_by_scheduled_supply.sql
-- into the BigQuery console, or `dbt show --inline` for a quick peek.
--
-- Reads the pre-aggregated route summary mart, so the scan is tiny (~253 rows).

SELECT
    route_short_name,
    route_long_name,
    service_category,
    abstract_departures_count,
    distinct_stops_served,
    avg_headway_minutes,
    service_window_hours,
    RANK() OVER (ORDER BY abstract_departures_count DESC) AS supply_rank
FROM {{ ref('presentation_route_summary') }}
-- Focus on the iconic trunk BRT corridors for a clean headline chart.
-- Drop this filter to rank the entire 253-route network instead.
WHERE service_category = 'BRT'
ORDER BY abstract_departures_count DESC
LIMIT 15
