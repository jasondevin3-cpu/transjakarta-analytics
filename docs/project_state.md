# Project state — session handoff

Living doc. Update at the end of every working session so the next session (with or without an AI assistant) can pick up cleanly without re-asking questions.

---

## What this project is

End-to-end analytics project on publicly available **Transjakarta GTFS data**, built as a public portfolio piece targeting **analytics-engineering, BI, and data-analyst** roles. Headline deliverable is a published dbt docs site (GitHub Pages) plus a Looker Studio dashboard.

## Stack (locked in)

- **Warehouse:** BigQuery, region `asia-southeast2`, on free tier
- **Raw archive:** GCS bucket `transjakarta-analytics-raw` (same region)
- **Ingestion:** Plain Python (`requests`, `pandas`, `google-cloud-*`). No dlt/Airbyte — too much ceremony for portfolio scale
- **Transformation:** dbt-bigquery
- **Orchestration:** GitHub Actions cron + CI (Phase 3)
- **Docs/dashboard:** dbt docs on GitHub Pages + Looker Studio

## GCP values (live)

- Project ID: `transjakarta-analytics`
- Project number: `725328871562`
- Region: `asia-southeast2`
- GCS bucket: `transjakarta-analytics-raw`
- Service account: `transjakarta-dbt@transjakarta-analytics.iam.gserviceaccount.com`
- Service-account key: `./gcp-service-account.json` (gitignored)
- Datasets (all in `asia-southeast2`):
  - `raw_gtfs` — populated by ingestion
  - `raw_jakarta_open_data` — populated by ingestion (Phase 3)
  - `staging` — dbt `stg_*` views
  - `marts_core` — dbt `dim_*`, `fact_*` tables (Phase 2)
  - `marts_presentation` — dbt `report_*` tables (Phase 3)
  - `dbt_dev_jason` — personal dev sandbox

## Naming convention (locked in)

| Prefix     | Layer          | Materialization | Notes                                       |
|------------|----------------|-----------------|---------------------------------------------|
| `stg_`     | staging        | view            | 1:1 with raw, cleaning + types + renames    |
| `int_`     | intermediate   | ephemeral       | reusable business logic, not exposed        |
| `dim_`     | marts.core     | table           | conformed dimensions                        |
| `fact_`    | marts.core     | table           | conformed facts (full word, not `fct_`)     |
| `presentation_` | marts.pres. | table           | denormalized analyst-facing wide tables     |

## Architectural decisions (with rationale)

- **BigQuery over DuckDB** — DuckDB is trendier but BigQuery is what SEA/Indonesian employers use, so doubles as interview prep.
- **GCS + BQ separation** — every snapshot archived to GCS (date-partitioned), BQ raw tables are WRITE_TRUNCATE of latest. Decouples "current state" from "historical record."
- **Plain Python over dlt** — simpler, more legible for portfolio reviewers; data volume doesn't justify a framework.
- **Manual GCP setup (no Terraform)** — minimal resource set, runbook in `docs/gcp_setup.md` is the right level of ceremony.
- **`fact_` not `fct_`** — clearer for reviewers who aren't dbt-fluent.
- **dbt analyses for headline SQL** — version-controlled, linted, compiled but not materialized; great for "here's the SQL behind the insight" story.

---

## Phase status

### Phase 1 — Foundations (complete, 2026-05-21)

