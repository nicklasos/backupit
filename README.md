# Backups

Crontab-ready shell scripts that dump the database and images folder, zip them, upload to object storage, and prune old backups.

**Storage backends:** Google Cloud Storage (`gcs`), local disk (`local`), Amazon S3 stub (`s3`).  
You can use **several at once**: `STORAGE_TYPE="local,gcs"` (comma-separated; spaces optional).

Local staging files are created in this directory (`backupit/`), then copied/uploaded to the configured storage.

## Scripts

| Script | What it does |
|--------|----------------|
| `backup_db.sh` | `pg_dump` → strip `\restrict` lines → zip → upload → prune |
| `backup_images.sh` | zip images dir → upload → prune |

Shared helpers:

- `lib/common.sh` — logging, `.env` loader, zip, retention by filename timestamp
- `lib/storage.sh` — parses `STORAGE_TYPE` (one or more backends) and dispatches upload/prune
- `lib/gcs.sh` — GCS via `gcloud storage`
- `lib/local.sh` — copy to a directory on local (or mounted) disk
- `lib/s3.sh` — stub (not implemented)

## Prerequisites

On the backup host:

- `bash`, `pg_dump`, `psql` (for restore), `zip`, `unzip`, `sed`
- For **GCS**: [Google Cloud SDK](https://cloud.google.com/sdk) (`gcloud`) with `gcloud storage` working, plus a bucket and a service account with `storage.objects.create` / `list` / `delete`
- For **local disk**: a writable directory (external HDD/SSD, NAS mount, etc.)

## Configuration (`.env`)

Both scripts share one file: `backupit/.env` (not committed).

```bash
cd /path/to/smartcity/backupit
cp .env.example .env
# edit .env on the server
```

**Priority:** already-exported environment variables → `.env` → script defaults.

So crontab can override a single value without editing the file:

```bash
STORAGE_TYPE=local /var/www/smartcity/backupit/backup_db.sh
```

| Variable | Meaning |
|----------|---------|
| `STORAGE_TYPE` | One or more backends, comma-separated: `gcs`, `local` (alias `disk`), `s3` (stub). Example: `local,gcs` |
| `DATABASE_URL` | Postgres URL for `backup_db.sh` |
| `IMAGES_DIR` | Source images directory for `backup_images.sh` |
| `GCS_BUCKET` | Bucket name (GCS) |
| `GCS_CREDENTIALS` | Path to service account JSON (exported as `GOOGLE_APPLICATION_CREDENTIALS`) |
| `GCS_PREFIX_DB` / `GCS_PREFIX_IMAGES` | Object prefixes (scripts map these to `GCS_PREFIX`) |
| `LOCAL_DIR` | Root directory on disk for archives (local) |
| `LOCAL_PREFIX_DB` / `LOCAL_PREFIX_IMAGES` | Subdirs under `LOCAL_DIR` |
| `RETENTION_DAYS` | Delete staging and storage backups older than this many days |
| `KEEP_LOCAL` | `1` keep staging zip in `backupit/` until retention; `0` delete staging after successful upload/copy |

### Multiple storages

Upload the same archive to every listed backend (order left → right). Retention runs on each backend independently.

```bash
# in .env
STORAGE_TYPE=local,gcs
# later: STORAGE_TYPE=local,gcs,s3

LOCAL_DIR=/mnt/backups
LOCAL_PREFIX_DB=db
LOCAL_PREFIX_IMAGES=images

GCS_BUCKET=your-backup-bucket
GCS_PREFIX_DB=db
GCS_PREFIX_IMAGES=images
GCS_CREDENTIALS=/var/www/smartcity/backupit/gcs-sa.json
```

If any backend fails, the script exits non-zero (after earlier backends may already have received the file).

### Local disk

```bash
STORAGE_TYPE=local
LOCAL_DIR=/mnt/backups
LOCAL_PREFIX_DB=db
LOCAL_PREFIX_IMAGES=images
```

Archives go to `$LOCAL_DIR/$LOCAL_PREFIX_*/`. Staging zips in `backupit/` are still controlled by `KEEP_LOCAL`.

### GCS auth for cron

Prefer a service account file in `.env`:

```bash
GCS_CREDENTIALS=/var/www/smartcity/backupit/gcs-sa.json
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
cd /var/www/smartcity/backupit   # or your checkout path
cp -n .env.example .env          # first time
chmod +x backup_db.sh backup_images.sh

./backup_db.sh
./backup_images.sh
```

## Crontab

Use absolute paths. Example (daily DB at 02:00, images at 03:00):

```cron
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * * /var/www/smartcity/backupit/backup_db.sh >> /var/www/smartcity/backupit/logs/backup_db.log 2>&1
0 3 * * * /var/www/smartcity/backupit/backup_images.sh >> /var/www/smartcity/backupit/logs/backup_images.log 2>&1
```

```bash
mkdir -p /var/www/smartcity/backupit/logs
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

1. Implement `s3_upload`, `s3_list`, and `s3_delete` in `lib/s3.sh` (e.g. `aws s3 cp` / `ls` / `rm`).
2. Set `S3_BUCKET`, `S3_REGION`, `S3_PREFIX_DB` / `S3_PREFIX_IMAGES` (and AWS credentials) in `.env`.
3. Add `s3` to `STORAGE_TYPE`, e.g. `STORAGE_TYPE=local,gcs,s3`.

No changes to the main backup flow are required.

## Related

Local-only backup/restore helpers (no cloud upload) still live under `smartcity-api/stuff/db_backup.sh` and `smartcity-api/stuff/images_backup.sh`.
