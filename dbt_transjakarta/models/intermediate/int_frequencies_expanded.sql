-- Expand each row in stg_gtfs__frequencies into one row per realized
-- abstract departure. A row like (trip=10A-L02, start=05:00, end=22:00,
-- headway=2180) becomes ~28 rows — one per (start + N*headway) where
-- start + N*headway < end.
--
-- GTFS semantics: end_time is EXCLUSIVE (a departure at end_time itself
-- is not generated). We enforce that by using `end_seconds - 1` as the
-- upper bound of GENERATE_ARRAY — safe because no two TJ windows produce
-- departures less than 1 second apart, and adjacent windows already share
-- a boundary (the next window owns the boundary timestamp).
--
-- Grain: (trip_id, departure_seconds_from_service_midnight).
-- Materialization: ephemeral (per intermediate config in dbt_project.yml).
-- Expected size: ~23k rows for TJ's 772 frequency entries.

WITH frequencies AS (
    SELECT * FROM {{ ref('stg_gtfs__frequencies') }}
),

expanded AS (
    SELECT
        f.trip_id,
        departure_seconds AS departure_seconds_from_service_midnight,
        f.start_seconds_from_service_midnight AS window_start_seconds,
        f.end_seconds_from_service_midnight AS window_end_seconds,
        f.headway_seconds AS source_headway_seconds,
        f.is_exact_times
    FROM frequencies f,
    UNNEST(
        GENERATE_ARRAY(
            f.start_seconds_from_service_midnight,
            f.end_seconds_from_service_midnight - 1,
            f.headway_seconds
        )
    ) AS departure_seconds
)

SELECT * FROM expanded
