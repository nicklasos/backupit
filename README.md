# Backups

Crontab-ready shell scripts that dump the database and images folder, zip them, upload to object storage, and prune old backups.

**Storage backends:** Google Cloud Storage (`gcs`), local disk (`local`), Amazon S3 stub (`s3`).  
You can use **several at once**: `STORAGE_TYPE="local,gcs"` (comma-separated; spaces optional).

Local staging files are created in this directory (`backupit/`), then copied/uploaded to the configured storage.

## Scripts

| Script | What it does |
|--------|----------------|
| `backup_db.sh` | dump Postgres or MySQL → zip → upload → prune |
| `backup_images.sh` | zip images dir → upload → prune |

Shared helpers:

- `lib/common.sh` — logging, `.env` loader, zip, retention by filename timestamp
- `lib/db_url.sh` — `DATABASE_URL` parsing and `DB_ENGINE` normalization
- `lib/db_postgres.sh` — `pg_dump` + strip `\restrict`
- `lib/db_mysql.sh` — `mysqldump`
- `lib/storage.sh` — parses `STORAGE_TYPE` (one or more backends) and dispatches upload/prune
- `lib/gcs.sh` — GCS via `gcloud storage`
- `lib/local.sh` — copy to a directory on local (or mounted) disk
- `lib/s3.sh` — stub (not implemented)

## Prerequisites

On the backup host:

- `bash`, `zip`, `unzip`, `sed`
- **PostgreSQL backups:** `pg_dump` (and `psql` for restore)
- **MySQL backups:** `mysqldump` (and `mysql` client for restore)
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
| `DB_ENGINE` | Required: `postgres` or `mysql` |
| `DATABASE_URL` | DB URL for `backup_db.sh` — e.g. `postgres://…` or `mysql://user:pass@host:3306/dbname` |
| `IMAGES_DIR` | Source images directory for `backup_images.sh` |
| `GCS_BUCKET` | Bucket name (GCS) |
| `GCS_CREDENTIALS` | Path to this project's service account JSON. Required for the `gcs` backend. |
| `GCS_PREFIX_DB` / `GCS_PREFIX_IMAGES` | Object prefixes (scripts map these to `GCS_PREFIX`) |
| `LOCAL_DIR` | Root directory on disk for archives (local) |
| `LOCAL_PREFIX_DB` / `LOCAL_PREFIX_IMAGES` | Subdirs under `LOCAL_DIR` |
| `RETENTION_DAYS` | Delete staging and storage backups older than this many days |
| `KEEP_LOCAL` | `0` (default) delete staging zip after successful upload; `1` keep in `backupit/` until retention |

### Database engines

`backup_db.sh` supports **PostgreSQL** and **MySQL** (one engine per run). Set the engine explicitly in `.env`:

```bash
DB_ENGINE=postgres   # or mysql
```

Aliases accepted: `postgresql`, `pg` → postgres; `mariadb` → mysql.

**PostgreSQL**

```bash
DB_ENGINE=postgres
DATABASE_URL=postgres://user:pass@localhost:5432/smartcity_prod
```

Dump uses `pg_dump -Fp --no-owner --no-acl`, then strips `\restrict` / `\unrestrict` lines.

Restore:

```bash
psql "$DATABASE_URL" -f db_20260817_020000.sql
```

**MySQL**

```bash
DB_ENGINE=mysql
DATABASE_URL=mysql://user:pass@localhost:3306/smartcity_prod
```

Dump uses `mysqldump --single-transaction --routines --triggers --events --no-tablespaces`.

Restore:

```bash
mysql -h host -P 3306 -u user -p dbname < db_20260817_020000.sql
```

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

Set `GCS_CREDENTIALS` in this project's `.env` to that project's service account JSON:

```bash
GCS_CREDENTIALS=/var/www/smartcity/backupit/gcs-sa.json
```

The script activates that key in a private gcloud config under `backupit/.gcloud/` and does not change the account in `~/.config/gcloud`. Other projects on the same server keep their own keys, including when two backups run at the same time.

Bucket, service account, and `gcloud` install steps are in [GCS_SETUP.md](GCS_SETUP.md).

`gcloud` must be on `PATH` for cron. The apt package installs it to `/usr/bin/gcloud`.

## Manual run

```bash
cd /var/www/backupit   # or your checkout path
cp -n .env.example .env          # first time
chmod +x backup_db.sh backup_images.sh

./backup_db.sh
./backup_images.sh
```

## Crontab

Use absolute paths and a sane `PATH` (cron’s default is minimal). Example: DB + images twice a day (noon and 02:00):

```cron
PATH=/usr/local/bin:/usr/bin:/bin

# Noon
0 12 * * * /var/www/backupit/backup_db.sh >> /var/www/backupit/logs/backup_db.log 2>&1
5 12 * * * /var/www/backupit/backup_images.sh >> /var/www/backupit/logs/backup_images.log 2>&1

# Middle of the night (02:00 / 02:05)
0 2 * * * /var/www/backupit/backup_db.sh >> /var/www/backupit/logs/backup_db.log 2>&1
5 2 * * * /var/www/backupit/backup_images.sh >> /var/www/backupit/logs/backup_images.log 2>&1
```

Images are offset by 5 minutes so they do not start at the same second as the DB dump. Times use the server timezone (`timedatectl` / `/etc/localtime`).

### Install / one-time setup

```bash
mkdir -p /var/www/backupit/logs
chmod +x /var/www/backupit/backup_db.sh /var/www/backupit/backup_images.sh
# ensure .env exists and is configured:
#   cd /var/www/backupit && cp -n .env.example .env && nano .env
crontab -e   # paste the cron lines above
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

# PostgreSQL
psql "postgres://user:pass@localhost:5432/dbname" -f db_20260817_020000.sql

# MySQL
# mysql -h host -P 3306 -u user -p dbname < db_20260817_020000.sql
```

Postgres dumps from `backup_db.sh` already have `\restrict` / `\unrestrict` removed so older `psql` and GUI clients work.

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
