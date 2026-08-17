#!/usr/bin/env bash
# Backup images directory to a zip archive and upload to configured storage(s).
# Config: copy .env.example → .env (or export vars). See README.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_dotenv "${SCRIPT_DIR}/.env"

# Defaults (only applied when unset after env / .env)
: "${IMAGES_DIR:=/var/www/smartcity/smartcity-files}"
: "${STORAGE_TYPE:=gcs}"
: "${GCS_BUCKET:=your-backup-bucket}"
: "${GCS_CREDENTIALS:=}"
: "${GCS_PREFIX:=${GCS_PREFIX_IMAGES:-images}}"
: "${LOCAL_DIR:=}"
: "${LOCAL_PREFIX:=${LOCAL_PREFIX_IMAGES:-images}}"
: "${S3_BUCKET:=}"
: "${S3_REGION:=}"
: "${S3_PREFIX:=${S3_PREFIX_IMAGES:-images}}"
: "${RETENTION_DAYS:=14}"
: "${KEEP_LOCAL:=1}"

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
