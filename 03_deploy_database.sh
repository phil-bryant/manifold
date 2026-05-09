#!/bin/bash
#R001: Fail fast on unrecoverable SQL/bootstrap errors.
set -e

#R010: Configurable preferred 1psa source for postgres admin password.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
#R015: Configurable preferred 1psa source for teller user password.
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_manifold}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"
#R020: Environment fallback values when 1psa is unavailable or empty.
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
TELLER_PASSWORD="${TELLER_PASSWORD:-}"
POSTGRES_PASSWORD_FALLBACK="$POSTGRES_PASSWORD"
TELLER_PASSWORD_FALLBACK="$TELLER_PASSWORD"
#R035: Resolve SQL directory relative to script location.
SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql/postgres"

#R035: Fail fast with clear guidance when SQL assets are missing.
if [ ! -d "$SQL_DIR" ]; then
    echo "Missing SQL directory: $SQL_DIR"
    echo "This repository currently does not include sql/postgres deploy assets."
    echo "Expected files include create_database.sql and configure_database.sql."
    exit 1
fi

#R006: Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

#R007: Run SQL as postgres with fail-fast psql options.
run_psql_postgres() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres "$@"
}

#R008: Run SQL as teller with fail-fast psql options.
run_psql_teller() {
    PGPASSWORD="$TELLER_PASSWORD" psql "${PSQL_OPTS[@]}" -U teller -d prod "$@"
}

probe_postgres_password() {
    PGPASSWORD="$1" psql "${PSQL_OPTS[@]}" -U postgres -c '\q'
}

probe_teller_password() {
    PGPASSWORD="$1" psql "${PSQL_OPTS[@]}" -U teller -d prod -c '\q'
}

resolve_1psa_field() {
    local item="$1"
    local field="$2"
    local secret=""
    if [ -n "$field" ]; then
        if secret="$(1psa -f "$item" "$field")"; then
            if [ -n "$secret" ]; then
                echo "$secret"
            fi
        fi
    fi
}

#R005: Prefer 1psa credential lookups when available.
ONEPSA_PATH="$(command -v 1psa || true)"
if [ -n "$ONEPSA_PATH" ]; then
    #R010: Resolve postgres password from configured item/field.
    if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
        if resolved_postgres_password="$(1psa -p "$POSTGRES_PSA_ITEM")"; then
            if [ -n "$resolved_postgres_password" ]; then
                POSTGRES_PASSWORD="$resolved_postgres_password"
            fi
        fi
    else
        if resolved_postgres_password="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"; then
            if [ -n "$resolved_postgres_password" ]; then
                POSTGRES_PASSWORD="$resolved_postgres_password"
            fi
        fi
    fi
    #R015: Resolve teller password from configured item/field.
    if [ "$TELLER_PSA_FIELD" = "password" ]; then
        if resolved_teller_password="$(1psa -p "$TELLER_PSA_ITEM")"; then
            if [ -n "$resolved_teller_password" ]; then
                TELLER_PASSWORD="$resolved_teller_password"
            fi
        fi
    else
        if resolved_teller_password="$(1psa -f "$TELLER_PSA_ITEM" "$TELLER_PSA_FIELD")"; then
            if [ -n "$resolved_teller_password" ]; then
                TELLER_PASSWORD="$resolved_teller_password"
            fi
        fi
    fi
fi

#R020: Refuse deployment when postgres password stays empty after 1psa/env resolution.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to resolve postgres password from 1psa or POSTGRES_PASSWORD."
    exit 1
fi

#R020: Refuse deployment when teller password stays empty after 1psa/env resolution.
if [ -z "$TELLER_PASSWORD" ]; then
    echo "Failed to resolve teller password from 1psa or TELLER_PASSWORD."
    exit 1
fi

