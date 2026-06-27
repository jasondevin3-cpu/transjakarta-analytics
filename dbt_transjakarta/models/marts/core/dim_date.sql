-- Generated date dimension. Not sourced from GTFS — built from a date spine
-- so any fact with a date column can be joined for time-based slicing.
-- Range: 2020-01-01 through 2030-12-31 (covers the GTFS calendar's window
-- with comfortable headroom on both ends).
-- Grain: date. Material: table (marts_core). Rows: 4,018 (snapshot 2026-04-30).

WITH date_spine AS (
    SELECT day AS date_id
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2020-01-01', DATE '2030-12-31')) AS day
),

final AS (
    SELECT
        date_id,
        EXTRACT(YEAR FROM date_id) AS year,
        EXTRACT(QUARTER FROM date_id) AS quarter,
        EXTRACT(MONTH FROM date_id) AS month,
        EXTRACT(DAY FROM date_id) AS day_of_month,
        EXTRACT(DAYOFWEEK FROM date_id) AS day_of_week,  -- BigQuery: 1=Sunday, 7=Saturday
        FORMAT_DATE('%A', date_id) AS day_name,
        FORMAT_DATE('%a', date_id) AS day_name_short,
        FORMAT_DATE('%B', date_id) AS month_name,
        FORMAT_DATE('%b', date_id) AS month_name_short,
        EXTRACT(ISOWEEK FROM date_id) AS iso_week_number,
        FORMAT_DATE('%Y-%m', date_id) AS year_month,
        EXTRACT(DAYOFWEEK FROM date_id) IN (1, 7) AS is_weekend
    FROM date_spine
)

SELECT * FROM final
