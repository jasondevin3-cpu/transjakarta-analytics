with calendar as (
    select * from {{ ref('stg_gtfs__calendar') }}
),

active_dates as (
    select
        service_id,
        count(*)          as active_days_count,
        min(service_date) as first_active_date,
        max(service_date) as last_active_date
    from {{ ref('int_service_calendar_unrolled') }}
    group by service_id
),

final as (
    select
        c.service_id,
        -- Derive a friendly name from the per-day pattern, falling back to
        -- "Custom (<id>)" when the pattern doesn't match a common shape.
        case
            when c.runs_monday and c.runs_tuesday and c.runs_wednesday
                 and c.runs_thursday and c.runs_friday
                 and c.runs_saturday and c.runs_sunday
                then concat('Daily (', c.service_id, ')')
            when c.runs_monday and c.runs_tuesday and c.runs_wednesday
                 and c.runs_thursday and c.runs_friday
                 and not c.runs_saturday and not c.runs_sunday
                then concat('Weekday (', c.service_id, ')')
            when not c.runs_monday and not c.runs_tuesday
                 and not c.runs_wednesday and not c.runs_thursday
                 and not c.runs_friday
                 and c.runs_saturday and c.runs_sunday
                then concat('Weekend (', c.service_id, ')')
            when c.runs_monday and c.runs_tuesday and c.runs_wednesday
                 and c.runs_thursday and c.runs_friday and c.runs_saturday
                 and not c.runs_sunday
                then concat('Mon–Sat (', c.service_id, ')')
            when not c.runs_monday and not c.runs_tuesday
                 and not c.runs_wednesday and not c.runs_thursday
                 and not c.runs_friday and not c.runs_saturday
                 and c.runs_sunday
                then concat('Sunday only (', c.service_id, ')')
            when not c.runs_monday and not c.runs_tuesday
                 and not c.runs_wednesday and not c.runs_thursday
                 and c.runs_friday and not c.runs_saturday
                 and not c.runs_sunday
                then concat('Friday only (', c.service_id, ')')
            else concat('Custom (', c.service_id, ')')
        end                                  as service_name,
        c.service_start_date,
        c.service_end_date,
        coalesce(ad.active_days_count, 0)    as active_days_count,
        ad.first_active_date,
        ad.last_active_date,
        c.runs_monday,
        c.runs_tuesday,
        c.runs_wednesday,
        c.runs_thursday,
        c.runs_friday,
        c.runs_saturday,
        c.runs_sunday
    from calendar c
    left join active_dates ad using (service_id)
)

select * from final
