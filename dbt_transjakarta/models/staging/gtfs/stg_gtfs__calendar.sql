with source as (
    select * from {{ source('raw_gtfs', 'calendar') }}
),

renamed as (
    select
        cast(service_id as string)              as service_id,
        cast(monday as int64) = 1               as runs_monday,
        cast(tuesday as int64) = 1              as runs_tuesday,
        cast(wednesday as int64) = 1            as runs_wednesday,
        cast(thursday as int64) = 1             as runs_thursday,
        cast(friday as int64) = 1               as runs_friday,
        cast(saturday as int64) = 1             as runs_saturday,
        cast(sunday as int64) = 1               as runs_sunday,
        parse_date('%Y%m%d', cast(start_date as string)) as service_start_date,
        parse_date('%Y%m%d', cast(end_date as string))   as service_end_date
    from source
)

select * from renamed
