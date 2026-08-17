#!/usr/bin/env bash

# PostgreSQL dump via pg_dump. Writes a clean .sql file to $1.

dump_postgres() {
  local out_sql="$1"
  local raw_sql="${out_sql}.raw"

  require_cmd pg_dump
  require_cmd sed

  if ! pg_dump -Fp --no-owner --no-acl -f "$raw_sql" "$DATABASE_URL"; then
    rm -f "$raw_sql"
    die "pg_dump failed"
  fi

  if [ ! -s "$raw_sql" ]; then
    rm -f "$raw_sql"
    die "dump file is empty or missing"
  fi

  strip_pg_restrict "$raw_sql" "$out_sql"
  rm -f "$raw_sql"

  if [ ! -s "$out_sql" ]; then
    die "cleaned dump file is empty or missing"
  fi
}
