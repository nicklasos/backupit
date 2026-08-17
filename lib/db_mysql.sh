#!/usr/bin/env bash

# MySQL dump via mysqldump. Writes a .sql file to $1.
# Expects DATABASE_URL like: mysql://user:pass@host:3306/dbname

dump_mysql() {
  local out_sql="$1"

  require_cmd mysqldump
  parse_database_url "$DATABASE_URL"

  local port="${DB_PORT:-3306}"
  export MYSQL_PWD="$DB_PASS"

  if ! mysqldump \
    -h "$DB_HOST" \
    -P "$port" \
    -u "$DB_USER" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --no-tablespaces \
    "$DB_NAME" > "$out_sql"; then
    unset MYSQL_PWD
    rm -f "$out_sql"
    die "mysqldump failed"
  fi

  unset MYSQL_PWD

  if [ ! -s "$out_sql" ]; then
    rm -f "$out_sql"
    die "dump file is empty or missing"
  fi
}
