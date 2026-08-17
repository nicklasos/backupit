#!/usr/bin/env bash

# DATABASE_URL helpers for postgres / mysql.

url_decode() {
  local encoded="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$encoded"
  elif command -v perl >/dev/null 2>&1; then
    perl -pe 's/%([0-9a-fA-F]{2})/chr(hex($1))/ge' <<< "$encoded"
  else
    echo "$encoded" | sed 's/%24/$/g; s/%25/%/g; s/%26/\&/g; s/%2B/+/g; s/%2F/\//g; s/%3A/:/g; s/%3D/=/g; s/%3F/?/g; s/%40/@/g'
  fi
}

# Parse DATABASE_URL into DB_SCHEME, DB_USER, DB_PASS, DB_HOST, DB_PORT, DB_NAME.
parse_database_url() {
  local url="$1"
  DB_SCHEME=""
  DB_USER=""
  DB_PASS=""
  DB_HOST=""
  DB_PORT=""
  DB_NAME=""

  if [[ "$url" =~ ^(postgres|postgresql|mysql)://([^:/@]+):([^@]*)@([^:/]+):([0-9]+)/([^?]+) ]]; then
    DB_SCHEME="${BASH_REMATCH[1]}"
    DB_USER=$(url_decode "${BASH_REMATCH[2]}")
    DB_PASS=$(url_decode "${BASH_REMATCH[3]}")
    DB_HOST="${BASH_REMATCH[4]}"
    DB_PORT="${BASH_REMATCH[5]}"
    DB_NAME=$(url_decode "${BASH_REMATCH[6]}")
  elif [[ "$url" =~ ^(postgres|postgresql|mysql)://([^:/@]+)@([^:/]+):([0-9]+)/([^?]+) ]]; then
    DB_SCHEME="${BASH_REMATCH[1]}"
    DB_USER=$(url_decode "${BASH_REMATCH[2]}")
    DB_PASS=""
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME=$(url_decode "${BASH_REMATCH[5]}")
  else
    die "Invalid DATABASE_URL (expected postgres:// or mysql://user:pass@host:port/dbname)"
  fi

  # Strip optional query/sslmode from db name if present
  DB_NAME="${DB_NAME%%\?*}"
}

# Normalize DB_ENGINE to postgres|mysql. Must be set explicitly in .env.
resolve_db_engine() {
  local engine="${DB_ENGINE:-}"
  engine=$(echo "$engine" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

  case "$engine" in
    postgres|postgresql|pg)
      DB_ENGINE="postgres"
      ;;
    mysql|mariadb)
      DB_ENGINE="mysql"
      ;;
    "")
      die "DB_ENGINE is required in .env (set to postgres or mysql)"
      ;;
    *)
      die "DB_ENGINE must be postgres or mysql (got: '${DB_ENGINE}')"
      ;;
  esac
}

database_url_host() {
  local url="${1:-$DATABASE_URL}"
  if [[ "$url" =~ @([^:/]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "(unknown)"
  fi
}
