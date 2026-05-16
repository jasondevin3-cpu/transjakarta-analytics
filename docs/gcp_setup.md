# GCP setup — step by step

A one-time runbook for setting up the Google Cloud resources this project needs. Every step lists both the **Console (UI) path** and the **`gcloud` CLI equivalent** so you can use whichever you prefer.

> **Cost expectations.** This setup stays inside Google's free tier for BigQuery (10 GB storage, 1 TB query/month) and incurs ~$0.01–0.05/month for Cloud Storage in `asia-southeast2`. We add a $5 budget alert in step 9 so there are no surprises.

---

## 0. Prerequisites

- A Google account (gmail.com or Google Workspace).
- A credit/debit card for billing verification. Google will not charge you unless you exceed the free tier or explicitly upgrade — but the card is required to create a billing account.
- (Optional) The `gcloud` CLI installed locally. On macOS: `brew install --cask google-cloud-sdk`. On Linux/Windows: [install guide](https://cloud.google.com/sdk/docs/install).

If you install `gcloud`, run once:

```bash
gcloud auth login
gcloud auth application-default login
```

---

## 1. Create a GCP project

The project is the top-level container for everything — datasets, buckets, service accounts, billing.

**Console path:**
1. Go to [console.cloud.google.com](https://console.cloud.google.com).
2. Top bar → click the project selector dropdown → **New Project**.
3. **Project name:** `transjakarta-analytics` (or anything descriptive).
4. **Project ID:** auto-generated, e.g. `transjakarta-analytics-471092`. You can edit it but it must be globally unique. Note this ID — you'll paste it into `.env` and `profiles.yml`.
5. **Location:** leave as "No organization".
6. Click **Create**. Wait ~30 seconds for it to provision, then switch to the new project from the dropdown.

**gcloud path:**

```bash
gcloud projects create transjakarta-analytics-$(date +%s) \
    --name="Transjakarta Analytics"
gcloud config set project transjakarta-analytics-XXXXXX   # use the ID printed above
```

---

## 2. Link a billing account

Free-tier services still require a billing account on the project (so Google can verify your identity). You won't be charged unless you exceed the free tier.

**Console path:**
1. Left nav → **Billing**.
2. If you've never used GCP, click **Create account** → fill in your country, name, address, payment method. Google often gives new accounts $300 free credit valid for 90 days.
3. Once the billing account exists, link it to your project: **Billing → Link a billing account → select the account → Set account**.

**gcloud path** (requires the billing account to already exist):

```bash
gcloud beta billing accounts list
gcloud beta billing projects link YOUR_PROJECT_ID \
    --billing-account=BILLING_ACCOUNT_ID
```

---

## 3. Enable the APIs

BigQuery and Cloud Storage APIs need to be turned on per-project.

**Console path:**
1. Left nav → **APIs & Services → Library**.
2. Search **BigQuery API** → click → **Enable**.
3. Back to Library, search **Cloud Storage API** → click → **Enable**.
4. (Optional but useful) also enable **IAM API** and **Cloud Resource Manager API** — they're needed for some service-account management.

**gcloud path:**

```bash
gcloud services enable \
    bigquery.googleapis.com \
    storage.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com
```

Verify:

```bash
gcloud services list --enabled --filter="config.name:(bigquery storage)"
```

---

## 4. Create the GCS bucket

This is the immutable archive for every raw GTFS download. Naming convention: `{project-id}-transjakarta-raw`.

**Console path:**
1. Left nav → **Cloud Storage → Buckets → Create**.
2. **Name:** `your-project-id-transjakarta-raw` (must be globally unique — adding your project ID guarantees that).
3. **Location type:** Region. **Location:** `asia-southeast2 (Jakarta)`.
4. **Default storage class:** Standard.
5. **Access control:** Uniform.
6. **Public access prevention:** **Enforced** (very important — keeps the bucket private).
7. Leave soft delete + versioning at defaults.
8. **Create**.

**gcloud path:**

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=${PROJECT_ID}-transjakarta-raw

gcloud storage buckets create gs://${BUCKET} \
    --project=${PROJECT_ID} \
    --location=asia-southeast2 \
    --default-storage-class=standard \
    --uniform-bucket-level-access \
    --public-access-prevention
```

---

## 5. Create the BigQuery datasets

Six datasets, all in `asia-southeast2`. The first four are populated by the pipeline; the last two are used by dbt for the marts layer.

| Dataset                    | Populated by             | Contents                          |
|----------------------------|--------------------------|-----------------------------------|
| `raw_gtfs`                 | `ingestion/gtfs/`        | Latest GTFS snapshot, mirrored 1:1 |
| `raw_jakarta_open_data`    | `ingestion/jakarta_open_data/` | Open-data CSVs/Excels       |
| `staging`                  | dbt                      | `stg_*` views                     |
| `marts_core`               | dbt                      | `dim_*`, `fact_*` tables          |
| `marts_presentation`       | dbt                      | `report_*` tables                 |
| `dbt_dev_jason`            | dbt (your personal dev)  | Your own dev runs                 |

**Console path** (for each dataset):
1. Left nav → **BigQuery → Studio**.
2. Left panel → click the three dots next to your project → **Create dataset**.
3. **Dataset ID:** as above.
4. **Location type:** Region. **Location:** `asia-southeast2`.
5. Leave default table expiration empty.
6. **Create dataset**.
7. Repeat for the other five.

**gcloud / bq CLI path** (much faster — paste this whole block):

```bash
PROJECT_ID=$(gcloud config get-value project)
for ds in raw_gtfs raw_jakarta_open_data staging marts_core marts_presentation dbt_dev_jason; do
    bq --location=asia-southeast2 mk --dataset \
        --description="Transjakarta analytics: ${ds}" \
        ${PROJECT_ID}:${ds}
done
```

> **Note:** `staging`, `marts_core`, `marts_presentation` are also automatically created by dbt on first run if they don't exist, but pre-creating them lets us control the location.

---

## 6. Create a service account

The ingestion scripts and dbt both authenticate as a service account (not as you personally) — this is the right pattern for anything that will eventually run in CI.

**Console path:**
1. Left nav → **IAM & Admin → Service Accounts → Create service account**.
2. **Service account name:** `transjakarta-dbt`.
3. **Service account ID:** auto-generated (e.g. `transjakarta-dbt`).
4. **Description:** "Service account for dbt + Python ingestion".
5. Click **Create and continue**.
6. **Skip** the "Grant access" step here — we'll do it more cleanly below. Click **Done**.

**gcloud path:**

```bash
PROJECT_ID=$(gcloud config get-value project)
gcloud iam service-accounts create transjakarta-dbt \
    --display-name="Transjakarta dbt + ingestion" \
    --description="Used by Python ingestion and dbt to read/write BigQuery and GCS"
```

The service account's email will be `transjakarta-dbt@${PROJECT_ID}.iam.gserviceaccount.com`.

---

## 7. Grant IAM roles to the service account

Principle of least privilege: only what's needed.

| Role                          | Why                                                  |
|-------------------------------|------------------------------------------------------|
| `roles/bigquery.dataEditor`   | Create/read/write tables in all datasets             |
| `roles/bigquery.jobUser`      | Run BigQuery queries and load jobs                   |
| `roles/storage.objectAdmin`   | Read/write/delete objects in the bucket only         |

**Console path** (BigQuery roles — project-level):
1. Left nav → **IAM & Admin → IAM → Grant access**.
2. **New principals:** paste `transjakarta-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com`.
3. **Assign roles:** add **BigQuery Data Editor** and **BigQuery Job User**.
4. **Save**.

**Console path** (Storage role — bucket-scoped, more secure than project-wide):
1. Left nav → **Cloud Storage → Buckets** → click your bucket.
2. **Permissions** tab → **Grant access**.
3. **New principals:** the service-account email.
4. **Assign roles:** **Storage Object Admin**.
5. **Save**.

**gcloud path:**

```bash
PROJECT_ID=$(gcloud config get-value project)
SA="transjakarta-dbt@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET="${PROJECT_ID}-transjakarta-raw"

# Project-level BigQuery roles
for role in roles/bigquery.dataEditor roles/bigquery.jobUser; do
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA}" \
        --role="${role}"
done

# Bucket-scoped Storage role
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \
    --member="serviceAccount:${SA}" \
    --role="roles/storage.objectAdmin"
```

---

## 8. Download the service-account key

The Python scripts and dbt read this JSON file to authenticate.

**Console path:**
1. **IAM & Admin → Service Accounts** → click `transjakarta-dbt`.
2. **Keys** tab → **Add key → Create new key → JSON → Create**.
3. A JSON file downloads automatically. **Move it to the repo root and rename it to `gcp-service-account.json`.**

**gcloud path:**

```bash
PROJECT_ID=$(gcloud config get-value project)
SA="transjakarta-dbt@${PROJECT_ID}.iam.gserviceaccount.com"

# Run from the repo root so the file lands in the right place.
gcloud iam service-accounts keys create gcp-service-account.json \
    --iam-account=${SA}
```

> **Security:** `gcp-service-account.json` is already listed in `.gitignore` — never commit it. If it ever leaks, immediately rotate by creating a new key and deleting the old one from the Keys tab.

---

## 9. Set a $5 budget alert (cost safety)

Belt-and-suspenders so a surprise bill is impossible.

**Console path:**
1. Left nav → **Billing → Budgets & alerts → Create budget**.
2. **Name:** `transjakarta-analytics-monthly`.
3. **Projects:** select your project. **Services:** All services.
4. **Time range:** Monthly.
5. **Budget type:** Specified amount. **Target amount:** $5.
6. **Threshold rules:** 50%, 90%, 100% (defaults are fine).
7. **Manage notifications → Email alerts to billing admins:** checked.
8. **Finish**.

You'll now get an email if monthly spend crosses $2.50, $4.50, or $5 — which would be your cue to investigate.

---

## 10. Wire the values into the repo

You now have the four pieces of info this repo needs. Update `.env` (copy from `.env.example` first):

```bash
cp .env.example .env
```

Edit `.env`:

```
GCP_PROJECT_ID=transjakarta-analytics-XXXXXX    # from step 1
GCP_REGION=asia-southeast2
GCS_BUCKET=transjakarta-analytics-XXXXXX-transjakarta-raw   # from step 4
GOOGLE_APPLICATION_CREDENTIALS=./gcp-service-account.json   # from step 8
BQ_DATASET_RAW=raw_gtfs
BQ_DATASET_OPEN_DATA=raw_jakarta_open_data
BQ_DATASET_STAGING=staging
BQ_DATASET_MARTS=marts_core
GTFS_FEED_URL=...                                # set in the next phase
```

Edit `dbt_transjakarta/profiles.yml.template`, copy to `~/.dbt/profiles.yml`:

```bash
mkdir -p ~/.dbt
cp dbt_transjakarta/profiles.yml.template ~/.dbt/profiles.yml
```

Open `~/.dbt/profiles.yml` and replace:
- `your-gcp-project-id` → your real project ID (both `dev` and `prod` blocks)
- `/absolute/path/to/gcp-service-account.json` → the full absolute path to the JSON key (e.g. `/Users/jasondevin/Documents/transjakarta_analysis/gcp-service-account.json`)
- For the `dev` block, change `dbt_dev_jason` to whatever personal dev dataset you created in step 5.

---

## 11. Verify everything

```bash
# Confirm gcloud sees the right project
gcloud config get-value project

# Confirm the bucket exists and is yours
gcloud storage ls gs://$(gcloud config get-value project)-transjakarta-raw

# Confirm all six datasets exist
bq ls --location=asia-southeast2

# Confirm the service-account key works
GOOGLE_APPLICATION_CREDENTIALS=./gcp-service-account.json \
    python -c "from google.cloud import bigquery; \
               print([d.dataset_id for d in bigquery.Client().list_datasets()])"

# Confirm dbt can connect
cd dbt_transjakarta && dbt debug
```

If all four succeed, you're done with GCP setup. The next step is finding the GTFS feed URL and running the ingestion loader.

---

## Troubleshooting

**"Billing is not enabled on this project"** when creating a dataset → revisit step 2; the billing-account link is required.

**"Permission denied" when running the loader** → the service account is missing a role, or `GOOGLE_APPLICATION_CREDENTIALS` doesn't point to the right JSON. Verify with:
```bash
gcloud auth activate-service-account --key-file=gcp-service-account.json
gcloud auth list
```

**`dbt debug` fails with "404 Not found: Dataset"** → the dataset you named in `profiles.yml` doesn't exist or is in the wrong region. Recreate it with `bq --location=asia-southeast2 mk --dataset PROJECT:DATASET`.

**`bq` or `gcloud` not found** → install the Google Cloud SDK (see step 0) and run `gcloud init`.
