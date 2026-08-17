#!/usr/bin/env bash

# Stub for future Amazon S3 support.
# Implement with aws cli (aws s3 cp / ls / rm) and set STORAGE_TYPE=s3.
# Reserve config: S3_BUCKET, S3_PREFIX, S3_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.

storage_upload() {
  die "S3 storage is not implemented yet (STORAGE_TYPE=s3). Use STORAGE_TYPE=gcs for now."
}

storage_list() {
  die "S3 storage is not implemented yet (STORAGE_TYPE=s3). Use STORAGE_TYPE=gcs for now."
}

storage_delete() {
  die "S3 storage is not implemented yet (STORAGE_TYPE=s3). Use STORAGE_TYPE=gcs for now."
}
