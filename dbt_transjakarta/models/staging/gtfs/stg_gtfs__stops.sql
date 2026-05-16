with source as (
    select * from {{ source('raw_gtfs', 'stops') }}
),

renamed as (
    select
        cast(stop_id as string)            as stop_id,
        cast(stop_code as string)          as stop_code,
        cast(stop_name as string)          as stop_name,
        cast(stop_desc as string)          as stop_description,
        cast(stop_lat as float64)          as stop_latitude,
        cast(stop_lon as float64)          as stop_longitude,
        cast(zone_id as string)            as zone_id,
        cast(stop_url as string)           as stop_url,
        cast(location_type as int64)       as location_type,
        cast(parent_station as string)     as parent_station_id,
        cast(wheelchair_boarding as int64) as wheelchair_boarding_code
    from source
)

select * from renamed
