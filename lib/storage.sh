#!/usr/bin/env bash

# Dispatcher: load backend from STORAGE_TYPE (gcs | local | s3).
# Callers must set STORAGE_TYPE before sourcing this file.
# Exposes: storage_upload, storage_list, storage_delete

_BACKUPIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_BACKUPIT_LIB_DIR}/common.sh"

case "${STORAGE_TYPE:-}" in
  gcs)
    # shellcheck source=gcs.sh
    source "${_BACKUPIT_LIB_DIR}/gcs.sh"
    ;;
  local|disk)
    # shellcheck source=local.sh
    source "${_BACKUPIT_LIB_DIR}/local.sh"
    ;;
  s3)
    # shellcheck source=s3.sh
    source "${_BACKUPIT_LIB_DIR}/s3.sh"
    ;;
  *)
    echo "ERROR: STORAGE_TYPE must be 'gcs', 'local', or 's3' (got: '${STORAGE_TYPE:-}')" >&2
    exit 1
    ;;
esac
