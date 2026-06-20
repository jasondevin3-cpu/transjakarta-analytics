-- Insight: When does the Transjakarta network run hottest during the day?
--
-- Averages scheduled bus arrivals across the whole network for each hour of
-- the day, on a typical weekday vs. weekend. Shows the daily "pulse" — the
-- morning/evening commute peaks and the overnight trough — and how the
-- weekend profile flattens relative to weekdays.
--
-- Compiled, not materialized (dbt analysis). Run with:
--   dbt compile -s analysis:network_pulse_by_hour
--
-- Reads the pre-aggregated hourly density mart and joins dim_date only to
-- label weekday vs. weekend, so the scan stays small.

with hourly as (
    select
        d.service_date,
        d.hour_of_day,
        case when dt.is_weekend then 'Weekend' else 'Weekday' end as day_type,
        sum(d.arrivals_count) as arrivals_count
    from {{ ref('presentation_hourly_network_density') }} d
    join {{ ref('dim_date') }} dt
        on d.service_date = dt.date_id
    group by d.service_date, d.hour_of_day, day_type
)

select
    hour_of_day,
    day_type,
    -- Average across all dates of that day_type, so we get a representative
    -- profile rather than a single date that might be atypical.
    round(avg(arrivals_count), 0) as avg_arrivals_per_hour
from hourly
group by hour_of_day, day_type
order by hour_of_day, day_type
