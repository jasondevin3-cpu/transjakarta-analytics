-- One row per (clock-date × stop_id), with the count of scheduled bus
-- arrivals at that stop on that date across the entire network.
--
-- Computed by:
--   1. Pre-aggregating fact_scheduled_stop_event to (service_id, stop_id,
--      next_day_offset) — collapses millions of arrivals to ~tens of
--      thousands of templates before any cross-join.
--   2. Cross-joining with int_service_calendar_unrolled to enumerate every
--      calendar date each (service × stop × next_day_offset) is realized.
--   3. Applying the date shift for hours 24+ — those arrivals belong to
--      the *next* clock date (per the GTFS service-day overflow
--      convention) — and re-aggregating to (clock_date × stop_id).
--
-- Grain: (service_date × stop_id). Service_date here is the CLOCK date,
-- not the GTFS service date, so a query "give me Tuesday's arrivals"
-- returns what actually happened during Tuesday's calendar hours.
--
-- Expected size: ~18M rows.

WITH arrival_template AS (
    SELECT
        service_id,
        stop_id,
        CASE WHEN arrival_seconds_from_service_midnight >= 86400
             THEN 1 ELSE 0 END AS next_day_offset,
        COUNT(*) AS arrivals_count
    FROM {{ ref('fact_scheduled_stop_event') }}
    GROUP BY service_id, stop_id, next_day_offset
),

active_dates AS (
    SELECT * FROM {{ ref('int_service_calendar_unrolled') }}
),

expanded AS (
    SELECT
        DATE_ADD(d.service_date, INTERVAL t.next_day_offset DAY) AS clock_date,
        t.stop_id,
        t.arrivals_count
    FROM arrival_template t
    INNER JOIN active_dates d USING (service_id)
),

final AS (
    SELECT
        clock_date AS service_date,
        stop_id,
        SUM(arrivals_count) AS arrivals_count
    FROM expanded
    GROUP BY clock_date, stop_id
)

SELECT * FROM final
