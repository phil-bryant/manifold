#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve manifold credential from dedicated 1psa item.
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_PSA_FIELD="${MANIFOLD_PSA_FIELD:-password}"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="manifold"
DB_USER="manifold"

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

DB_PASSWORD="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "$MANIFOLD_PSA_FIELD")"
if [ -z "$DB_PASSWORD" ]; then
  echo "Failed to resolve manifold password from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi

#R010: Refuse SQL unit tests when psql is unavailable.
if ! command -v psql >/dev/null; then
  echo "psql is required but was not found on PATH."
  exit 1
fi

#R010: Refuse unit tests when go is unavailable.
if ! command -v go >/dev/null; then
  echo "go is required but was not found on PATH."
  exit 1
fi

#R015: Resolve SQL test file path from script directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_TEST_FILE="${SCRIPT_DIR}/internal/storage/sql/unit/ingest_schema_pgtap.sql"

#R020: Fail clearly when SQL unit-test file is missing.
if [ ! -f "$SQL_TEST_FILE" ]; then
  echo "SQL unit-test file not found: ${SQL_TEST_FILE}"
  exit 1
fi

#R025: Ensure pgTAP extension exists in target database.
PGPASSWORD="$DB_PASSWORD" \
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

#R030: Execute SQL unit tests first with fail-fast psql settings.
PGPASSWORD="$DB_PASSWORD" \
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_TEST_FILE"

#R030: Run Go unit tests only after SQL unit tests pass.
go test ./...

#R035: Emit concise operator-readable success output.
echo "✅ PASS: SQL and Go unit tests completed."
