#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve admin and manifold credentials from dedicated 1psa items.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_PSA_FIELD="${MANIFOLD_PSA_FIELD:-password}"
DB_NAME=""
DB_SCHEMA=""
POSTGRES_USER="postgres"
MANIFOLD_USER="manifold"

if ! command -v 1psa >/dev/null; then
  echo "1psa is required but was not found on PATH."
  exit 1
fi

read_1psa_secret() {
  local item="$1"
  local field="$2"
  if [ "$field" = "password" ]; then
    1psa -p "$item"
  else
    1psa -f "$item" "$field"
  fi
}

# One 1psa round-trip per item. Sequential 1psa -f/-p calls each pay ~2s to 1Password.
POSTGRES_PASSWORD="$(read_1psa_secret "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Failed to resolve postgres password from 1psa item: ${POSTGRES_PSA_ITEM}"
  exit 1
fi

MANIFOLD_PASSWORD=""
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_SCHEMA=""
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  key="${line%%=*}"
  val="${line#*=}"
  case "$key" in
    password) MANIFOLD_PASSWORD="$val" ;;
    host) DB_HOST="$val" ;;
    port) DB_PORT="$val" ;;
    database) DB_NAME="$val" ;;
    schema) DB_SCHEMA="$val" ;;
  esac
done < <(1psa -m "$MANIFOLD_PSA_ITEM" password host port database schema)
if [ -z "$MANIFOLD_PASSWORD" ]; then
  echo "Failed to resolve manifold password from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
if [ -z "$DB_HOST" ]; then
  echo "Failed to resolve manifold host from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
if [[ ! "${DB_PORT}" =~ ^[0-9]+$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
  echo "Failed to resolve manifold port from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
if [ -z "$DB_NAME" ]; then
  echo "Failed to resolve manifold database from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
if [ -z "$DB_SCHEMA" ]; then
  echo "Failed to resolve manifold schema from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
MANIFOLD_PASSWORD_SQL="${MANIFOLD_PASSWORD//\'/\'\'}"
DB_SCHEMA_IDENT="\"${DB_SCHEMA//\"/\"\"}\""

#R010: Fail fast when psql client is unavailable.
if ! command -v psql >/dev/null; then
  echo "psql is required but was not found on PATH."
  exit 1
fi

#R015: Resolve schema path relative to script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="${SCRIPT_DIR}/storage/schema.sql"

#R020: Refuse deploy when schema file is missing.
if [ ! -f "$SCHEMA_PATH" ]; then
  echo "Schema file not found: ${SCHEMA_PATH}"
  exit 1
fi

run_psql_postgres() {
  PGPASSWORD="$POSTGRES_PASSWORD" \
    psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 "$@"
}

#R025: Bootstrap manifold role/database then apply schema as manifold.
if [ "$(run_psql_postgres -d postgres -At -c "SELECT 1 FROM pg_roles WHERE rolname = '${MANIFOLD_USER}'")" = "1" ]; then
  run_psql_postgres -d postgres \
    -c "ALTER ROLE ${MANIFOLD_USER} WITH LOGIN PASSWORD '${MANIFOLD_PASSWORD_SQL}';"
else
  run_psql_postgres -d postgres \
    -c "CREATE ROLE ${MANIFOLD_USER} WITH LOGIN PASSWORD '${MANIFOLD_PASSWORD_SQL}';"
fi

if [ "$(run_psql_postgres -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'")" != "1" ]; then
  run_psql_postgres -d postgres \
    -c "CREATE DATABASE ${DB_NAME} WITH OWNER = ${MANIFOLD_USER} ENCODING = 'UTF8' TEMPLATE template0;"
else
  run_psql_postgres -d postgres -c "ALTER DATABASE ${DB_NAME} OWNER TO ${MANIFOLD_USER};"
fi
run_psql_postgres -d "$DB_NAME" -c "CREATE SCHEMA IF NOT EXISTS ${DB_SCHEMA_IDENT} AUTHORIZATION ${MANIFOLD_USER};"

PGPASSWORD="$MANIFOLD_PASSWORD" \
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$MANIFOLD_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "SET search_path TO ${DB_SCHEMA_IDENT};" -f "$SCHEMA_PATH"

#R030: Emit concise operator-readable success output.
echo "✅ PASS: Applied manifold schema to target database."

