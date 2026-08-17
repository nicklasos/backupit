# Backups

Crontab-ready shell scripts that dump the database and images folder, zip them, upload to object storage, and prune old backups.

**Storage backends:** Google Cloud Storage (`gcs`), local disk (`local`), Amazon S3 stub (`s3`).

Local staging files are created in this directory (`backupit/`), then copied/uploaded to the configured storage.

## Scripts

| Script | What it does |
|--------|----------------|
| `backup_db.sh` | `pg_dump` → strip `\restrict` lines → zip → upload → prune |
| `backup_images.sh` | zip images dir → upload → prune |

Shared helpers:

- `lib/common.sh` — logging, zip, retention by filename timestamp
- `lib/storage.sh` — picks backend from `STORAGE_TYPE`
- `lib/gcs.sh` — GCS via `gcloud storage`
- `lib/local.sh` — copy to a directory on local (or mounted) disk
- `lib/s3.sh` — stub (not implemented)

## Prerequisites

On the backup host:

- `bash`, `pg_dump`, `psql` (for restore), `zip`, `unzip`, `sed`
- For **GCS**: [Google Cloud SDK](https://cloud.google.com/sdk) (`gcloud`) with `gcloud storage` working, plus a bucket and a service account with `storage.objects.create` / `list` / `delete`
- For **local disk**: a writable directory (external HDD/SSD, NAS mount, etc.)

## Configuration

Edit the **CONFIG** block at the top of each script on the server (do not commit secrets).

Shared variables:

| Variable | Meaning |
|----------|---------|
| `STORAGE_TYPE` | `gcs`, `local` (alias: `disk`), or `s3` (stub) |
| `GCS_BUCKET` | Bucket name (GCS) |
| `GCS_PREFIX` | Object prefix (`db` / `images`) |
| `GCS_CREDENTIALS` | Path to service account JSON (exported as `GOOGLE_APPLICATION_CREDENTIALS`) |
| `LOCAL_DIR` | Root directory on disk for archives (local) |
| `LOCAL_PREFIX` | Subdirectory under `LOCAL_DIR` (`db` / `images`) |
| `RETENTION_DAYS` | Delete staging and storage backups older than this many days |
| `KEEP_LOCAL` | `1` keep staging zip in `backupit/` until retention; `0` delete staging after successful upload/copy |

Script-specific:

- `backup_db.sh`: `DATABASE_URL` — e.g. `postgres://user:pass@localhost:5432/dbname`
- `backup_images.sh`: `IMAGES_DIR` — e.g. `/var/www/project/files`

### Local disk

Point `STORAGE_TYPE` at a path on the machine (or a mounted USB/NAS volume):

```bash
STORAGE_TYPE="local"
LOCAL_DIR="/var/www/project/backups"   # or /var/www/project/backups
LOCAL_PREFIX="db"          # → /var/www/project/backups/db/
```

Archives are copied to `$LOCAL_DIR/$LOCAL_PREFIX/`. Retention deletes old files there via `storage_delete`. Staging zips in `backupit/` are still controlled by `KEEP_LOCAL`.

### GCS auth for cron

Cron has a minimal environment. Prefer a service account file:

```bash
GCS_CREDENTIALS="/var/www/project/backupit/gcs-sa.json"
```

Or authenticate once as the cron user:

```bash
gcloud auth application-default login
# or
gcloud auth activate-service-account --key-file=/path/to/sa.json
```

Ensure `gcloud` is on `PATH` for cron (use absolute path or set `PATH` in crontab).

## Manual run

```bash
cd /var/www/project/backupit   # or your checkout path
chmod +x backup_db.sh backup_images.sh

# After editing CONFIG on the server:
./backup_db.sh
./backup_images.sh
```

## Crontab

Use absolute paths. Example (daily DB at 02:00, images at 03:00):

```cron
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * * /var/www/project/backupit/backup_db.sh >> /var/www/project/backupit/logs/backup_db.log 2>&1
0 3 * * * /var/www/project/backupit/backup_images.sh >> /var/www/project/backupit/logs/backup_images.log 2>&1
```

```bash
mkdir -p /var/www/project/backupit/logs
```

## Object naming

- DB: `db_YYYYMMDD_HHMMSS.sql.zip`
- Images: `images_YYYYMMDD_HHMMSS.zip`

Stored under:

- GCS: `gs://$GCS_BUCKET/$GCS_PREFIX/`
- Local: `$LOCAL_DIR/$LOCAL_PREFIX/`

Retention uses the `YYYYMMDD_HHMMSS` in the filename (not mtime), so the same logic works for GCS, local disk, and a future S3 backend.

## Restore

### Database

```bash
# From GCS
gcloud storage cp gs://YOUR_BUCKET/db/db_20260817_020000.sql.zip .

# Or from local disk
cp /mnt/backups/db/db_20260817_020000.sql.zip .

unzip db_20260817_020000.sql.zip
# produces db_20260817_020000.sql

psql "postgres://user:pass@localhost:5432/dbname" -f db_20260817_020000.sql
```

New dumps from `backup_db.sh` already have `\restrict` / `\unrestrict` removed so older `psql` and GUI clients work.

### Images

```bash
# From GCS
gcloud storage cp gs://YOUR_BUCKET/images/images_20260817_030000.zip .

# Or from local disk
cp /mnt/backups/images/images_20260817_030000.zip .

unzip images_20260817_030000.zip -d /tmp/images-restore
# copy contents into IMAGES_DIR (e.g. /var/www/project/files)
```

## `\restrict` in older dumps

Recent `pg_dump` (15.14+, including 15.17) wraps plain dumps with psql meta-commands:

```text
\restrict <random-token>
...
\unrestrict <random-token>
```

These are **not SQL**. They are a security feature (CVE-2025-8714). There is no official flag to omit them; `--restrict-key` only sets the token.

If an old dump fails with `syntax error at or near "\"` near `\restrict`, strip the lines:

```bash
sed -E '/^\\(un)?restrict[[:space:]]+[A-Za-z0-9]+$/d' dump.sql > dump.clean.sql
psql "$DATABASE_URL" -f dump.clean.sql
```

Or restore with a matching modern `psql` that understands `\restrict`.

`backup_db.sh` runs this filter automatically before zipping.

## Adding Amazon S3 later

1. Implement `storage_upload`, `storage_list`, and `storage_delete` in `lib/s3.sh` (e.g. `aws s3 cp` / `ls` / `rm`).
2. Uncomment / set `S3_BUCKET`, `S3_PREFIX`, `S3_REGION` (and AWS credentials) in the CONFIG blocks.
3. Set `STORAGE_TYPE="s3"` in each script.

No changes to the main backup flow are required.

## Related

Local-only backup/restore helpers (no cloud upload) still live under `project/stuff/db_backup.sh` and `project/stuff/images_backup.sh`.
# backupit
