-- Generated date dimension. Not sourced from GTFS — built from a date spine
-- so any fact with a date column can be joined for time-based slicing.
-- Range: 2020-01-01 through 2030-12-31 (covers the GTFS calendar's window
-- with comfortable headroom on both ends).

with date_spine as (
    select day as date_id
    from unnest(generate_date_array(date '2020-01-01', date '2030-12-31')) as day
),

final as (
    select
        date_id,
        extract(year     from date_id) as year,
        extract(quarter  from date_id) as quarter,
        extract(month    from date_id) as month,
        extract(day      from date_id) as day_of_month,
        extract(dayofweek from date_id) as day_of_week,  -- BigQuery: 1=Sunday, 7=Saturday
        format_date('%A', date_id)     as day_name,
        format_date('%a', date_id)     as day_name_short,
        format_date('%B', date_id)     as month_name,
        format_date('%b', date_id)     as month_name_short,
        extract(isoweek  from date_id) as iso_week_number,
        format_date('%Y-%m', date_id)  as year_month,
        extract(dayofweek from date_id) in (1, 7) as is_weekend
    from date_spine
)

select * from final
