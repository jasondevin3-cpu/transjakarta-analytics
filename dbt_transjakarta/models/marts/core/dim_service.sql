WITH calendar AS (
    SELECT * FROM {{ ref('stg_gtfs__calendar') }}
),

active_dates AS (
    SELECT
        service_id,
        COUNT(*) AS active_days_count,
        MIN(service_date) AS first_active_date,
        MAX(service_date) AS last_active_date
    FROM {{ ref('int_service_calendar_unrolled') }}
    GROUP BY service_id
),

final AS (
    SELECT
        c.service_id,
        -- Derive a friendly name from the per-day pattern, falling back to
        -- "Custom (<id>)" when the pattern doesn't match a common shape.
        CASE
            WHEN c.runs_monday AND c.runs_tuesday AND c.runs_wednesday
                 AND c.runs_thursday AND c.runs_friday
                 AND c.runs_saturday AND c.runs_sunday
                THEN CONCAT('Daily (', c.service_id, ')')
            WHEN c.runs_monday AND c.runs_tuesday AND c.runs_wednesday
                 AND c.runs_thursday AND c.runs_friday
                 AND NOT c.runs_saturday AND NOT c.runs_sunday
                THEN CONCAT('Weekday (', c.service_id, ')')
            WHEN NOT c.runs_monday AND NOT c.runs_tuesday
                 AND NOT c.runs_wednesday AND NOT c.runs_thursday
                 AND NOT c.runs_friday
                 AND c.runs_saturday AND c.runs_sunday
                THEN CONCAT('Weekend (', c.service_id, ')')
            WHEN c.runs_monday AND c.runs_tuesday AND c.runs_wednesday
                 AND c.runs_thursday AND c.runs_friday AND c.runs_saturday
                 AND NOT c.runs_sunday
                THEN CONCAT('Mon–Sat (', c.service_id, ')')
            WHEN NOT c.runs_monday AND NOT c.runs_tuesday
                 AND NOT c.runs_wednesday AND NOT c.runs_thursday
                 AND NOT c.runs_friday AND NOT c.runs_saturday
                 AND c.runs_sunday
                THEN CONCAT('Sunday only (', c.service_id, ')')
            WHEN NOT c.runs_monday AND NOT c.runs_tuesday
                 AND NOT c.runs_wednesday AND NOT c.runs_thursday
                 AND c.runs_friday AND NOT c.runs_saturday
                 AND NOT c.runs_sunday
                THEN CONCAT('Friday only (', c.service_id, ')')
            ELSE CONCAT('Custom (', c.service_id, ')')
        END AS service_name,
        c.service_start_date,
        c.service_end_date,
        COALESCE(ad.active_days_count, 0) AS active_days_count,
        ad.first_active_date,
        ad.last_active_date,
        c.runs_monday,
        c.runs_tuesday,
        c.runs_wednesday,
        c.runs_thursday,
        c.runs_friday,
        c.runs_saturday,
        c.runs_sunday
    FROM calendar c
    LEFT JOIN active_dates ad USING (service_id)
)

SELECT * FROM final
