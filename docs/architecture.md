# Architecture notes

Companion document to the architecture diagram in the README.

## Why this stack

**BigQuery.** Free tier covers this workload comfortably (GTFS for one mid-sized agency is a few hundred MB at most). BigQuery is also the warehouse most commonly used in SEA and at Indonesian data orgs, so building on it doubles as relevant interview prep.

**GCS as the immutable raw landing zone.** Every ingestion run archives the original GTFS zip and per-table CSVs under a date-partitioned prefix. The BigQuery raw tables are `WRITE_TRUNCATE`d to always reflect the latest feed; if we ever need to reproduce a past state, we can replay from GCS. This separation between "archive" (GCS) and "current snapshot" (BQ) keeps storage cheap and analysis fast.

**Plain Python ingestion (no dlt / Airbyte / Meltano).** The data volume doesn't justify a framework. A 200-line script is more legible to a reviewer than a framework config, and the loader's "do one thing well" structure is easier to test.

**dbt with a three-layer model.**
1. **Staging** (`stg_*`, views): 1:1 with raw, only cleaning + types + renames. No business logic.
2. **Intermediate** (`int_*`, ephemeral CTEs): reusable transformations not exposed to end-users — joins, calendar unrolling, geographic enrichments.
3. **Marts** (tables): `marts_core` for conformed `dim_*` and `fact_*`, `marts_presentation` for `report_*` wide tables.

The ephemeral materialization for intermediate models keeps the surface area of BigQuery objects small (fewer things for a reviewer to be confused by) while still letting us reuse logic via `ref()`. Marts are materialized as tables because they're queried repeatedly by the dashboard and by ad-hoc analysis.

**No Terraform.** The GCP resource set is small (one bucket, six datasets, one service account). Manual setup with a README runbook is the right level of ceremony for a portfolio project. If this ever scales beyond a personal project, Terraform would be the next step.

## Data freshness

GTFS static feeds change infrequently (typically when routes or schedules are modified — every few weeks at most). Ingestion runs nightly via GitHub Actions (added in Phase 3); `dbt source freshness` warns if the latest feed is more than 8 days old and errors after 30 days.

## Testing strategy

Three layers of tests:
1. **Schema-level** (`not_null`, `unique`, `relationships`, `accepted_values`) on every key column.
2. **Domain-level** via `dbt_expectations` — for example, that all stop latitudes fall inside Jakarta's bounding box.
3. **Custom singular tests** in `dbt_transjakarta/tests/` for cross-model invariants that don't fit a generic test.

Tests run on every PR via GitHub Actions and gate merges to `main`.
