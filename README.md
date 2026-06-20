# transjakarta-analytics

An end-to-end analytics project on publicly available **Transjakarta** transit data — the Bus system serving Jakarta, Indonesia.

This project stack covers the full data lifecycle: Python ingestion into Google Cloud Storage and BigQuery, dimensional modeling in dbt with a staging → intermediate → marts layered architecture, and an analysis optimized presentation tables that enable reporting dashboards and data analysis.

> **Portfolio context.** This repository is a public portfolio piece intended to demonstrate analytics-engineering, BI, and data-analyst skills end-to-end. The published [dbt docs site](#) (link added after deployment) is the primary deliverable — see the lineage graph, model descriptions, and test coverage.

---

## Key findings

Two headline reads from the modeled schedule (every query below is reproducible as a dbt analysis in [`dbt_transjakarta/analyses/`](dbt_transjakarta/analyses)).

**The busiest corridors are exactly the iconic trunk routes — a clean validation of the model.** Ranking BRT corridors by *scheduled departures per service day* puts Corridor 8 (Lebak Bulus–Pasar Baru) on top, followed by the other well-known backbones:

| Rank | Corridor | Route | Scheduled departures / day | Stops served | Avg headway |
|------|----------|-------|---------------------------:|-------------:|------------:|
| 1 | 8 | Lebak Bulus – Pasar Baru | 1,609 | 52 | 12.5 min |
| 2 | 9 | Pinang Ranti – Pluit | 1,495 | 50 | 8.8 min |
| 3 | 1 | Blok M – Kota | 1,337 | 43 | 15.1 min |
| 4 | 10 | Tanjung Priok – PGC | 1,154 | 42 | 6.2 min |
| 5 | 3 | Kalideres – Monas | 1,032 | 31 | 10.8 min |

**Transjakarta schedules a flat, all-day level of service — with no weekday/weekend distinction.** Network-wide scheduled arrivals ramp from ~71k/hour at 5am to a remarkably constant **~167k/hour plateau that holds from 7am to 9pm**, then wind down by midnight. Weekday and weekend profiles are nearly identical (9am: 168,052 vs 167,746). In other words, the *timetable* commits a steady supply across the whole operating day rather than intensifying for rush hour. That makes ridership (actual demand) the natural next data layer to overlay — the question "where does flat supply meet peaky demand?" is exactly what this model is built to answer next.

---

## Architecture

```
        ┌──────────────────────────┐
        │  GTFS feed (.zip)        │
        │  manual snapshot         │
        └────────────┬─────────────┘
                     │
                     ▼
        ┌──────────────────────────────────────────────────────────┐
        │  Python ingestion (ingestion/)                           │
        │   - Reads + unzips GTFS                                  │
        │   - Archives raw files to GCS                            │
        │   - Loads each table into BigQuery raw_gtfs.*            │
        └────────────────────────┬─────────────────────────────────┘
                                 │
                                 ▼
        ┌──────────────────────────────────────────────────────────┐
        │  BigQuery (asia-southeast2)                              │
        │   raw_gtfs.*           ── 1:1 mirror of latest feed      │
        │                                                          │
        │   staging.stg_*        ── views, cleaned + typed         │
        │   intermediate.int_*   ── ephemeral, business logic      │
        │   marts_core.dim_*, fact_*        ── conformed fact/dim  │
        │   marts_presentation.presentation_* ── analyst-facing    │
        └────────────────────────┬─────────────────────────────────┘
                                 │
                                 ▼
        ┌──────────────────────────────────────────────────────────┐
        │  dbt docs (GitHub Pages)                                 │
        │  + analyses/ folder of headline SQL queries              │
        └──────────────────────────────────────────────────────────┘
```

GCS also archives every raw snapshot (`gs://{bucket}/gtfs/raw/{snapshot_date}/feed.zip`), so any historical state can be reproduced.

> **Scope note.** An earlier plan included ingesting Jakarta open-data CSVs (e.g. ridership) to enrich the GTFS models. That was descoped: the Jakarta portals are now JavaScript single-page apps whose exports sit behind rotating token URLs, with no stable link for automated ingestion. The `ingestion/jakarta_open_data/` loader remains in the repo as a working, registry-driven skeleton. This keeps the project GTFS-only — a complete pipeline without an unstable external dependency.

---

## Repository layout

```
transjakarta-analytics/
├── README.md
├── LICENSE
├── .env.example                 # template — copy to .env, fill in real values
├── .sqlfluff                    # SQL lint config (BigQuery dialect)
├── docs/
│   └── architecture.md          # deeper architecture notes
├── ingestion/
│   ├── pyproject.toml
│   ├── gtfs/
│   │   └── loader.py            # GTFS .zip → GCS → BigQuery raw_gtfs.*
│   └── jakarta_open_data/
│       ├── datasets.yml         # registry of open-data CSVs to ingest
│       └── loader.py            # registry-driven loader → BigQuery
├── dbt_transjakarta/
│   ├── dbt_project.yml
│   ├── profiles.yml.template
│   ├── packages.yml             # dbt_utils, dbt_expectations, codegen
│   ├── models/
│   │   ├── staging/gtfs/        # stg_gtfs__*  (views)
│   │   ├── intermediate/        # int_*        (ephemeral)
│   │   └── marts/
│   │       ├── core/            # dim_*, fact_*       (tables)
│   │       └── presentation/    # presentation_*      (tables)
│   ├── macros/
│   ├── seeds/
│   ├── snapshots/
│   ├── tests/
│   └── analyses/                # headline analytical SQL (compiled, not materialized)
└── analysis/queries/            # ad-hoc exploration outside dbt
```

### Naming convention

| Prefix     | Layer          | Materialization | Purpose                                       |
|------------|----------------|-----------------|-----------------------------------------------|
| `stg_`     | staging        | view            | 1:1 with raw, cleaning + types + renames only |
| `int_`     | intermediate   | ephemeral       | reusable business logic, not exposed          |
| `dim_`     | marts (core)   | table           | conformed dimensions                          |
| `fact_`    | marts (core)   | table           | conformed facts                               |
| `presentation_` | marts (pres.) | table        | denormalized, analyst-facing wide tables      |

---

## Manual GCP setup (one-time)

This project uses BigQuery free tier (10 GB storage + 1 TB queries / month) and Cloud Storage free tier (5 GB in `us-*`; we use `asia-southeast2` so storage past the trial credit costs ~$0.02/GB/month — comfortably under $1/month at portfolio scale).

1. **Create a GCP project** at [console.cloud.google.com](https://console.cloud.google.com). Note the project ID — you'll paste it into `.env` and `profiles.yml`.
2. **Enable APIs:** BigQuery API, Cloud Storage API.
3. **Create a GCS bucket** in `asia-southeast2`. Suggested name: `{project-id}-transjakarta-raw`. Default settings are fine (no public access, soft-delete optional).
4. **Create BigQuery datasets** in `asia-southeast2`:
   - `raw_gtfs`
   - `raw_jakarta_open_data`
   - `staging`
   - `marts_core`
   - `marts_presentation`
   - `dbt_dev_jason` (or similar; personal dev schema for dbt)
5. **Create a service account** with roles: `BigQuery Data Editor`, `BigQuery Job User`, `Storage Object Admin` (scoped to the bucket above). Download the JSON key as `gcp-service-account.json` to the repo root — it's already in `.gitignore`.
6. **Copy `.env.example` to `.env`** and fill in `GCP_PROJECT_ID`, `GCS_BUCKET`, and `GTFS_FEED_URL` (find the current Transjakarta GTFS feed URL at [mobilitydatabase.org](https://mobilitydatabase.org) or the official open-data portal).
7. **Copy `dbt_transjakarta/profiles.yml.template`** to `~/.dbt/profiles.yml` and update the `project`, `keyfile`, and `dataset` values.

---

## How to run (Phase 1)

```bash
# 1. Install ingestion deps
cd ingestion
python -m venv .venv && source .venv/bin/activate
pip install -e .

# 2. Run the GTFS loader (downloads → GCS → BigQuery raw_gtfs.*)
python -m gtfs.loader

# 3. dbt setup
cd ../dbt_transjakarta
dbt deps           # installs dbt_utils, dbt_expectations, codegen
dbt debug          # confirms profiles.yml + BigQuery connection
dbt build          # runs + tests all models (staging only in Phase 1)

# 4. Preview docs locally
dbt docs generate
dbt docs serve
```

---

## Roadmap

- **Phase 1 — Foundations.** ✅ GCP setup, GTFS ingestion, dbt project skeleton, staging models with tests.
- **Phase 2 — Modeling core.** ✅ Intermediate models, `dim_*` and `fact_*` in `marts_core`, full test coverage with `dbt_utils` and `dbt_expectations`.
- **Phase 3 — Presentation marts.** ✅ Three `presentation_*` wide tables in `marts_presentation` (route summary, daily stop arrivals, hourly network density), each with a test suite. *(Jakarta open-data ingestion was descoped — see the scope note above.)*
- **Phase 4 — Storytelling.** Headline analyses in `dbt_transjakarta/analyses/` and README insights ✅; dbt docs deployed to GitHub Pages and an optional Looker Studio dashboard *(in progress)*.

---

## License

[MIT](./LICENSE)
