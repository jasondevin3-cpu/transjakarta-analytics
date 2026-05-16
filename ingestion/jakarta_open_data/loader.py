"""
Loader for Jakarta open data (data.jakarta.go.id).

Reads dataset definitions from datasets.yml and loads each into BigQuery
under the BQ_DATASET_OPEN_DATA dataset. Files are also archived in GCS at
gs://{bucket}/open_data/raw/{snapshot_date}/{name}.{ext}.

Phase 1 ships a working skeleton with an empty datasets.yml registry —
populate the registry with real URLs as analytical needs emerge.

Run:
    python -m ingestion.jakarta_open_data.loader
"""

from __future__ import annotations

import io
import logging
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
import yaml
from dotenv import load_dotenv
from google.cloud import bigquery, storage

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("open_data_loader")


@dataclass(frozen=True)
class Config:
    gcp_project: str
    gcs_bucket: str
    bq_dataset: str
    snapshot_date: str

    @classmethod
    def from_env(cls) -> "Config":
        load_dotenv()
        missing = [
            k
            for k in ("GCP_PROJECT_ID", "GCS_BUCKET", "BQ_DATASET_OPEN_DATA")
            if not os.getenv(k)
        ]
        if missing:
            raise SystemExit(f"Missing required env vars: {', '.join(missing)}")
        return cls(
            gcp_project=os.environ["GCP_PROJECT_ID"],
            gcs_bucket=os.environ["GCS_BUCKET"],
            bq_dataset=os.environ["BQ_DATASET_OPEN_DATA"],
            snapshot_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        )


def load_registry() -> list[dict]:
    registry_path = Path(__file__).parent / "datasets.yml"
    with registry_path.open() as f:
        data = yaml.safe_load(f) or {}
    return data.get("datasets") or []


def download(url: str) -> bytes:
    log.info("Downloading %s", url)
    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    return resp.content


def archive_to_gcs(
    gcs: storage.Client, cfg: Config, name: str, fmt: str, blob_bytes: bytes
) -> str:
    bucket = gcs.bucket(cfg.gcs_bucket)
    path = f"open_data/raw/{cfg.snapshot_date}/{name}.{fmt}"
    bucket.blob(path).upload_from_string(blob_bytes)
    uri = f"gs://{cfg.gcs_bucket}/{path}"
    log.info("Archived %s -> %s", name, uri)
    return uri


def to_dataframe(blob_bytes: bytes, fmt: str) -> pd.DataFrame:
    buf = io.BytesIO(blob_bytes)
    if fmt == "csv":
        return pd.read_csv(buf)
    if fmt == "xlsx":
        return pd.read_excel(buf)
    raise ValueError(f"Unsupported format: {fmt}")


def load_to_bq(bq: bigquery.Client, cfg: Config, name: str, df: pd.DataFrame) -> None:
    table_ref = f"{cfg.gcp_project}.{cfg.bq_dataset}.{name}"
    job = bq.load_table_from_dataframe(
        df,
        table_ref,
        job_config=bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
    )
    job.result()
    log.info("Loaded %s rows into %s", len(df), table_ref)


def ensure_dataset(bq: bigquery.Client, cfg: Config) -> None:
    dataset_id = f"{cfg.gcp_project}.{cfg.bq_dataset}"
    try:
        bq.get_dataset(dataset_id)
    except Exception:
        log.info("Creating BigQuery dataset %s", dataset_id)
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = os.getenv("GCP_REGION", "asia-southeast2")
        bq.create_dataset(dataset, exists_ok=True)


def run() -> None:
    cfg = Config.from_env()
    registry = load_registry()
    if not registry:
        log.warning("No datasets registered in datasets.yml — nothing to do.")
        return

    gcs = storage.Client(project=cfg.gcp_project)
    bq = bigquery.Client(project=cfg.gcp_project)
    ensure_dataset(bq, cfg)

    for entry in registry:
        name, url, fmt = entry["name"], entry["url"], entry["format"]
        try:
            blob_bytes = download(url)
            archive_to_gcs(gcs, cfg, name, fmt, blob_bytes)
            df = to_dataframe(blob_bytes, fmt)
            load_to_bq(bq, cfg, name, df)
        except Exception as exc:
            log.exception("Failed to ingest %s: %s", name, exc)


if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        log.exception("Loader failed: %s", exc)
        sys.exit(1)
