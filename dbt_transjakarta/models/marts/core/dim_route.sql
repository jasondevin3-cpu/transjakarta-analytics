with source as (
    select * from {{ ref('stg_gtfs__routes') }}
),

final as (
    select
        route_id,
        route_short_name,
        route_long_name,
        route_description,
        -- TJ uses route_desc as a service-tier label (BRT, Mikrotrans, Royaltrans,
        -- Transjabodetabek, Rusun, Shuttle, Bus Wisata, Angkutan Umum Integrasi).
        -- Surface it as service_category so analysts don't have to guess.
        coalesce(nullif(route_description, ''), 'Unknown') as service_category,
        route_type_code,
        route_type_name,
        route_color_hex,
        route_text_color_hex,
        agency_id
    from source
)

select * from final
