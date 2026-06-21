WITH source AS (
    SELECT * FROM {{ source('raw_gtfs', 'calendar_dates') }}
),

renamed AS (
    SELECT
        CAST(service_id AS STRING) AS service_id,
        PARSE_DATE('%Y%m%d', CAST(date AS STRING)) AS exception_date,
        CAST(exception_type AS INT64) AS exception_type_code,
        CASE CAST(exception_type AS INT64)
            WHEN 1 THEN 'added'
            WHEN 2 THEN 'removed'
            ELSE 'unknown'
        END AS exception_type_name
    FROM source
)

SELECT * FROM renamed
