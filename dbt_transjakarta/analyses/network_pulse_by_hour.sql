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

WITH hourly AS (
    SELECT
        d.service_date,
        d.hour_of_day,
        CASE WHEN dt.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        SUM(d.arrivals_count) AS arrivals_count
    FROM {{ ref('presentation_hourly_network_density') }} d
    JOIN {{ ref('dim_date') }} dt
        ON d.service_date = dt.date_id
    GROUP BY d.service_date, d.hour_of_day, day_type
)

SELECT
    hour_of_day,
    day_type,
    -- Average across all dates of that day_type, so we get a representative
    -- profile rather than a single date that might be atypical.
    ROUND(AVG(arrivals_count), 0) AS avg_arrivals_per_hour
FROM hourly
GROUP BY hour_of_day, day_type
ORDER BY hour_of_day, day_type
