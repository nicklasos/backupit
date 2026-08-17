#!/usr/bin/env bash
# Backup images directory to a zip archive and upload to object storage (GCS by default).
# Run from crontab. Edit the config block below on the server.

set -euo pipefail

# =============================================================================
# CONFIG — edit on the server
# =============================================================================

IMAGES_DIR="/var/www/smartcity/smartcity-files"

STORAGE_TYPE="gcs" # gcs | local | s3 (s3 not implemented yet)

GCS_BUCKET="your-backup-bucket"
GCS_PREFIX="images"
# Path to a service account JSON (used for unattended cron). Leave empty if
# gcloud is already authenticated (e.g. gcloud auth application-default login).
GCS_CREDENTIALS=""

# Local disk (set STORAGE_TYPE=local):
# LOCAL_DIR="/mnt/backups"
# LOCAL_PREFIX="images"

# Future S3 (reserved — set STORAGE_TYPE=s3 when lib/s3.sh is implemented):
# S3_BUCKET=""
# S3_PREFIX="images"
# S3_REGION="eu-central-1"

RETENTION_DAYS=14
KEEP_LOCAL=1 # 1 = keep zip until retention prune; 0 = delete after successful upload

# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/storage.sh
source "${SCRIPT_DIR}/lib/storage.sh"

require_cmd zip
require_cmd unzip

if [ ! -d "$IMAGES_DIR" ]; then
  die "images directory does not exist: $IMAGES_DIR"
fi

TIMESTAMP=$(backup_timestamp)
ZIP_FILE="${SCRIPT_DIR}/images_${TIMESTAMP}.zip"

cleanup_partial() {
  if [ -f "$ZIP_FILE" ] && [ "${UPLOAD_OK:-0}" != "1" ]; then
    rm -f "$ZIP_FILE"
  fi
}
trap cleanup_partial EXIT

log "Starting images backup"
log "Source: $IMAGES_DIR"

if ! zip_dir "$IMAGES_DIR" "$ZIP_FILE"; then
  die "failed to create zip archive"
fi

SIZE=$(du -h "$ZIP_FILE" | cut -f1)
FILE_COUNT=$(unzip -l "$ZIP_FILE" 2>/dev/null | tail -1 | awk '{print $2}')
log "Created $ZIP_FILE ($SIZE, ${FILE_COUNT:-?} entries)"

storage_upload "$ZIP_FILE"
UPLOAD_OK=1
log "Upload complete"

if [ "$KEEP_LOCAL" != "1" ]; then
  rm -f "$ZIP_FILE"
  log "Removed local zip (KEEP_LOCAL=0)"
fi

prune_local "$SCRIPT_DIR" "images" "$RETENTION_DAYS"
prune_remote "$RETENTION_DAYS"

log "Images backup finished"
