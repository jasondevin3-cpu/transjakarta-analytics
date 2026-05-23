with source as (
    select * from {{ source('raw_gtfs', 'frequencies') }}
),

renamed as (
    select
        cast(trip_id as string)                  as trip_id,
        cast(start_time as string)               as start_time_str,
        cast(end_time as string)                 as end_time_str,
        {{ gtfs_time_to_seconds('start_time') }} as start_seconds_from_service_midnight,
        {{ gtfs_time_to_seconds('end_time') }}   as end_seconds_from_service_midnight,
        cast(headway_secs as int64)              as headway_seconds,
        cast(exact_times as int64) = 1           as is_exact_times
    from source
)

select * from renamed
