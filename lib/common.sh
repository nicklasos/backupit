#!/usr/bin/env bash

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

backup_timestamp() {
  date +%Y%m%d_%H%M%S
}

# Parse YYYYMMDD_HHMMSS from a filename; print epoch seconds or empty.
filename_to_epoch() {
  local name="$1"
  local ts
  ts=$(echo "$name" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1) || true
  if [ -z "$ts" ]; then
    return 0
  fi
  local y="${ts:0:4}" m="${ts:4:2}" d="${ts:6:2}"
  local H="${ts:9:2}" M="${ts:11:2}" S="${ts:13:2}"
  if date -j -f "%Y-%m-%d %H:%M:%S" "${y}-${m}-${d} ${H}:${M}:${S}" +%s 2>/dev/null; then
    return 0
  fi
  date -d "${y}-${m}-${d} ${H}:${M}:${S}" +%s 2>/dev/null || true
}

# Strip pg_dump \restrict / \unrestrict meta-commands (CVE-2025-8714).
# These break older psql and GUI clients that treat the dump as SQL.
strip_pg_restrict() {
  local src="$1"
  local dst="$2"
  sed -E '/^\\(un)?restrict[[:space:]]+[A-Za-z0-9]+$/d' "$src" > "$dst"
}

zip_file() {
  local src="$1"
  local zip_path="$2"
  local dir base
  dir=$(dirname "$src")
  base=$(basename "$src")
  (
    cd "$dir" || exit 1
    zip -q -9 "$zip_path" "$base"
  ) || return 1
  unzip -tq "$zip_path" >/dev/null 2>&1 || return 1
}

zip_dir() {
  local src_dir="$1"
  local zip_path="$2"
  local parent name
  parent=$(dirname "$src_dir")
  name=$(basename "$src_dir")
  (
    cd "$parent" || exit 1
    zip -r -q -9 "$zip_path" "$name"
  ) || return 1
  unzip -tq "$zip_path" >/dev/null 2>&1 || return 1
}

# Delete local files matching prefix_*.zip older than RETENTION_DAYS (by filename timestamp).
prune_local() {
  local dir="$1"
  local prefix="$2"
  local retention_days="$3"
  local now cutoff epoch name
  now=$(date +%s)
  cutoff=$((now - retention_days * 86400))

  shopt -s nullglob
  for f in "$dir"/${prefix}_*.zip; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    epoch=$(filename_to_epoch "$name")
    if [ -n "$epoch" ] && [ "$epoch" -lt "$cutoff" ]; then
      log "Removing old local backup: $name"
      rm -f "$f"
    fi
  done
  shopt -u nullglob
}

# Delete remote objects older than RETENTION_DAYS (by filename timestamp).
prune_remote() {
  local retention_days="$1"
  local now cutoff epoch name
  now=$(date +%s)
  cutoff=$((now - retention_days * 86400))

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    epoch=$(filename_to_epoch "$name")
    if [ -n "$epoch" ] && [ "$epoch" -lt "$cutoff" ]; then
      log "Removing old remote backup: $name"
      storage_delete "$name"
    fi
  done < <(storage_list)
}
