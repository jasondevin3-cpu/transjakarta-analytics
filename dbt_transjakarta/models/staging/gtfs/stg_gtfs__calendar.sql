WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'calendar') }}
),

renamed AS (
    SELECT
        CAST(service_id AS STRING) AS service_id,
        CAST(monday AS INT64) = 1 AS runs_monday,
        CAST(tuesday AS INT64) = 1 AS runs_tuesday,
        CAST(wednesday AS INT64) = 1 AS runs_wednesday,
        CAST(thursday AS INT64) = 1 AS runs_thursday,
        CAST(friday AS INT64) = 1 AS runs_friday,
        CAST(saturday AS INT64) = 1 AS runs_saturday,
        CAST(sunday AS INT64) = 1 AS runs_sunday,
        PARSE_DATE('%Y%m%d', CAST(start_date AS STRING)) AS service_start_date,
        PARSE_DATE('%Y%m%d', CAST(end_date AS STRING)) AS service_end_date
    FROM source
)

SELECT * FROM renamed
