{#
    Convert a GTFS HH:MM:SS time string to integer seconds-from-service-midnight.

    GTFS allows hours >= 24 to represent trips that cross midnight relative to
    the service start day (e.g. '25:15:00' = 01:15:00 on the next calendar day).
    A plain CAST AS TIME would fail on those, so we parse the parts manually.

    Returns NULL when the input is NULL or malformed.
#}
{% macro gtfs_time_to_seconds(column_name) %}
    case
        when {{ column_name }} is null then null
        when regexp_contains(cast({{ column_name }} as string), r'^\d{1,2}:\d{2}:\d{2}$') then
            safe_cast(split(cast({{ column_name }} as string), ':')[offset(0)] as int64) * 3600
            + safe_cast(split(cast({{ column_name }} as string), ':')[offset(1)] as int64) * 60
            + safe_cast(split(cast({{ column_name }} as string), ':')[offset(2)] as int64)
        else null
    end
{% endmacro %}
