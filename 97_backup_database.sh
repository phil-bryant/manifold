#!/bin/bash
#R001: Enforce strict shell mode and secure default file permissions.
umask 007
set -euo pipefail

#R010: Configure credential source and database name via environment overrides.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
MANIFOLD_PSA_ITEM="${MANIFOLD_PSA_ITEM:-localhost_postgres_manifold}"
DATABASE_NAME="${DATABASE_NAME:-manifold}"
BACKUP_INCLUDE_ROLE_AUTH_DATA="${BACKUP_INCLUDE_ROLE_AUTH_DATA:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
BACKUP_BASENAME="${DATABASE_NAME}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.dump"
GLOBALS_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}_globals.sql"

#R005: Require backup dependencies before running dump commands.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "pg_dump is required but was not found on PATH."
    exit 1
fi
if ! command -v pg_dumpall >/dev/null 2>&1; then
    echo "pg_dumpall is required but was not found on PATH."
    exit 1
fi

#R010: Resolve postgres password and manifold host/port from 1psa.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi
DB_HOST="$(1psa -f "$MANIFOLD_PSA_ITEM" "host")"
DB_PORT="$(1psa -f "$MANIFOLD_PSA_ITEM" "port")"

#R015: Refuse backup when credential or target lookup is invalid.
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

#R020: Create backup output directory with restricted permissions.
mkdir -p "$BACKUP_DIR"
chmod 770 "$BACKUP_DIR"

#R025: Write timestamped custom-format database dump.
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -w -h "$DB_HOST" -p "$DB_PORT" -U postgres -d "$DATABASE_NAME" -Fc -C -f "$BACKUP_PATH"
#R030: Write matching globals-only dump for roles/grants.
GLOBALS_ROLE_PASSWORD_ARGS=()
if [ "$BACKUP_INCLUDE_ROLE_AUTH_DATA" != "true" ]; then
    GLOBALS_ROLE_PASSWORD_ARGS+=(--no-role-passwords)
fi
PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -w -h "$DB_HOST" -p "$DB_PORT" -U postgres --globals-only "${GLOBALS_ROLE_PASSWORD_ARGS[@]}" -f "$GLOBALS_BACKUP_PATH"

#R035: Restrict output file permissions and print resulting paths.
chmod 660 "$BACKUP_PATH"
chmod 660 "$GLOBALS_BACKUP_PATH"
echo "Backup written: $BACKUP_PATH"
echo "Globals written: $GLOBALS_BACKUP_PATH"
