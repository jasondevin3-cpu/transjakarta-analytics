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

with calendar as (
    select * from {{ ref('stg_gtfs__calendar') }}
),

dates as (
    select date_id, day_of_week from {{ ref('dim_date') }}
),

calendar_dates as (
    select * from {{ ref('stg_gtfs__calendar_dates') }}
),

-- Cross-join each service's date window with the day spine,
-- keeping only weekdays the service runs on.
-- BigQuery convention: day_of_week 1 = Sunday, 7 = Saturday.
base_active_dates as (
    select
        c.service_id,
        d.date_id as service_date
    from calendar c
    inner join dates d
        on d.date_id between c.service_start_date and c.service_end_date
    where
        (d.day_of_week = 1 and c.runs_sunday)
        or (d.day_of_week = 2 and c.runs_monday)
        or (d.day_of_week = 3 and c.runs_tuesday)
        or (d.day_of_week = 4 and c.runs_wednesday)
        or (d.day_of_week = 5 and c.runs_thursday)
        or (d.day_of_week = 6 and c.runs_friday)
        or (d.day_of_week = 7 and c.runs_saturday)
),

removed_exceptions as (
    select service_id, exception_date as service_date
    from calendar_dates
    where exception_type_code = 2  -- service removed on this date
),

added_exceptions as (
    select service_id, exception_date as service_date
    from calendar_dates
    where exception_type_code = 1  -- service added on this date
),

after_removed as (
    select * from base_active_dates
    except distinct
    select * from removed_exceptions
),

final as (
    select * from after_removed
    union distinct
    select * from added_exceptions
)

select * from final
