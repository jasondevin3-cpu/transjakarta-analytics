-- Purpose: one row per realized abstract scheduled trip — i.e. one row per
--          (trip_id, realized departure time) — with route and service
--          attributes denormalized in for analyst convenience.
-- Grain:   (trip_id, departure_seconds_from_service_midnight).
-- Material: table (marts_core).
-- Rows:    70,322 (snapshot 2026-04-30).
--
-- "Abstract" means we do NOT enumerate service dates here — that explosion
-- happens downstream in fact_scheduled_stop_event. To count real daily
-- departures, join dim_service to know which dates each service_id is active.
--
-- Note: the frequency-expansion step below used to live in its own
-- intermediate model (int_frequencies_expanded). It had exactly one consumer
-- — this model — so it was inlined here as a CTE to remove a single-use
-- "phantom" model. The shared calendar logic stays in int_service_calendar_unrolled.

WITH frequencies AS (
    SELECT * FROM {{ ref('stg_gtfs__frequencies') }}
),

-- Expand each frequency window into one row per realized abstract departure.
-- A row like (trip=10A-L02, start=05:00, end=22:00, headway=2180) becomes
-- ~28 rows, one per (start + N*headway).
--
-- GTFS semantics: end_time is EXCLUSIVE (a departure exactly at end_time is
-- not generated). We enforce that with `end_seconds - 1` as the GENERATE_ARRAY
-- upper bound — safe because no two TJ windows produce departures less than
-- 1 second apart, and adjacent windows already share a boundary (the next
-- window owns the boundary timestamp).
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
),

trips AS (
    SELECT * FROM {{ ref('stg_gtfs__trips') }}
),

routes AS (
    SELECT * FROM {{ ref('dim_route') }}
),

services AS (
    SELECT * FROM {{ ref('dim_service') }}
),

final AS (
    SELECT
        -- stable surrogate key for the realized abstract departure
        {{ dbt_utils.generate_surrogate_key([
            't.trip_id',
            'e.departure_seconds_from_service_midnight'
        ]) }} AS scheduled_trip_id,

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
        e.window_start_seconds AS source_window_start_seconds,
        e.window_end_seconds AS source_window_end_seconds,
        e.source_headway_seconds,
        e.is_exact_times,

        -- denormalized route attributes
        r.service_category AS route_service_category,
        r.route_short_name,
        r.route_long_name,
        r.route_color_hex,

        -- denormalized service attributes
        s.service_name,
        s.active_days_count AS service_active_days_count
    FROM expanded e
    INNER JOIN trips t USING (trip_id)
    LEFT JOIN routes r USING (route_id)
    LEFT JOIN services s USING (service_id)
)

SELECT * FROM final
