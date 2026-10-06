#!/usr/bin/env bash

# Private gcloud config for this key. Keeps the host-wide account in
# ~/.config/gcloud unchanged so other projects can use their own keys.
_gcs_config_dir() {
  local root id
  if [ -n "${SCRIPT_DIR:-}" ]; then
    root="$SCRIPT_DIR"
  else
    root="$(cd "${_BACKUPIT_LIB_DIR}/.." && pwd)"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    id=$(printf '%s' "$GCS_CREDENTIALS" | sha256sum | cut -d' ' -f1)
  else
    id=$(printf '%s' "$GCS_CREDENTIALS" | shasum -a 256 | cut -d' ' -f1)
  fi
  printf '%s\n' "${root}/.gcloud/${id}"
}

_gcs_activate_key() {
  local cfg sum stamp
  cfg=$(_gcs_config_dir)
  mkdir -p "$cfg"
  chmod 700 "$cfg"
  export CLOUDSDK_CONFIG="$cfg"
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  export GOOGLE_APPLICATION_CREDENTIALS="$GCS_CREDENTIALS"

  sum=$(cksum "$GCS_CREDENTIALS")
  stamp="${cfg}/key.cksum"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sum" ]; then
    return 0
  fi

  log "[gcs] Activating service account from $GCS_CREDENTIALS"
  gcloud auth activate-service-account --key-file="$GCS_CREDENTIALS" --quiet \
    || die "failed to activate service account from $GCS_CREDENTIALS"
  printf '%s\n' "$sum" > "$stamp"
}

gcs_setup() {
  require_cmd gcloud
  if [ -z "${GCS_BUCKET:-}" ]; then
    die "GCS_BUCKET is not set"
  fi
  if [ -z "${GCS_CREDENTIALS:-}" ]; then
    die "GCS_CREDENTIALS is not set (path to this project's service account JSON)"
  fi
  if [ ! -f "$GCS_CREDENTIALS" ]; then
    die "GCS_CREDENTIALS file not found: $GCS_CREDENTIALS"
  fi
  _gcs_activate_key
}

gcs_object_uri() {
  local name="$1"
  local prefix="${GCS_PREFIX:-}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  if [ -n "$prefix" ]; then
    echo "gs://${GCS_BUCKET}/${prefix}/${name}"
  else
    echo "gs://${GCS_BUCKET}/${name}"
  fi
}

gcs_prefix_uri() {
  local prefix="${GCS_PREFIX:-}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  if [ -n "$prefix" ]; then
    echo "gs://${GCS_BUCKET}/${prefix}/"
  else
    echo "gs://${GCS_BUCKET}/"
  fi
}

gcs_upload() {
  local local_file="$1"
  [ -f "$local_file" ] || die "file not found: $local_file"
  gcs_setup
  local name uri
  name=$(basename "$local_file")
  uri=$(gcs_object_uri "$name")
  log "[gcs] Uploading to $uri"
  gcloud storage cp "$local_file" "$uri"
}

gcs_list() {
  gcs_setup
  local uri
  uri=$(gcs_prefix_uri)
  gcloud storage ls "$uri" 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    basename "$line"
  done
}

gcs_delete() {
  local name="$1"
  gcs_setup
  local uri
  uri=$(gcs_object_uri "$name")
  log "[gcs] Removing $uri"
  gcloud storage rm "$uri"
}
