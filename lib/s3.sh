#!/usr/bin/env bash

# Stub for future Amazon S3 support.
# Implement with aws cli (aws s3 cp / ls / rm) and include s3 in STORAGE_TYPE.
# Reserve config: S3_BUCKET, S3_PREFIX, S3_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.

s3_upload() {
  die "S3 storage is not implemented yet. Remove 's3' from STORAGE_TYPE or implement lib/s3.sh."
}

s3_list() {
  die "S3 storage is not implemented yet. Remove 's3' from STORAGE_TYPE or implement lib/s3.sh."
}

s3_delete() {
  die "S3 storage is not implemented yet. Remove 's3' from STORAGE_TYPE or implement lib/s3.sh."
}
