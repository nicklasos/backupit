#!/usr/bin/env bash

# Local hard-disk storage. Copies backups to LOCAL_DIR[/LOCAL_PREFIX].

local_setup() {
  if [ -z "${LOCAL_DIR:-}" ]; then
    die "LOCAL_DIR is not set"
  fi
  mkdir -p "$(local_dest_dir)"
}

local_dest_dir() {
  local prefix="${LOCAL_PREFIX:-}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  if [ -n "$prefix" ]; then
    echo "${LOCAL_DIR%/}/${prefix}"
  else
    echo "${LOCAL_DIR%/}"
  fi
}

local_object_path() {
  local name="$1"
  echo "$(local_dest_dir)/${name}"
}

local_upload() {
  local local_file="$1"
  [ -f "$local_file" ] || die "file not found: $local_file"
  local_setup
  local name dest src_real dest_real
  name=$(basename "$local_file")
  dest=$(local_object_path "$name")

  src_real=$(cd "$(dirname "$local_file")" && pwd)/$(basename "$local_file")
  dest_real="$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"

  if [ "$src_real" = "$dest_real" ]; then
    log "[local] Already at destination: $dest"
    return 0
  fi

  log "[local] Copying to $dest"
  cp -f "$local_file" "$dest"
}

local_list() {
  local_setup
  local dir
  dir=$(local_dest_dir)
  shopt -s nullglob
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    basename "$f"
  done
  shopt -u nullglob
}

local_delete() {
  local name="$1"
  local_setup
  local path
  path=$(local_object_path "$name")
  if [ -f "$path" ]; then
    log "[local] Removing $path"
    rm -f "$path"
  fi
}
