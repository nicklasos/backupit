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

# Load KEY=VALUE from a .env file. Does not override variables already set
# in the environment (priority: exported env > .env > script defaults).
# Supports comments, blank lines, optional "export ", and simple quoted values.
load_dotenv() {
  local file="$1"
  local line key value

  if [ ! -f "$file" ]; then
    log "No .env at $file (using defaults / environment)"
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    line="${line#"${line%%[![:space:]]*}"}"
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    if [ -n "${!key+x}" ]; then
      continue
    fi

    if [[ "$value" =~ ^\".*\"$ ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    else
      value="${value%"${value##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
    fi

    export "${key}=${value}"
  done < "$file"

  log "Loaded env from $file"
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

# Format epoch seconds with date(1) on macOS or Linux: epoch_format EPOCH +FORMAT
epoch_format() {
  date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2"
}

# KEEP_WEEKLY_DAY (mon..sun or 1..7, empty = off) as ISO weekday 1..7.
weekly_day_number() {
  case "$(echo "${KEEP_WEEKLY_DAY:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    "") ;;
    1|mon|monday) echo 1 ;;
    2|tue|tuesday) echo 2 ;;
    3|wed|wednesday) echo 3 ;;
    4|thu|thursday) echo 4 ;;
    5|fri|friday) echo 5 ;;
    6|sat|saturday) echo 6 ;;
    7|sun|sunday) echo 7 ;;
    *) die "KEEP_WEEKLY_DAY must be mon..sun or 1..7, got '${KEEP_WEEKLY_DAY}'" ;;
  esac
}

# Read backup names on stdin, print the ones to delete.
# A backup older than RETENTION_DAYS is deleted, except the first backup of each
# KEEP_WEEKLY_DAY, which is kept for KEEP_WEEKLY_DAYS (default 365; 0 = forever).
backups_to_delete() {
  local retention_days="$1"
  local weekly_day weekly_days now cutoff weekly_cutoff name epoch ts key last_key=""
  weekly_day=$(weekly_day_number)
  weekly_days="${KEEP_WEEKLY_DAYS:-365}"
  now=$(date +%s)
  cutoff=$((now - retention_days * 86400))
  weekly_cutoff=$((now - weekly_days * 86400))

  sort | while IFS= read -r name; do
    [ -n "$name" ] || continue
    epoch=$(filename_to_epoch "$name")
    [ -n "$epoch" ] || continue
    [ "$epoch" -lt "$cutoff" ] || continue

    if [ -n "$weekly_day" ] && [ "$(epoch_format "$epoch" +%u)" = "$weekly_day" ]; then
      ts=$(echo "$name" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
      key="${name%%_[0-9]*}_${ts:0:8}"
      if [ "$key" != "$last_key" ]; then
        last_key="$key"
        if [ "$weekly_days" = "0" ] || [ "$epoch" -ge "$weekly_cutoff" ]; then
          continue
        fi
      fi
    fi

    echo "$name"
  done
}

list_local_backups() {
  local dir="$1" prefix="$2" f
  shopt -s nullglob
  for f in "$dir"/${prefix}_*.zip; do
    [ -f "$f" ] && basename "$f"
  done
  shopt -u nullglob
}

# Delete local files matching prefix_*.zip that backups_to_delete selects.
prune_local() {
  local dir="$1"
  local prefix="$2"
  local retention_days="$3"
  local name

  while IFS= read -r name; do
    log "Removing old local backup: $name"
    rm -f "${dir:?}/$name"
  done < <(list_local_backups "$dir" "$prefix" | backups_to_delete "$retention_days")
}

# Delete remote/storage objects that backups_to_delete selects.
# Implemented per-backend in lib/storage.sh as storage_prune / prune_remote.
prune_remote() {
  if ! declare -F storage_prune >/dev/null 2>&1; then
    die "storage_prune is not available (source lib/storage.sh)"
  fi
  storage_prune "$@"
}
