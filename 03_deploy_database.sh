#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve admin and manifold credentials from dedicated 1psa items.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_PSA_FIELD="${MANIFOLD_PSA_FIELD:-password}"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="manifold"
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

POSTGRES_PASSWORD="$(read_1psa_secret "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Failed to resolve postgres password from 1psa item: ${POSTGRES_PSA_ITEM}"
  exit 1
fi

MANIFOLD_PASSWORD="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "$MANIFOLD_PSA_FIELD")"
if [ -z "$MANIFOLD_PASSWORD" ]; then
  echo "Failed to resolve manifold password from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
MANIFOLD_PASSWORD_SQL="${MANIFOLD_PASSWORD//\'/\'\'}"

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

PGPASSWORD="$MANIFOLD_PASSWORD" \
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$MANIFOLD_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SCHEMA_PATH"

#R030: Emit concise operator-readable success output.
echo "✅ PASS: Applied manifold schema to target database."

