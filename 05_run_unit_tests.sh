#!/usr/bin/env bash
#R001: Enforce strict fail-fast execution semantics.
set -euo pipefail

#R005: Resolve manifold credential from dedicated 1psa item.
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_PSA_FIELD="${MANIFOLD_PSA_FIELD:-password}"
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER="manifold"
DB_SCHEMA=""

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
DB_HOST="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "host")"
if [ -z "$DB_HOST" ]; then
  echo "Failed to resolve manifold host from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_PORT="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "port")"
if [[ ! "${DB_PORT}" =~ ^[0-9]+$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
  echo "Failed to resolve manifold port from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_NAME="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "database")"
if [ -z "$DB_NAME" ]; then
  echo "Failed to resolve manifold database from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "schema")"
if [ -z "$DB_SCHEMA" ]; then
  echo "Failed to resolve manifold schema from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA_IDENT="\"${DB_SCHEMA//\"/\"\"}\""

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

#R010: Refuse unit tests when bats is unavailable.
if ! command -v bats >/dev/null; then
  echo "bats is required but was not found on PATH."
  exit 1
fi

#R015: Resolve SQL test file path from script directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_TEST_FILE="${SCRIPT_DIR}/storage/sql/unit/ingest_schema_pgtap.sql"

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
  psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v schema_name="$DB_SCHEMA" -c "SET search_path TO ${DB_SCHEMA_IDENT};" -f "$SQL_TEST_FILE"

#R030: Run Go unit tests only after SQL unit tests pass.
GO_TEST_OUTPUT_FILE="$(mktemp)"
if ! go test ./... | tee "$GO_TEST_OUTPUT_FILE"; then
  exit 1
fi

#R030: Run Bats shell tests only after Go unit tests pass.
bats "${SCRIPT_DIR}/tests/sh"

#R032: Fail when any Go package reports no associated unit-test files.
NO_TEST_PACKAGES_FILE="$(mktemp)"
awk '$0 ~ /\[no test files\]/ { print $2 }' "$GO_TEST_OUTPUT_FILE" | sort -u > "$NO_TEST_PACKAGES_FILE"
if [ -s "$NO_TEST_PACKAGES_FILE" ]; then
  echo "❌ Go unit test coverage check failed: packages without _test.go files detected."
  sed 's/^/  - /' "$NO_TEST_PACKAGES_FILE"
  exit 1
fi

#R035: Emit concise operator-readable success output.
echo "✅ PASS: SQL, Go, and Bats unit tests completed."
