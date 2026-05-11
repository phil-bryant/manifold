#!/bin/bash
#R001: Enforce strict shell mode and secure default file permissions.
umask 007
set -euo pipefail

#R015: Configure credential source and target database via environment overrides.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
DATABASE_NAME=""
DATABASE_SCHEMA=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
BACKUP_PATH=""
GLOBALS_BACKUP_PATH=""

usage() {
    echo "Usage: $0 [--from /path/to/backup.dump]"
}

latest_backup_path() {
    #R005: Resolve newest local dump when --from is not provided.
    local latest=""
    local candidate=""
    shopt -s nullglob
    for candidate in "$BACKUP_DIR"/*.dump; do
        if [ -z "$latest" ] || [ "$candidate" -nt "$latest" ]; then
            latest="$candidate"
        fi
    done
    shopt -u nullglob
    echo "$latest"
}

#R005: Parse optional --from backup source argument.
while [ "$#" -gt 0 ]; do
    case "$1" in
        --from)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            BACKUP_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

#R010: Require restore dependencies before running restore commands.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi
if ! command -v pg_restore >/dev/null 2>&1; then
    echo "pg_restore is required but was not found on PATH."
    exit 1
fi
if ! command -v psql >/dev/null 2>&1; then
    echo "psql is required but was not found on PATH."
    exit 1
fi

#R015: Resolve postgres password plus manifold host/port/database from 1psa.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi
DB_HOST="$(1psa -f "$MANIFOLD_PSA_ITEM" "host")"
DB_PORT="$(1psa -f "$MANIFOLD_PSA_ITEM" "port")"
DATABASE_NAME="$(1psa -f "$MANIFOLD_PSA_ITEM" "database")"
DATABASE_SCHEMA="$(1psa -f "$MANIFOLD_PSA_ITEM" "schema")"
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
if [ -z "$DATABASE_NAME" ]; then
    echo "Failed to read manifold database from 1psa item: $MANIFOLD_PSA_ITEM"
    exit 1
fi
if [ -z "$DATABASE_SCHEMA" ]; then
    echo "Failed to read manifold schema from 1psa item: $MANIFOLD_PSA_ITEM"
    exit 1
fi
DATABASE_SCHEMA_SQL="${DATABASE_SCHEMA//\'/\'\'}"

#R005: Default to latest backup when --from is omitted.
if [ -z "$BACKUP_PATH" ]; then
    BACKUP_PATH="$(latest_backup_path)"
fi

#R020: Require backup dump and matching globals files to exist.
if [ -z "$BACKUP_PATH" ]; then
    echo "No backup file found in $BACKUP_DIR"
    exit 1
fi
if [ ! -f "$BACKUP_PATH" ]; then
    echo "Backup file does not exist: $BACKUP_PATH"
    exit 1
fi
GLOBALS_BACKUP_PATH="${BACKUP_PATH%.dump}_globals.sql"
if [ ! -f "$GLOBALS_BACKUP_PATH" ]; then
    echo "Matching globals backup is missing: $GLOBALS_BACKUP_PATH"
    echo "Recreate backup with 97_backup_database.sh to include roles and grants."
    exit 1
fi

#R025: Refuse full restore when ingest tables already exist in target db.
database_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}';")"
if [ "$database_exists" = "1" ]; then
    ingest_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d "$DATABASE_NAME" -tAc "SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r' AND c.relname = 'ingest_batches' AND n.nspname = '${DATABASE_SCHEMA_SQL}' LIMIT 1;")"
    if [ "$ingest_exists" = "1" ]; then
        echo "Database ${DATABASE_NAME} already contains ingest schema objects in schema ${DATABASE_SCHEMA}; refusing restore."
        exit 1
    fi
fi

#R030: Restore globals first, then database content.
PGPASSWORD="$POSTGRES_PASSWORD" psql -w -h "$DB_HOST" -p "$DB_PORT" -v ON_ERROR_STOP=1 -U postgres -d postgres -f "$GLOBALS_BACKUP_PATH"
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d postgres --clean --if-exists --create "$BACKUP_PATH"

#R035: Print completion status with source backup path.
echo "Restore complete from: $BACKUP_PATH"
