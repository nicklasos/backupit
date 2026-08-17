#!/usr/bin/env bash

gcs_setup() {
  require_cmd gcloud
  if [ -z "${GCS_BUCKET:-}" ]; then
    die "GCS_BUCKET is not set"
  fi
  if [ -n "${GCS_CREDENTIALS:-}" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$GCS_CREDENTIALS"
  fi
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

# Upload local file; object name is the basename.
storage_upload() {
  local local_file="$1"
  [ -f "$local_file" ] || die "file not found: $local_file"
  gcs_setup
  local name uri
  name=$(basename "$local_file")
  uri=$(gcs_object_uri "$name")
  log "Uploading to $uri"
  gcloud storage cp "$local_file" "$uri"
}

# List object basenames under GCS_PREFIX.
storage_list() {
  gcs_setup
  local uri
  uri=$(gcs_prefix_uri)
  gcloud storage ls "$uri" 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    basename "$line"
  done
}

storage_delete() {
  local name="$1"
  gcs_setup
  local uri
  uri=$(gcs_object_uri "$name")
  gcloud storage rm "$uri"
}