**Done:**
- Repo skeleton (directories, configs, README, docs)
- Python ingestion package (`ingestion/gtfs/loader.py`, `ingestion/jakarta_open_data/loader.py`)
- dbt project initialized with `packages.yml` (dbt-utils, dbt-expectations, codegen)
- Five GTFS staging models with full `schema.yml` (not_null, unique, relationships, dbt_expectations range checks)
- Custom macro `gtfs_time_to_seconds` for GTFS's 24:00:00+ time quirk
- GCP fully set up: project, billing, APIs, bucket, datasets, service account, IAM, key, budget alert
- `.env` and `~/.dbt/profiles.yml` wired with real values
- End-to-end verification: `python -c "list_datasets"` works, `dbt debug` passes "All checks passed!"
- Loader extended to support `GTFS_LOCAL_ZIP` env var (since official source is form-gated)
- PPID information-request form submitted, response received with GTFS download link
- GTFS zip placed at `./data/raw/transjakarta-gtfs.zip` (5.1 MB, snapshot 2026-04-30)
- Ingestion run successful — 12 tables loaded into `raw_gtfs.*`; raw zip + extracted CSVs archived in GCS at `gs://transjakarta-analytics-raw/gtfs/raw/2026-05-21/` and `.../staged/2026-05-21/`
- `dbt build` PASS=40/40 — 5 staging views in `dbt_dev_jason_staging.*`, 35 tests all passing
- `dbt docs generate` produced `target/catalog.json` (19 KB) and `target/manifest.json` (1.2 MB)

**Raw layer row counts (snapshot 2026-05-21):**

| Table             | Rows    |
|-------------------|---------|
| agency            | 1       |
| calendar          | 7       |
| calendar_dates    | 0       |
| routes            | 253     |
| trips             | 717     |
| stops             | 8,216   |
| stop_times        | 26,582  |
| frequencies       | 772     |
| shapes            | 247,814 |
| fare_attributes   | 6       |
| fare_rules        | 244     |
| transfers         | 14      |
| feed_info         | (skipped — not in feed) |

### Phase 2 — Modeling core (complete, 2026-05-22)

**Final `dbt build` state: PASS=104/104, 16 models, 91 data tests, 9 sources.**

Layer breakdown of what's now in `dbt_dev_jason_*`:

| Model                              | Layer           | Materialization | Rows       | Notes                                                                                       |
|------------------------------------|-----------------|-----------------|------------|---------------------------------------------------------------------------------------------|
| `stg_gtfs__frequencies`            | staging         | view            | 772        | Cleans + applies `gtfs_time_to_seconds`                                                     |
| `stg_gtfs__calendar_dates`         | staging         | view            | 0          | Materialized for future-proofing; empty in current snapshot                                 |
| `int_service_calendar_unrolled`    | intermediate    | ephemeral       | —          | Unrolls calendar × dim_date with day-of-week mask + exceptions; grain (service_id, date)    |
| `int_frequencies_expanded`         | intermediate    | ephemeral       | —          | `GENERATE_ARRAY(start, end-1, headway)` + `UNNEST` to materialize every abstract departure  |
| `int_stop_times_with_offsets`      | intermediate    | ephemeral       | —          | Adds per-stop offsets relative to trip's first arrival                                      |
| `dim_date`                         | marts_core      | table           | 4,018      | Generated date spine 2020-01-01 → 2030-12-31                                                |
| `dim_route`                        | marts_core      | table           | 253        | Adds `service_category` from `route_desc` (BRT, Mikrotrans, Royaltrans, …)                  |
| `dim_stop`                         | marts_core      | table           | 8,216      | Decodes `location_type`, `wheelchair_boarding`; `is_station` boolean                        |
| `dim_service`                      | marts_core      | table           | 7          | Friendly `service_name` derived from day pattern; `active_days_count` from int unrolled     |
| `fact_scheduled_trip`              | marts_core      | table           | 70,300     | One row per (trip_id × realized departure). md5 surrogate PK. Date NOT expanded here.       |
| `fact_scheduled_stop_event`        | marts_core      | table           | 3,000,000  | Apex fact. Joins fact_scheduled_trip × stop_times-with-offsets. Powers all stop-level analytics. |

