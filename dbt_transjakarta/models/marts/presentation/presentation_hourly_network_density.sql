-- One row per (clock-date × hour_of_day × service_category), with the
-- count of scheduled bus arrivals across the entire network at that
-- hour. Designed for the network-wide time-series chart on the dashboard.
--
-- Hours 24+ are normalized: an arrival at 24:15 becomes hour 0 of the
-- next clock date, which is what an analyst asking "how busy was the
-- network at 0:00 Tuesday" actually wants.
--
-- Same template + expand + re-aggregate pattern as
-- presentation_daily_stop_arrivals — pre-aggregate to a small template,
-- expand via the calendar, re-aggregate to the final grain.
--
-- Grain: (service_date × hour_of_day × service_category).
-- Expected size: ~576k rows max (3000 dates × 24 hours × 8 categories).

WITH arrival_template AS (
    SELECT
        e.service_id,
        r.service_category,
        MOD(DIV(e.arrival_seconds_from_service_midnight, 3600), 24) AS hour_of_day,
        CASE WHEN e.arrival_seconds_from_service_midnight >= 86400
             THEN 1 ELSE 0 END AS next_day_offset,
        COUNT(*) AS arrivals_count
    FROM {{ ref('fact_scheduled_stop_event') }} e
    JOIN {{ ref('dim_route') }} r USING (route_id)
    GROUP BY e.service_id, r.service_category, hour_of_day, next_day_offset
),

active_dates AS (
    SELECT * FROM {{ ref('int_service_calendar_unrolled') }}
),

expanded AS (
    SELECT
        DATE_ADD(d.service_date, INTERVAL t.next_day_offset DAY) AS clock_date,
        t.hour_of_day,
        t.service_category,
        t.arrivals_count
    FROM arrival_template t
    INNER JOIN active_dates d USING (service_id)
),

final AS (
    SELECT
        clock_date AS service_date,
        hour_of_day,
        service_category,
        SUM(arrivals_count) AS arrivals_count
    FROM expanded
    GROUP BY clock_date, hour_of_day, service_category
)

SELECT * FROM final