#R005: If preferred 1psa password cannot authenticate, retry with env fallback.
if ! probe_postgres_password "$POSTGRES_PASSWORD"; then
    alt_postgres_password=""
    if [ -n "$ONEPSA_PATH" ]; then
        alt_postgres_password="$(resolve_1psa_field "$POSTGRES_PSA_ITEM" "postgres_password")"
        if [ -z "$alt_postgres_password" ]; then
            alt_postgres_password="$(resolve_1psa_field "$POSTGRES_PSA_ITEM" "admin_password")"
        fi
    fi
    if [ -n "$alt_postgres_password" ] && [ "$alt_postgres_password" != "$POSTGRES_PASSWORD" ]; then
        if probe_postgres_password "$alt_postgres_password"; then
            POSTGRES_PASSWORD="$alt_postgres_password"
        fi
    fi
    if ! probe_postgres_password "$POSTGRES_PASSWORD"; then
        if [ -n "$POSTGRES_PASSWORD_FALLBACK" ] && [ "$POSTGRES_PASSWORD_FALLBACK" != "$POSTGRES_PASSWORD" ]; then
            if probe_postgres_password "$POSTGRES_PASSWORD_FALLBACK"; then
                POSTGRES_PASSWORD="$POSTGRES_PASSWORD_FALLBACK"
            else
                echo "Failed to authenticate as postgres with 1psa and POSTGRES_PASSWORD fallback."
                exit 1
            fi
        else
            echo "Failed to authenticate as postgres with resolved password."
            exit 1
        fi
    fi
fi

#R025: Run admin bootstrap SQL in required order.
run_psql_postgres -f "${SQL_DIR}/create_database.sql"
run_psql_postgres -d prod -v teller_password="$TELLER_PASSWORD" -f "${SQL_DIR}/configure_database.sql"
#R050: Ensure pgTAP extension exists in prod for SQL unit test execution.
run_psql_postgres -d prod -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

#R005: If preferred 1psa teller password cannot authenticate, retry with env fallback.
if ! probe_teller_password "$TELLER_PASSWORD"; then
    alt_teller_password=""
    if [ -n "$ONEPSA_PATH" ]; then
        alt_teller_password="$(resolve_1psa_field "$TELLER_PSA_ITEM" "teller_password")"
    fi
    if [ -n "$alt_teller_password" ] && [ "$alt_teller_password" != "$TELLER_PASSWORD" ]; then
        if probe_teller_password "$alt_teller_password"; then
            TELLER_PASSWORD="$alt_teller_password"
        fi
    fi
    if ! probe_teller_password "$TELLER_PASSWORD"; then
        if [ -n "$TELLER_PASSWORD_FALLBACK" ] && [ "$TELLER_PASSWORD_FALLBACK" != "$TELLER_PASSWORD" ]; then
            if probe_teller_password "$TELLER_PASSWORD_FALLBACK"; then
                TELLER_PASSWORD="$TELLER_PASSWORD_FALLBACK"
            else
                echo "Failed to authenticate as teller with 1psa and TELLER_PASSWORD fallback."
                exit 1
            fi
        else
            echo "Failed to authenticate as teller with resolved password."
            exit 1
        fi
    fi
fi

#R030: Build teller schema objects in declared dependency order.
run_psql_teller -f "${SQL_DIR}/teller_enums.sql"
run_psql_teller -f "${SQL_DIR}/teller_institution.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_name.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_email.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_phone_number.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_address_data.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_address.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_identities.sql"
run_psql_teller -f "${SQL_DIR}/teller_routing_numbers.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_details_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_details.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_balances_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_balances.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_type.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_details_counterparty.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_details.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction.sql"
run_psql_teller -f "${SQL_DIR}/teller_nys_snw_category.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_nys_snw_category.sql"
#R045: Ensure transaction classification FK cascades deletes from teller.transaction.
run_psql_teller -c \
"ALTER TABLE teller.transaction_nys_snw_category \
 DROP CONSTRAINT IF EXISTS transaction_nys_snw_category_transaction_id_fkey, \
 ADD CONSTRAINT transaction_nys_snw_category_transaction_id_fkey \
 FOREIGN KEY (transaction_id) REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE;"
#R040: Attach updated_at triggers only after all updated_at tables exist.
run_psql_teller -f "${SQL_DIR}/create_triggers.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_info_view.sql"
run_psql_teller -f "${SQL_DIR}/create_audit.sql"

