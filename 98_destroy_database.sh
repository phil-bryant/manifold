#!/bin/bash
#R001: Fail fast on unrecoverable teardown errors.
set -euo pipefail

#R005: Configure 1psa source for postgres password lookup and target identifiers.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
DATABASE_NAME="${DATABASE_NAME:-manifold}"
DATABASE_USER="${DATABASE_USER:-manifold}"

#R005: Require dependencies before credential lookup and teardown.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi
if ! command -v psql >/dev/null 2>&1; then
    echo "psql is required but was not found on PATH."
    exit 1
fi

#R005: Resolve postgres password and manifold host/port from 1psa.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi
DB_HOST="$(1psa -f "$MANIFOLD_PSA_ITEM" "host")"
DB_PORT="$(1psa -f "$MANIFOLD_PSA_ITEM" "port")"
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi
if [ -z "$DB_HOST" ]; then
    echo "Failed to read manifold host from 1psa item: $MANIFOLD_PSA_ITEM"
    exit 1
fi
if [[ ! "$DB_PORT" =~ ^[0-9]+$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
    echo "Failed to read manifold port from 1psa item: $MANIFOLD_PSA_ITEM"
    exit 1
fi

#R010: Require explicit destroy confirmation.
read -r -p "Type 'destroy' to drop ${DATABASE_NAME} and role ${DATABASE_USER}: " confirmation
if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

#R015: Terminate active sessions before database drop.
db_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}';")"
if [ "$db_exists" = "1" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -c \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DATABASE_NAME}' AND pid <> pg_backend_pid();"
fi

#R020: Drop manifold database and app role idempotently.
PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${DATABASE_NAME};"
PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DROP ROLE IF EXISTS ${DATABASE_USER};"

#R025: Print completion status after teardown.
echo "Cleanup complete!"