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

with arrival_template as (
    select
        e.service_id,
        r.service_category,
        mod(div(e.arrival_seconds_from_service_midnight, 3600), 24) as hour_of_day,
        case when e.arrival_seconds_from_service_midnight >= 86400
             then 1 else 0 end                                       as next_day_offset,
        count(*) as arrivals_count
    from {{ ref('fact_scheduled_stop_event') }} e
    join {{ ref('dim_route') }} r using (route_id)
    group by e.service_id, r.service_category, hour_of_day, next_day_offset
),

active_dates as (
    select * from {{ ref('int_service_calendar_unrolled') }}
),

expanded as (
    select
        date_add(d.service_date, interval t.next_day_offset day) as clock_date,
        t.hour_of_day,
        t.service_category,
        t.arrivals_count
    from arrival_template t
    inner join active_dates d using (service_id)
),

final as (
    select
        clock_date as service_date,
        hour_of_day,
        service_category,
        sum(arrivals_count) as arrivals_count
    from expanded
    group by clock_date, hour_of_day, service_category
)

select * from final
