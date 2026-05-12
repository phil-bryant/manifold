#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MANIFOLD_ADDR="${MANIFOLD_ADDR:-:8080}"
MANIFOLD_INGEST_KEY="${MANIFOLD_INGEST_KEY:-local-ingest-key}"
MANIFOLD_DATABASE_SSLMODE="${MANIFOLD_DATABASE_SSLMODE:-disable}"
MANIFOLD_DATABASE_1PSA_ITEM="${MANIFOLD_DATABASE_1PSA_ITEM:-localhost_postgres_manifold}"
MANIFOLD_DATABASE_URL_SOURCE="env"

require_command() {
  local command_name="$1"
  #R005: Fail fast with installer guidance when required commands are missing.
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

read_database_field_from_1psa() {
  local field="$1"
  local field_upper=""
  local value=""
  field_upper="$(printf '%s' "$field" | tr '[:lower:]' '[:upper:]')"
  set +e
  value="$(1psa -f "${MANIFOLD_DATABASE_1PSA_ITEM}" "${field}" 2>/dev/null)"
  local read_exit=$?
  set -e
  if [[ "${read_exit}" -ne 0 ]]; then
    #R015: Fail clearly when database fields cannot be resolved from 1psa.
    echo "❌ Failed to read MANIFOLD_DATABASE_${field_upper} from 1psa item/field: ${MANIFOLD_DATABASE_1PSA_ITEM}/${field}" >&2
    return 1
  fi
  value="${value//$'\r'/}"
  value="${value%$'\n'}"
  if [[ -z "${value}" ]]; then
    #R015: Reject empty 1psa field values required for runtime database URL composition.
    echo "❌ 1psa returned an empty MANIFOLD_DATABASE_${field_upper} for item/field: ${MANIFOLD_DATABASE_1PSA_ITEM}/${field}" >&2
    return 1
  fi
  printf '%s' "${value}"
}

compose_database_url_from_1psa() {
  local database_user=""
  local database_password=""
  local database_host=""
  local database_port=""
  local database_name=""
  database_user="$(read_database_field_from_1psa "username")" || return 1
  database_password="$(read_database_field_from_1psa "password")" || return 1
  database_host="$(read_database_field_from_1psa "host")" || return 1
  database_port="$(read_database_field_from_1psa "port")" || return 1
  database_name="$(read_database_field_from_1psa "database")" || return 1
  if [[ ! "${database_port}" =~ ^[0-9]+$ ]] || (( database_port < 1 || database_port > 65535 )); then
    #R015: Validate 1psa-derived port values before launching runtime.
    echo "❌ 1psa returned an invalid MANIFOLD_DATABASE_PORT for item/field: ${MANIFOLD_DATABASE_1PSA_ITEM}/port" >&2
    return 1
  fi
  python3 - "${database_user}" "${database_password}" "${database_host}" "${database_port}" "${database_name}" "${MANIFOLD_DATABASE_SSLMODE}" <<'PY'
import sys
from urllib.parse import quote

user, password, host, port, dbname, sslmode = sys.argv[1:]
print(
    "postgres://"
    + quote(user, safe="")
    + ":"
    + quote(password, safe="")
    + "@"
    + host
    + ":"
    + port
    + "/"
    + dbname
    + "?sslmode="
    + sslmode
)
PY
}

require_command go

#R010: Compose MANIFOLD_DATABASE_URL from 1psa when explicit URL override is not provided.
if [[ -z "${MANIFOLD_DATABASE_URL:-}" ]]; then
  require_command 1psa
  require_command python3
  if ! MANIFOLD_DATABASE_URL="$(compose_database_url_from_1psa)"; then
    exit 1
  fi
  MANIFOLD_DATABASE_URL_SOURCE="1psa"
fi

#R020: Honor explicit MANIFOLD_DATABASE_URL overrides without requiring 1psa.
if [[ -z "${MANIFOLD_DATABASE_URL}" ]]; then
  echo "❌ MANIFOLD_DATABASE_URL must be non-empty."
  exit 1
fi

#R025: Emit deterministic startup context and launch manifold service from cmd/manifold.
echo "▶ Starting manifold service"
echo "ℹ️  MANIFOLD_ADDR=${MANIFOLD_ADDR}"
echo "ℹ️  MANIFOLD_DATABASE_URL source=${MANIFOLD_DATABASE_URL_SOURCE}"
echo "ℹ️  MANIFOLD_INGEST_KEY source=env/default"
echo "ℹ️  Launch command: go run ./cmd/manifold"
exec env \
  MANIFOLD_ADDR="${MANIFOLD_ADDR}" \
  MANIFOLD_DATABASE_URL="${MANIFOLD_DATABASE_URL}" \
  MANIFOLD_INGEST_KEY="${MANIFOLD_INGEST_KEY}" \
  go run ./cmd/manifold
