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
| `report_`  | marts.pres.    | table           | denormalized analyst-facing wide tables     |

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

### Phase 2 — Modeling core (ready to start)

Build `int_*` models (e.g. `int_trip_with_route`, `int_service_calendar_unrolled`), then `dim_stop`, `dim_route`, `dim_date`, `dim_service`, `fact_scheduled_trip`, `fact_scheduled_stop_event`. Aggressive test coverage.

**Key modeling note from the live data:** TJ's feed uses `frequencies.txt` heavily (772 rows). Many trips in `trips.txt` are not literal scheduled departures — they're trip *patterns* paired with a frequency entry that says "this pattern runs every N seconds between HH:MM and HH:MM." `fact_scheduled_trip` will need to **expand** these into individual scheduled departures (one row per realized departure time) before downstream analyses can compute things like daily trip counts or headway distributions correctly. Plain `trips.txt` row counts will undercount actual service by orders of magnitude.

**Other things to address in this phase:**
- The three "unused configuration paths" warnings (`models.transjakarta_analytics.marts.core`, `marts.presentation`, `intermediate`) will resolve themselves once Phase 2/3 models exist in those folders.

### Phase 3 — Presentation + open data (not started)

Populate `ingestion/jakarta_open_data/datasets.yml` registry, build `report_*` marts, wire up GitHub Actions CI + scheduled ingest, deploy dbt docs to GitHub Pages.

### Phase 4 — Storytelling (not started)

Looker Studio dashboard, `dbt/analyses/` SQL, README polish with screenshots, LinkedIn post.

---

## Gotchas & lessons learned

- **dbt doesn't read `.env` automatically.** `python-dotenv` is a Python library; dbt only reads OS-level environment variables. Before running `dbt build`/`run`/`test` in a fresh terminal, run `set -a; source ../.env; set +a` from inside `dbt_transjakarta/` so `GCP_PROJECT_ID` (and any other config vars in `.env`) are exported into the shell. Without this, `_gtfs__sources.yml`'s `env_var('GCP_PROJECT_ID', 'your-gcp-project-id')` falls back to the placeholder and every test / model errors with `Access Denied: Table your-gcp-project-id:raw_gtfs.*`.

- **No `requirements.txt` exists yet.** The `.venv` was set up ad-hoc; first run after a fresh clone failed with `ModuleNotFoundError: No module named 'dotenv'`. Phase-2 cleanup: pin actual installed versions into a `requirements.txt` (or `pyproject.toml`) so the next person can `pip install -r requirements.txt` and have everything work. Current confirmed-needed packages: `requests`, `python-dotenv`, `google-cloud-bigquery>=3.0`, `google-cloud-storage>=2.0`, `pandas`, `dbt-bigquery` (pulls in `dbt-core`), `sqlfluff`.

- **Cosmetic dbt deprecation warnings (still passing tests; address opportunistically):**
  - `PropertyMovedToConfigDeprecation` — `freshness:` under sources should be nested under `config:` in newer dbt versions.
  - `MissingArgumentsPropertyInGenericTestDeprecation` (9 occurrences) — top-level arguments to generic tests (`dbt_expectations.expect_column_values_to_be_between`, `relationships`) should be nested under an `arguments:` key.

- **TJ source schema observations worth knowing before Phase 2:**
  - Only 7 service patterns in `calendar.txt` (`HK` = Hari Kerja/weekday, `HL` = Hari Libur/weekend, +5 more — likely Ramadan / special schedules; verify).
  - `calendar_dates.txt` is empty in this snapshot — no holiday exceptions defined. `dim_service` can ignore exception logic for now but should be designed to absorb them if a future feed adds them.
  - `route_id`s mix numeric (`"9"`) and alphanumeric (`"BW2"`, `"9-P23"`); autodetect correctly inferred STRING. Don't cast to INT64 anywhere downstream.

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
- `dbt_transjakarta/models/staging/gtfs/` — five `stg_gtfs__*` models + sources + schema
- `dbt_transjakarta/macros/gtfs_time_to_seconds.sql` — custom time-parsing macro
- `gcp-service-account.json` — service-account key (gitignored)
- `data/raw/` — drop zone for the manually-downloaded GTFS zip

## How to pick up in a new chat session

When starting a new Cowork chat on this project, paste this as the first message:

> Continuing work on a Transjakarta analytics portfolio project. Read `docs/project_state.md` for full context — stack, naming conventions, decisions, phase status, and where we left off. Then [describe what you want to do next].

Ask the assistant to **update this file** at the end of each session before you close the chat. That way the next session always starts from a current state.
