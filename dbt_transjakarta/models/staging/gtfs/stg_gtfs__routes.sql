with source as (
    select * from {{ source('raw_gtfs', 'routes') }}
),

renamed as (
    select
        cast(route_id as string)         as route_id,
        cast(agency_id as string)        as agency_id,
        cast(route_short_name as string) as route_short_name,
        cast(route_long_name as string)  as route_long_name,
        cast(route_desc as string)       as route_description,
        cast(route_type as int64)        as route_type_code,
        case cast(route_type as int64)
            when 0 then 'tram'
            when 1 then 'subway'
            when 2 then 'rail'
            when 3 then 'bus'
            when 4 then 'ferry'
            when 5 then 'cable_tram'
            when 6 then 'aerial_lift'
            when 7 then 'funicular'
            when 11 then 'trolleybus'
            when 12 then 'monorail'
            else 'unknown'
        end                              as route_type_name,
        cast(route_url as string)        as route_url,
        cast(route_color as string)      as route_color_hex,
        cast(route_text_color as string) as route_text_color_hex
    from source
)

select * from renamed
