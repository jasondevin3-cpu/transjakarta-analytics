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

with arrival_template as (
    select
        service_id,
        stop_id,
        case when arrival_seconds_from_service_midnight >= 86400
             then 1 else 0 end                            as next_day_offset,
        count(*) as arrivals_count
    from {{ ref('fact_scheduled_stop_event') }}
    group by service_id, stop_id, next_day_offset
),

active_dates as (
    select * from {{ ref('int_service_calendar_unrolled') }}
),

expanded as (
    select
        date_add(d.service_date, interval t.next_day_offset day) as clock_date,
        t.stop_id,
        t.arrivals_count
    from arrival_template t
    inner join active_dates d using (service_id)
),

final as (
    select
        clock_date as service_date,
        stop_id,
        sum(arrivals_count) as arrivals_count
    from expanded
    group by clock_date, stop_id
)

select * from final
