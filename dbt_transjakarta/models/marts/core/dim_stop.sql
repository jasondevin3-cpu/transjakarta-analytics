with source as (
    select * from {{ ref('stg_gtfs__stops') }}
),

final as (
    select
        stop_id,
        stop_code,
        stop_name,
        stop_description,
        stop_latitude,
        stop_longitude,
        zone_id,
        parent_station_id,
        location_type,
        case location_type
            when 0 then 'stop_or_platform'
            when 1 then 'station'
            when 2 then 'entrance_or_exit'
            when 3 then 'generic_node'
            when 4 then 'boarding_area'
            else 'unknown'
        end                              as location_type_name,
        location_type = 1                as is_station,
        wheelchair_boarding_code,
        case wheelchair_boarding_code
            when 0 then 'unknown'
            when 1 then 'accessible'
            when 2 then 'not_accessible'
            else 'unknown'
        end                              as wheelchair_boarding_name
    from source
)

select * from final
