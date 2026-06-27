-- Unroll each service_id from stg_gtfs__calendar into one row per active
-- (service_id, service_date). The calendar table says "service HK runs
-- Mon-Fri from 2004-01-15 to 2027-12-31"; this model materializes that into
-- one row per (HK, every Mon-Fri date in that window).
--
-- Then layer on stg_gtfs__calendar_dates exceptions:
--   exception_type_code = 2 → service NOT running on that date (subtract)
--   exception_type_code = 1 → service ADDED on that date     (union in)
--
-- Grain: (service_id, service_date) — one row per active service-day.
-- Materialization: ephemeral (per dbt_project.yml intermediate config).
--
-- This is the project's ONLY intermediate model. It earns its place because
-- three models reuse it (dim_service + the two date-expanding presentation
-- tables) — keeping the logic here avoids copy-pasting it in three places.
-- The two former single-use intermediates were inlined into their facts.

WITH calendar AS (
    SELECT * FROM {{ ref('stg_gtfs__calendar') }}
),

dates AS (
    SELECT date_id, day_of_week FROM {{ ref('dim_date') }}
),

calendar_dates AS (
    SELECT * FROM {{ ref('stg_gtfs__calendar_dates') }}
),

-- Cross-join each service's date window with the day spine,
-- keeping only weekdays the service runs on.
-- BigQuery convention: day_of_week 1 = Sunday, 7 = Saturday.
base_active_dates AS (
    SELECT
        c.service_id,
        d.date_id AS service_date
    FROM calendar c
    INNER JOIN dates d
        ON d.date_id BETWEEN c.service_start_date AND c.service_end_date
    WHERE
        (d.day_of_week = 1 AND c.runs_sunday)
        OR (d.day_of_week = 2 AND c.runs_monday)
        OR (d.day_of_week = 3 AND c.runs_tuesday)
        OR (d.day_of_week = 4 AND c.runs_wednesday)
        OR (d.day_of_week = 5 AND c.runs_thursday)
        OR (d.day_of_week = 6 AND c.runs_friday)
        OR (d.day_of_week = 7 AND c.runs_saturday)
),

removed_exceptions AS (
    SELECT service_id, exception_date AS service_date
    FROM calendar_dates
    WHERE exception_type_code = 2  -- service removed on this date
),

added_exceptions AS (
    SELECT service_id, exception_date AS service_date
    FROM calendar_dates
    WHERE exception_type_code = 1  -- service added on this date
),

after_removed AS (
    SELECT * FROM base_active_dates
    EXCEPT DISTINCT
    SELECT * FROM removed_exceptions
),

final AS (
    SELECT * FROM after_removed
    UNION DISTINCT
    SELECT * FROM added_exceptions
)

SELECT * FROM final
