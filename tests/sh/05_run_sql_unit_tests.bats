#!/usr/bin/env bats

load "helpers/common.bash"

make_psql_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/psql"
  : > "${CALLS_LOG}"
}

make_go_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [ "\${1:-}" = "test" ]; then
  exit ${exit_code}
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
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
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "05_run_sql_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/internal/storage/sql/unit"
  cat > "${FIXTURE_ROOT}/internal/storage/sql/unit/ingest_schema_pgtap.sql" <<'EOF'
SELECT plan(1);
SELECT ok(true, 'stub');
SELECT * FROM finish();
EOF
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_fixture
  make_psql_stub 0
  make_go_stub 0
  make_1psa_stub
}

@test "fails on first psql error" {
  #R001
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when manifold 1psa credential lookup is empty" {
  #R005
  run env MANIFOLD_PASSWORD= bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold password from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "fails when go is unavailable" {
  #R010
  rm -f "${STUB_BIN}/go"
  make_psql_stub 0
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"go is required"* ]]
}

@test "resolves SQL unit-test path relative to script location" {
  #R015
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "internal/storage/sql/unit/ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "fails when SQL unit-test file is missing" {
  #R020
  mv "${FIXTURE_ROOT}/internal/storage/sql/unit/ingest_schema_pgtap.sql" \
    "${FIXTURE_ROOT}/internal/storage/sql/unit/ingest_schema_pgtap.sql.trash"
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SQL unit-test file not found"* ]]
}

@test "creates pgtap extension before running SQL unit tests" {
  #R025
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -eq 0 ]
  local create_line
  create_line="$(grep -n "CREATE EXTENSION IF NOT EXISTS pgtap" "${CALLS_LOG}")"
  local run_line
  run_line="$(grep -n "ingest_schema_pgtap.sql" "${CALLS_LOG}")"
  [ -n "$create_line" ]
  [ -n "$run_line" ]
}

@test "runs SQL unit tests with fail-fast psql options" {
  #R030
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-h localhost" "${CALLS_LOG}"
  grep -F -- "-p 5432" "${CALLS_LOG}"
  grep -F -- "-U manifold" "${CALLS_LOG}"
  grep -F -- "-d manifold" "${CALLS_LOG}"
  grep -F "ON_ERROR_STOP=1" "${CALLS_LOG}"
  grep -F "ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "does not run go tests when SQL stage fails" {
  #R030
  make_psql_stub 1
  make_go_stub 0
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  ! grep -F "go test ./..." "${CALLS_LOG}"
}

@test "fails when go unit tests fail" {
  #R030
  make_psql_stub 0
  make_go_stub 1
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -ne 0 ]
  grep -F "go test ./..." "${CALLS_LOG}"
}

@test "runs go tests only after SQL unit tests pass" {
  #R030
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -eq 0 ]
  local sql_line
  sql_line="$(grep -n "ingest_schema_pgtap.sql" "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  local go_line
  go_line="$(grep -n "go test ./..." "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  [ -n "$sql_line" ]
  [ -n "$go_line" ]
  [ "$go_line" -gt "$sql_line" ]
}

@test "emits a single pass line after successful SQL and Go unit tests" {
  #R035
  run bash "${FIXTURE_ROOT}/05_run_sql_unit_tests.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}
