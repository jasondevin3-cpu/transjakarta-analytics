with source as (
    select * from {{ source('raw_gtfs', 'trips') }}
),

renamed as (
    select
        cast(trip_id as string)              as trip_id,
        cast(route_id as string)             as route_id,
        cast(service_id as string)           as service_id,
        cast(trip_headsign as string)        as trip_headsign,
        cast(trip_short_name as string)      as trip_short_name,
        cast(direction_id as int64)          as direction_id,
        cast(block_id as string)             as block_id,
        cast(shape_id as string)             as shape_id,
        cast(wheelchair_accessible as int64) as wheelchair_accessible_code,
        cast(bikes_allowed as int64)         as bikes_allowed_code
    from source
)

select * from renamed
