"""
GTFS loader for Transjakarta.

Pipeline:
  1. Obtain the GTFS .zip — either from GTFS_FEED_URL (HTTP download)
     or GTFS_LOCAL_ZIP (path to a local file). Exactly one must be set.
  2. Upload the raw zip to GCS at gs://{bucket}/gtfs/raw/{snapshot_date}/feed.zip
     (immutable archive — useful for reproducing any past run).
  3. Unzip in memory, upload each .txt as CSV to
     gs://{bucket}/gtfs/staged/{snapshot_date}/{table}.csv
  4. Load each CSV into BigQuery: {project}.{raw_dataset}.{table}
     with WRITE_TRUNCATE (the raw layer is a current-snapshot mirror;
     historical snapshots live in GCS).

Run:
    python -m ingestion.gtfs.loader

Environment variables (see .env.example):
    GCP_PROJECT_ID, GCS_BUCKET, BQ_DATASET_RAW,
    GTFS_FEED_URL or GTFS_LOCAL_ZIP,
    GOOGLE_APPLICATION_CREDENTIALS
"""

from __future__ import annotations

import io
import logging
import os
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv
from google.cloud import bigquery, storage

# GTFS reference files we expect to ingest. Files not in this list will be
# uploaded to GCS but skipped for BigQuery load (logged as INFO).
GTFS_TABLES: tuple[str, ...] = (
    "agency",
    "stops",
    "routes",
    "trips",
    "stop_times",
    "calendar",
    "calendar_dates",
    "shapes",
    "fare_attributes",
    "fare_rules",
    "frequencies",
    "transfers",
    "feed_info",
)

# Explicit schemas for tables that can be legitimately empty in a GTFS feed.
# BigQuery's autodetect can't infer columns from a header-only CSV, so without
# this the resulting table would have no columns and every downstream query
# would fail with `Unrecognized name: <col>`.
GTFS_EXPLICIT_SCHEMAS: dict[str, list[bigquery.SchemaField]] = {
    "calendar_dates": [
        bigquery.SchemaField("service_id", "STRING"),
        bigquery.SchemaField("date", "STRING"),
        bigquery.SchemaField("exception_type", "INT64"),
    ],
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("gtfs_loader")


@dataclass(frozen=True)
class Config:
    gcp_project: str
    gcs_bucket: str
    bq_dataset_raw: str
    gtfs_url: str | None
    gtfs_local_zip: str | None
    snapshot_date: str

    @classmethod
    def from_env(cls) -> "Config":
        load_dotenv()
        required = ("GCP_PROJECT_ID", "GCS_BUCKET", "BQ_DATASET_RAW")
        missing = [k for k in required if not os.getenv(k)]
        if missing:
            raise SystemExit(f"Missing required env vars: {', '.join(missing)}")

        gtfs_url = os.getenv("GTFS_FEED_URL") or None
        gtfs_local_zip = os.getenv("GTFS_LOCAL_ZIP") or None
        # Treat the placeholder URL from .env.example as "unset"
        if gtfs_url and "example.com" in gtfs_url:
            gtfs_url = None
        if not gtfs_url and not gtfs_local_zip:
            raise SystemExit(
                "Set GTFS_FEED_URL (HTTP source) or GTFS_LOCAL_ZIP (local file path)."
            )

        return cls(
            gcp_project=os.environ["GCP_PROJECT_ID"],
            gcs_bucket=os.environ["GCS_BUCKET"],
            bq_dataset_raw=os.environ["BQ_DATASET_RAW"],
            gtfs_url=gtfs_url,
            gtfs_local_zip=gtfs_local_zip,
            snapshot_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        )


def fetch_feed(cfg: Config) -> bytes:
    """Return GTFS zip bytes, either from a local file or a remote URL."""
    if cfg.gtfs_local_zip:
        path = Path(cfg.gtfs_local_zip).expanduser().resolve()
        if not path.exists():
            raise SystemExit(f"GTFS_LOCAL_ZIP set but file not found: {path}")
        log.info("Reading GTFS feed from local file %s", path)
        data = path.read_bytes()
        log.info("Read %.2f MB", len(data) / 1_048_576)
        return data

    log.info("Downloading GTFS feed from %s", cfg.gtfs_url)
    resp = requests.get(cfg.gtfs_url, timeout=120)
    resp.raise_for_status()
    log.info("Downloaded %.2f MB", len(resp.content) / 1_048_576)
    return resp.content


def upload_raw_zip(gcs: storage.Client, cfg: Config, blob_bytes: bytes) -> str:
    bucket = gcs.bucket(cfg.gcs_bucket)
    path = f"gtfs/raw/{cfg.snapshot_date}/feed.zip"
    blob = bucket.blob(path)
    blob.upload_from_string(blob_bytes, content_type="application/zip")
    uri = f"gs://{cfg.gcs_bucket}/{path}"
    log.info("Archived raw zip to %s", uri)
    return uri


def upload_staged_csv(
    gcs: storage.Client, cfg: Config, table: str, csv_bytes: bytes
) -> str:
    bucket = gcs.bucket(cfg.gcs_bucket)
    path = f"gtfs/staged/{cfg.snapshot_date}/{table}.csv"
    blob = bucket.blob(path)
    blob.upload_from_string(csv_bytes, content_type="text/csv")
    return f"gs://{cfg.gcs_bucket}/{path}"


def load_csv_to_bq(bq: bigquery.Client, cfg: Config, table: str, gcs_uri: str) -> None:
    table_ref = f"{cfg.gcp_project}.{cfg.bq_dataset_raw}.{table}"
    schema = GTFS_EXPLICIT_SCHEMAS.get(table)
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=schema is None,   # explicit schema wins over autodetect
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        allow_quoted_newlines=True,
    )
    log.info("Loading %s -> %s%s", gcs_uri, table_ref,
             " (explicit schema)" if schema else "")
    job = bq.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    job.result()
    log.info("Loaded %s rows into %s", job.output_rows, table_ref)


def ensure_dataset(bq: bigquery.Client, cfg: Config) -> None:
    dataset_id = f"{cfg.gcp_project}.{cfg.bq_dataset_raw}"
    try:
        bq.get_dataset(dataset_id)
    except Exception:
        log.info("Creating BigQuery dataset %s", dataset_id)
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = os.getenv("GCP_REGION", "asia-southeast2")
        bq.create_dataset(dataset, exists_ok=True)


def run() -> None:
    cfg = Config.from_env()
    log.info("Snapshot date: %s", cfg.snapshot_date)

    gcs = storage.Client(project=cfg.gcp_project)
    bq = bigquery.Client(project=cfg.gcp_project)
    ensure_dataset(bq, cfg)

    feed_bytes = fetch_feed(cfg)
    upload_raw_zip(gcs, cfg, feed_bytes)

    loaded, skipped = [], []
    with zipfile.ZipFile(io.BytesIO(feed_bytes)) as zf:
        members = {Path(n).stem: n for n in zf.namelist() if n.endswith(".txt")}
        for table in GTFS_TABLES:
            if table not in members:
                log.info("Table %s not present in feed; skipping", table)
                skipped.append(table)
                continue
            csv_bytes = zf.read(members[table])
            gcs_uri = upload_staged_csv(gcs, cfg, table, csv_bytes)
            load_csv_to_bq(bq, cfg, table, gcs_uri)
            loaded.append(table)

    log.info("Done. Loaded: %s. Skipped: %s.", loaded, skipped)


if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        log.exception("Loader failed: %s", exc)
        sys.exit(1)
