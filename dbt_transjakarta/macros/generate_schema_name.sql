-- Clean, unprefixed schema (dataset) names.
--
-- By default dbt names a model's schema `<target.schema>_<custom_schema>`, which is
-- how this project used to produce the dbt_dev_jason_* sandbox datasets. This project
-- runs as a single environment, so we override that: each model lands in exactly the
-- dataset named by its `+schema` config — staging, marts_core, marts_presentation —
-- with no target/sandbox prefix. Models without a `+schema` fall back to target.schema
-- (currently none do).
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
