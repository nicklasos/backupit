#!/usr/bin/env bash

# Dispatcher: load one or more backends from STORAGE_TYPE.
# Examples: STORAGE_TYPE="gcs"  |  STORAGE_TYPE="local,gcs"  |  STORAGE_TYPE="local, gcs, s3"
# Exposes: storage_upload, storage_prune (and STORAGE_BACKENDS array)

_BACKUPIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_BACKUPIT_LIB_DIR}/common.sh"

STORAGE_BACKENDS=()

_storage_normalize_name() {
  local name="$1"
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$name" in
    disk) echo "local" ;;
    gcs|local|s3) echo "$name" ;;
    *)
      die "unknown storage backend: '$1' (use gcs, local, s3)"
      ;;
  esac
}

_storage_parse_backends() {
  local raw="${STORAGE_TYPE:-}"
  local part normalized seen
  STORAGE_BACKENDS=()

  if [ -z "$raw" ]; then
    die "STORAGE_TYPE is not set (e.g. gcs, local, or local,gcs)"
  fi

  IFS=',' read -ra _storage_parts <<< "$raw"
  for part in "${_storage_parts[@]}"; do
    [ -n "$part" ] || continue
    normalized=$(_storage_normalize_name "$part")
    seen=0
    for b in "${STORAGE_BACKENDS[@]+"${STORAGE_BACKENDS[@]}"}"; do
      if [ "$b" = "$normalized" ]; then
        seen=1
        break
      fi
    done
    if [ "$seen" -eq 0 ]; then
      STORAGE_BACKENDS+=("$normalized")
    fi
  done

  if [ "${#STORAGE_BACKENDS[@]}" -eq 0 ]; then
    die "STORAGE_TYPE is empty after parsing"
  fi
}

_storage_load_backends() {
  local b
  for b in "${STORAGE_BACKENDS[@]}"; do
    case "$b" in
      gcs)
        # shellcheck source=gcs.sh
        source "${_BACKUPIT_LIB_DIR}/gcs.sh"
        ;;
      local)
        # shellcheck source=local.sh
        source "${_BACKUPIT_LIB_DIR}/local.sh"
        ;;
      s3)
        # shellcheck source=s3.sh
        source "${_BACKUPIT_LIB_DIR}/s3.sh"
        ;;
    esac
  done
}

_storage_parse_backends
_storage_load_backends

log "Storage backends: $(IFS=,; echo "${STORAGE_BACKENDS[*]}")"

# Upload/copy the file to every configured backend (fail if any fails).
storage_upload() {
  local local_file="$1"
  local b
  [ -f "$local_file" ] || die "file not found: $local_file"
  for b in "${STORAGE_BACKENDS[@]}"; do
    "${b}_upload" "$local_file" || die "upload failed for storage: $b"
  done
}

# Prune old objects on each backend independently (by filename timestamp).
storage_prune() {
  local retention_days="$1"
  local now cutoff epoch name b
  now=$(date +%s)
  cutoff=$((now - retention_days * 86400))

  for b in "${STORAGE_BACKENDS[@]}"; do
    log "Pruning old backups on storage: $b"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      epoch=$(filename_to_epoch "$name")
      if [ -n "$epoch" ] && [ "$epoch" -lt "$cutoff" ]; then
        log "Removing old backup on $b: $name"
        "${b}_delete" "$name" || die "delete failed for $b: $name"
      fi
    done < <("${b}_list")
  done
}

# Back-compat name used by backup scripts.
prune_remote() {
  storage_prune "$@"
}
