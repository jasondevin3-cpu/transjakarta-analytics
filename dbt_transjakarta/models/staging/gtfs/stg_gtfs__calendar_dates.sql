with source as (
    select * from {{ source('raw_gtfs', 'calendar_dates') }}
),

renamed as (
    select
        cast(service_id as string)                  as service_id,
        parse_date('%Y%m%d', cast(date as string))  as exception_date,
        cast(exception_type as int64)               as exception_type_code,
        case cast(exception_type as int64)
            when 1 then 'added'
            when 2 then 'removed'
            else 'unknown'
        end                                          as exception_type_name
    from source
)

select * from renamed
