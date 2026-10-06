# Google Cloud Storage setup

`backupit` uploads with `gcloud storage`. Each project uses the service account JSON in its own `.env` (`GCS_CREDENTIALS`). That key is activated in a private config under `backupit/.gcloud/` and does not replace the account in `~/.config/gcloud`, so several projects on one server can use different keys.

## 1. Bucket

In [Google Cloud Console](https://console.cloud.google.com), select the project, then **Cloud Storage → Buckets → Create**.

- Name: globally unique, for example `smartcity-backups`. This exact name is `GCS_BUCKET` (no `gs://`).
- Location: a region close to the server.
- Access control: **Uniform**.
- Public access prevention: **Enforced**.

## 2. Service account key

**IAM & Admin → Service accounts → Create service account** (for example `backupit`). Skip a project-wide role.

Open that account → **Keys → Add key → Create new key → JSON**. The browser downloads the credentials file.

If **Add key** is disabled, the organization blocks service-account keys. An org admin has to allow them.

## 3. Grant access on the bucket

**Cloud Storage → your bucket → Permissions → Grant access**:

- Principal: the service account email (`backupit@PROJECT_ID.iam.gserviceaccount.com`)
- Role: **Storage Object Admin** (`roles/storage.objectAdmin`)

That role covers create, list, and delete, which upload and retention need.

## 4. Install gcloud on Ubuntu

The apt package installs `gcloud` to `/usr/bin`, which cron can see.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates gnupg curl

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

sudo apt-get update
sudo apt-get install -y google-cloud-cli
```

Check:

```bash
gcloud --version
```

Do not run `gcloud auth login` or `gcloud auth activate-service-account` for the server user. Those set one account for every project. The script reads the key from `.env`.

## 5. Configure this project

Copy the JSON into the project directory (files matching `*.json` are gitignored) and lock it down:

```bash
chmod 600 /var/www/smartcity/backupit/gcs-sa.json
```

In `backupit/.env`:

```bash
STORAGE_TYPE=gcs
GCS_BUCKET=smartcity-backups
GCS_CREDENTIALS=/var/www/smartcity/backupit/gcs-sa.json
GCS_PREFIX_DB=db
GCS_PREFIX_IMAGES=images
```

Use a different bucket name, key file, and `.env` for each project. Then run `./backup_db.sh` once. Objects land at `gs://smartcity-backups/db/` and `gs://smartcity-backups/images/`.
