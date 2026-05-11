#!/bin/sh
#R001: Enforce strict fail-fast execution semantics.
set -eu

#R005: Resolve manifold credential from dedicated 1psa item.
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_PSA_FIELD="${MANIFOLD_PSA_FIELD:-password}"
DB_USER="manifold"
DB_SCHEMA=""

if ! command -v 1psa >/dev/null; then
  echo "❌ FAIL: 1psa is required but was not found on PATH."
  exit 1
fi

read_1psa_secret() {
  item="$1"
  field="$2"
  if [ "$field" = "password" ]; then
    1psa -p "$item"
  else
    1psa -f "$item" "$field"
  fi
}

DB_PASSWORD="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "$MANIFOLD_PSA_FIELD")"
if [ -z "$DB_PASSWORD" ]; then
  echo "❌ FAIL: Failed to resolve manifold password from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_HOST="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "host")"
if [ -z "$DB_HOST" ]; then
  echo "❌ FAIL: Failed to resolve manifold host from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_PORT="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "port")"
case "$DB_PORT" in
  ''|*[!0-9]*)
    echo "❌ FAIL: Failed to resolve manifold port from 1psa item: ${MANIFOLD_PSA_ITEM}"
    exit 1
    ;;
esac
DB_NAME="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "database")"
if [ -z "$DB_NAME" ]; then
  echo "❌ FAIL: Failed to resolve manifold database from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA="$(read_1psa_secret "$MANIFOLD_PSA_ITEM" "schema")"
if [ -z "$DB_SCHEMA" ]; then
  echo "❌ FAIL: Failed to resolve manifold schema from 1psa item: ${MANIFOLD_PSA_ITEM}"
  exit 1
fi
DB_SCHEMA_SQL="${DB_SCHEMA//\'/\'\'}"

#R010: Refuse verification when psql is unavailable.
if ! command -v psql >/dev/null; then
  echo "❌ FAIL: psql is required but was not found on PATH."
  exit 1
fi

#R035: Run all verification queries with fail-fast psql options.
db_lines() {
  PGPASSWORD="$DB_PASSWORD" \
    psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -At -c "$1"
}

#R035: Scalar helper shares fail-fast settings with line helper.
db_scalar() {
  db_lines "$1"
}

FAILURES=""
record_failure() {
  if [ -n "$FAILURES" ]; then
    FAILURES="${FAILURES}
$1"
  else
    FAILURES="$1"
  fi
}

comma_join_lines() {
  printf '%s' "$1" | tr '\n' ',' | sed 's/,$//'
}

echo "🔎 Verifying manifold database schema on ${DB_HOST}:${DB_PORT}/${DB_NAME} (schema=${DB_SCHEMA}) as ${DB_USER}..."

#R015: Verify required ingest tables exist.
echo "- checking required tables..."
missing_tables="$(
  db_lines "
    WITH expected(table_name) AS (
      VALUES ('ingest_batches'), ('ingest_events')
    )
    SELECT expected.table_name
    FROM expected
    LEFT JOIN information_schema.tables tables
      ON tables.table_schema = '${DB_SCHEMA_SQL}'
     AND tables.table_name = expected.table_name
     AND tables.table_type = 'BASE TABLE'
    WHERE tables.table_name IS NULL
    ORDER BY expected.table_name;
  "
)"
if [ -n "$missing_tables" ]; then
  record_failure "missing tables: $(comma_join_lines "$missing_tables")"
else
  echo "  ✓ tables present: ingest_batches, ingest_events"
fi

#R020: Verify required ingest indexes exist.
echo "- checking required indexes..."
missing_indexes="$(
  db_lines "
    WITH expected(index_name) AS (
      VALUES
        ('idx_ingest_events_timestamp'),
        ('idx_ingest_events_event_name'),
        ('idx_ingest_events_component'),
        ('idx_ingest_events_install_id')
    )
    SELECT expected.index_name
    FROM expected
    LEFT JOIN pg_indexes idx
      ON idx.schemaname = '${DB_SCHEMA_SQL}'
     AND idx.tablename = 'ingest_events'
     AND idx.indexname = expected.index_name
    WHERE idx.indexname IS NULL
    ORDER BY expected.index_name;
  "
)"
if [ -n "$missing_indexes" ]; then
  record_failure "missing indexes: $(comma_join_lines "$missing_indexes")"
else
  echo "  ✓ indexes present: timestamp, event_name, component, install_id"
fi

#R025: Verify ingest_events.batch_id FK references ingest_batches.batch_id.
echo "- checking foreign key relationship..."
if [ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class child_rel
      ON child_rel.oid = con.conrelid
    JOIN pg_namespace child_ns
      ON child_ns.oid = child_rel.relnamespace
    JOIN pg_class parent_rel
      ON parent_rel.oid = con.confrelid
    JOIN pg_namespace parent_ns
      ON parent_ns.oid = parent_rel.relnamespace
    WHERE con.contype = 'f'
      AND child_ns.nspname = '${DB_SCHEMA_SQL}'
      AND child_rel.relname = 'ingest_events'
      AND parent_ns.nspname = '${DB_SCHEMA_SQL}'
      AND parent_rel.relname = 'ingest_batches'
  );
")" != "t" ]; then
  record_failure "missing FK: ingest_events(batch_id) -> ingest_batches(batch_id)"
else
  echo "  ✓ FK present: ingest_events(batch_id) -> ingest_batches(batch_id)"
fi

#R030: Print explicit pass/fail verification result.
if [ -n "$FAILURES" ]; then
  echo "❌ FAIL: Manifold database verification failed."
  old_ifs="$IFS"
  IFS='
'
  for failure in $FAILURES; do
    echo "- $failure"
  done
  IFS="$old_ifs"
  exit 1
fi
echo "✅ PASS: Manifold database schema objects verified."
