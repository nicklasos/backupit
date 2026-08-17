#!/usr/bin/env bash
# Backup PostgreSQL to a zip archive and upload to object storage (GCS by default).
# Run from crontab. Edit the config block below on the server.

set -euo pipefail

# =============================================================================
# CONFIG — edit on the server
# =============================================================================

DATABASE_URL="postgres://root:pass@localhost:5432/smartcity_prod"

STORAGE_TYPE="gcs" # gcs | local | s3 (s3 not implemented yet)

GCS_BUCKET="your-backup-bucket"
GCS_PREFIX="db"
# Path to a service account JSON (used for unattended cron). Leave empty if
# gcloud is already authenticated (e.g. gcloud auth application-default login).
GCS_CREDENTIALS=""

# Local disk (set STORAGE_TYPE=local):
# LOCAL_DIR="/mnt/backups"
# LOCAL_PREFIX="db"

# Future S3 (reserved — set STORAGE_TYPE=s3 when lib/s3.sh is implemented):
# S3_BUCKET=""
# S3_PREFIX="db"
# S3_REGION="eu-central-1"

RETENTION_DAYS=14
KEEP_LOCAL=1 # 1 = keep zip until retention prune; 0 = delete after successful upload

# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/storage.sh
source "${SCRIPT_DIR}/lib/storage.sh"

require_cmd pg_dump
require_cmd zip
require_cmd unzip
require_cmd sed

TIMESTAMP=$(backup_timestamp)
SQL_RAW="${SCRIPT_DIR}/db_${TIMESTAMP}.raw.sql"
SQL_FILE="${SCRIPT_DIR}/db_${TIMESTAMP}.sql"
ZIP_FILE="${SCRIPT_DIR}/db_${TIMESTAMP}.sql.zip"

cleanup_partial() {
  rm -f "$SQL_RAW" "$SQL_FILE"
  if [ -f "$ZIP_FILE" ] && [ "${UPLOAD_OK:-0}" != "1" ]; then
    rm -f "$ZIP_FILE"
  fi
}
trap cleanup_partial EXIT

log "Starting DB backup"
log "Database URL host: $(echo "$DATABASE_URL" | sed -E 's|postgres(ql)?://[^@]*@([^/]+)/.*|\2|')"

if ! pg_dump -Fp --no-owner --no-acl -f "$SQL_RAW" "$DATABASE_URL"; then
  die "pg_dump failed"
fi

if [ ! -s "$SQL_RAW" ]; then
  die "dump file is empty or missing"
fi

strip_pg_restrict "$SQL_RAW" "$SQL_FILE"
rm -f "$SQL_RAW"

if ! zip_file "$SQL_FILE" "$ZIP_FILE"; then
  die "failed to create zip archive"
fi
rm -f "$SQL_FILE"

SIZE=$(du -h "$ZIP_FILE" | cut -f1)
log "Created $ZIP_FILE ($SIZE)"

storage_upload "$ZIP_FILE"
UPLOAD_OK=1
log "Upload complete"

if [ "$KEEP_LOCAL" != "1" ]; then
  rm -f "$ZIP_FILE"
  log "Removed local zip (KEEP_LOCAL=0)"
fi

prune_local "$SCRIPT_DIR" "db" "$RETENTION_DAYS"
prune_remote "$RETENTION_DAYS"

log "DB backup finished"