**Sanity-check queries already validated:**
- `dim_service.active_days_count` math (HL = 2×HM as expected; HK = 5/7 of calendar window; SH = full span; X = 0 because out of dim_date window)
- Top 10 busiest routes by abstract departures (Corridor 8, 9, 1, 10, 3, … — matches the iconic TJ corridors)
- Top 10 busiest stops by scheduled arrivals (Tanah Abang, Cawang Sentral, etc. — known major interchanges)
- Bundaran HI per-hour arrival histogram — flat ~100/hr from 6am–10pm, plus hours 24 and 25 appearing as expected (see new gotcha)

### Phase 3 — Presentation + open data (ready to start)

Naming convention now uses `presentation_*` (not `report_*`) for the wide denormalized tables in `marts.presentation`.

Work for this phase:
- Populate `ingestion/jakarta_open_data/datasets.yml` registry; ingest at least one open-data dataset to enrich GTFS-only model (ridership counts? bus depots? something joinable).
- Build `presentation_*` marts — pre-joined wide tables for Looker Studio. Candidates: `presentation_daily_stop_arrivals`, `presentation_route_summary`, `presentation_hourly_network_density`.
- Wire up GitHub Actions: scheduled ingestion + dbt CI (parse, build, test on PRs).
- Deploy dbt docs to GitHub Pages — the headline portfolio artifact.

### Phase 4 — Storytelling (not started)

Looker Studio dashboard, `dbt/analyses/` SQL, README polish with screenshots, LinkedIn post.

---

## Gotchas & lessons learned

- **dbt doesn't read `.env` automatically.** `python-dotenv` is a Python library; dbt only reads OS-level environment variables. Before running `dbt build`/`run`/`test` in a fresh terminal, run `set -a; source ../.env; set +a` from inside `dbt_transjakarta/` so `GCP_PROJECT_ID` (and any other config vars in `.env`) are exported into the shell. Without this, `_gtfs__sources.yml`'s `env_var('GCP_PROJECT_ID', 'your-gcp-project-id')` falls back to the placeholder and every test / model errors with `Access Denied: Table your-gcp-project-id:raw_gtfs.*`.

- **No `requirements.txt` exists yet.** The `.venv` was set up ad-hoc; first run after a fresh clone failed with `ModuleNotFoundError: No module named 'dotenv'`. Phase-2 cleanup: pin actual installed versions into a `requirements.txt` (or `pyproject.toml`) so the next person can `pip install -r requirements.txt` and have everything work. Current confirmed-needed packages: `requests`, `python-dotenv`, `google-cloud-bigquery>=3.0`, `google-cloud-storage>=2.0`, `pandas`, `dbt-bigquery` (pulls in `dbt-core`), `sqlfluff`.

- **Cosmetic dbt deprecation warnings (still passing tests; address opportunistically):**
  - `PropertyMovedToConfigDeprecation` — `freshness:` under sources should be nested under `config:` in newer dbt versions.
  - `MissingArgumentsPropertyInGenericTestDeprecation` (9 occurrences) — top-level arguments to generic tests (`dbt_expectations.expect_column_values_to_be_between`, `relationships`) should be nested under an `arguments:` key.

- **TJ source schema observations worth knowing for modeling:**
  - Only 7 service patterns in `calendar.txt` (`HK` = Hari Kerja/weekday, `HL` = Hari Libur/weekend, +5 more — likely Ramadan / special schedules; verify when building `dim_service`).
  - `calendar_dates.txt` is empty in this snapshot — no holiday exceptions defined. `dim_service` can ignore exception logic for now but should be designed to absorb them.
  - `route_id`s mix numeric (`"9"`) and alphanumeric (`"BW2"`, `"9-P23"`); autodetect correctly inferred STRING. Don't cast to INT64 anywhere downstream.
  - All routes are `route_type=3` (Bus). The useful service segmentation is in `route_desc`, not `route_type`. `dim_route.service_category` exposes this.
  - Stops split: 7,925 `location_type=0` (platforms) / 291 `location_type=1` (stations). `dim_stop.is_station` flags the latter.

