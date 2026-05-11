#!/usr/bin/env bats

load "helpers/common.bash"

make_psql_happy() {
  cat > "${STUB_BIN}/psql" <<'PY'
#!/usr/bin/env python3
import os
import sys

def log_line():
  path = os.environ.get("PSQL_LOG", "")
  if not path:
    return
  with open(path, "a", encoding="utf-8") as h:
    h.write("psql " + " ".join(sys.argv[1:]) + "\n")

def get_sql(args):
  if "-c" in args:
    return args[args.index("-c") + 1]
  return ""

def main():
  log_line()
  args = sys.argv[1:]
  sql = get_sql(args)
  if "expected(table_name)" in sql and "ingest_batches" in sql:
    print(os.environ.get("MISSING_TABLES", ""), end="")
    return
  if "expected(index_name)" in sql and "idx_ingest_events_timestamp" in sql:
    print(os.environ.get("MISSING_INDEXES", ""), end="")
    return
  if "child_rel.relname = 'ingest_events'" in sql and "parent_rel.relname = 'ingest_batches'" in sql:
    print("f" if os.environ.get("FK_MISSING") == "1" else "t", end="")
    return
  print("t", end="")

if __name__ == "__main__":
  main()
PY
  chmod +x "${STUB_BIN}/psql"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-p" ]; then
  case "${2:-}" in
    localhost_postgres_manifold)
      printf '%s\n' "${MANIFOLD_PASSWORD-manifold-password}"
      ;;
    *)
      exit 1
      ;;
  esac
  exit 0
fi
if [ "${1:-}" = "-f" ]; then
  case "${2:-}:${3:-}" in
    localhost_postgres_manifold:host)
      printf '%s\n' "${ONEPSA_MANIFOLD_HOST-localhost}"
      ;;
    localhost_postgres_manifold:port)
      printf '%s\n' "${ONEPSA_MANIFOLD_PORT-5432}"
      ;;
    localhost_postgres_manifold:database)
      printf '%s\n' "${ONEPSA_MANIFOLD_DATABASE-manifold}"
      ;;
    localhost_postgres_manifold:schema)
      printf '%s\n' "${ONEPSA_MANIFOLD_SCHEMA-manifold}"
      ;;
    localhost_postgres_manifold:password)
      printf '%s\n' "${MANIFOLD_PASSWORD-manifold-password}"
      ;;
    *)
      exit 1
      ;;
  esac
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "04_verify_deploy_database.sh"
  export PSQL_LOG="${TEST_TMPDIR}/psql.log"
  : > "${PSQL_LOG}"
  make_psql_happy
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  export PSQL_LOG
}

teardown() {
  teardown_shell_test
}

@test "fails on first psql error" {
  #R001
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/psql"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when manifold 1psa credential lookup is empty" {
  #R005
  run env MANIFOLD_PASSWORD= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold password from 1psa item"* ]]
}

@test "fails when manifold 1psa host/port/database/schema lookup is empty or invalid" {
  #R005
  run env ONEPSA_MANIFOLD_HOST= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold host from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_PORT=bad sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold port from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_DATABASE= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold database from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_SCHEMA= sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold schema from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "fails when required tables are missing" {
  #R015
  : > "${PSQL_LOG}"
  make_psql_happy
  run env MISSING_TABLES=ingest_events \
    sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing tables"* ]]
  [[ "$output" == *"ingest_events"* ]]
}

@test "fails when required indexes are missing" {
  #R020
  : > "${PSQL_LOG}"
  make_psql_happy
  run env MISSING_INDEXES=idx_ingest_events_component \
    sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing indexes"* ]]
  [[ "$output" == *"idx_ingest_events_component"* ]]
}

@test "fails when ingest_events to ingest_batches FK is missing" {
  #R025
  : > "${PSQL_LOG}"
  make_psql_happy
  run env FK_MISSING=1 sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing FK: ingest_events(batch_id) -> ingest_batches(batch_id)"* ]]
}

@test "emits a single pass line for successful verification" {
  #R030
  : > "${PSQL_LOG}"
  make_psql_happy
  run sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}

@test "uses fail-fast psql options with 1psa target and manifold user" {
  #R035
  : > "${PSQL_LOG}"
  make_psql_happy
  run env ONEPSA_MANIFOLD_HOST=db.internal ONEPSA_MANIFOLD_PORT=6543 ONEPSA_MANIFOLD_DATABASE=manifold_verify ONEPSA_MANIFOLD_SCHEMA=manifold_data sh "${FIXTURE_ROOT}/04_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-h db.internal" "${PSQL_LOG}"
  grep -F -- "-p 6543" "${PSQL_LOG}"
  grep -F -- "-U manifold" "${PSQL_LOG}"
  grep -F -- "-d manifold_verify" "${PSQL_LOG}"
  grep -F -- "table_schema = 'manifold_data'" "${PSQL_LOG}"
  grep -F "ON_ERROR_STOP=1" "${PSQL_LOG}"
}