- **Empty CSVs break BigQuery autodetect.** When a GTFS file has only a header row (e.g. `calendar_dates.txt` in this snapshot), `autodetect=True` in `LoadJobConfig` produces a table *with no columns*, and every downstream `SELECT` fails with `Unrecognized name: <col>`. Fix: `ingestion/gtfs/loader.py` now has a `GTFS_EXPLICIT_SCHEMAS` registry. Tables listed there use a hardcoded `[SchemaField(...)]` instead of autodetecting. Currently only `calendar_dates` is registered; add others as needed.

- **TJ encodes low-frequency services with extreme headway values.** `frequencies.headway_secs` is mostly in the 180–3600 range, but TJ also uses `86400` (24 hours = "one departure per day in this window"), `52700` (Bus Wisata tourist routes, ~14 hrs), and `21600`/`43200` (long-headway feeders). The `stg_gtfs__frequencies` headway range test is set to `[60, 86400]` to accept these. When building `int_frequencies_expanded`, the `GENERATE_ARRAY(start, end, headway)` call will produce just 1 row for the 24-hour-headway cases — that's the intended semantics.

- **Hours 24 and 25 appear in `fact_scheduled_stop_event.arrival_seconds_from_service_midnight`** (and in any GROUP BY on `DIV(seconds, 3600)`). This is the GTFS service-day-overflow convention working as designed: a bus that departed its origin at 23:30 and arrives at a downstream stop at 00:15 the next calendar day is preserved as 24:15 (= 87,300 seconds) because it's still part of the *previous service day's* schedule. The `gtfs_time_to_seconds` macro intentionally preserves this. **Implication for `presentation_*` tables:** decide per use case whether to (a) keep the service-day semantics, or (b) split such rows into (service_date, actual_clock_date) pairs and modulo the seconds. For dashboards showing "buses per hour of day," option (b) is usually what an analyst expects. For schedule-fidelity work, keep option (a).

---

## Key files / where things live

- `README.md` — public-facing project description
- `docs/architecture.md` — design rationale
- `docs/gcp_setup.md` — full GCP runbook
- `docs/project_state.md` — this file
- `.env` — real env values (gitignored)
- `.env.example` — template for cloners
- `ingestion/gtfs/loader.py` — GTFS pipeline; reads `GTFS_FEED_URL` or `GTFS_LOCAL_ZIP`
- `ingestion/jakarta_open_data/` — second pipeline; registry in `datasets.yml`
- `dbt_transjakarta/dbt_project.yml` — dbt config (materialization defaults, schemas)
- `dbt_transjakarta/profiles.yml` — local copy of BQ connection (gitignored); also copied to `~/.dbt/profiles.yml`
- `dbt_transjakarta/packages.yml` — dbt deps
- `dbt_transjakarta/models/staging/gtfs/` — seven `stg_gtfs__*` models + sources + schema
- `dbt_transjakarta/models/intermediate/` — three ephemeral `int_*` models (`service_calendar_unrolled`, `frequencies_expanded`, `stop_times_with_offsets`)
- `dbt_transjakarta/models/marts/core/` — four dims (`dim_date`, `dim_route`, `dim_stop`, `dim_service`) + two facts (`fact_scheduled_trip`, `fact_scheduled_stop_event`) + `_core__models.yml`
- `dbt_transjakarta/models/marts/presentation/` — empty until Phase 3 (will hold `presentation_*` denormalized wide tables)
- `dbt_transjakarta/macros/gtfs_time_to_seconds.sql` — custom time-parsing macro
- `gcp-service-account.json` — service-account key (gitignored)
- `data/raw/` — drop zone for the manually-downloaded GTFS zip

## How to pick up in a new chat session

When starting a new Cowork chat on this project, paste this as the first message:

> Continuing work on a Transjakarta analytics portfolio project. Read `docs/project_state.md` for full context — stack, naming conventions, decisions, phase status, and where we left off. Then [describe what you want to do next].

Ask the assistant to **update this file** at the end of each session before you close the chat. That way the next session always starts from a current state.
