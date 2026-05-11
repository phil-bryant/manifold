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
  local mode="${2:-with-tests}"
  cat > "${STUB_BIN}/go" <<EOF
#!/usr/bin/env bash
echo "go \$*" >> "${CALLS_LOG}"
if [ "\${1:-}" = "test" ]; then
  if [ "${mode}" = "with-tests" ]; then
    cat <<'GOOUT'
ok      manifold/storage       0.001s
GOOUT
  fi
  if [ "${mode}" = "no-tests" ]; then
    cat <<'GOOUT'
?       manifold/cmd/manifold   [no test files]
ok      manifold/storage       0.001s
GOOUT
  fi
  exit ${exit_code}
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
}

make_bats_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/bats" <<EOF
#!/usr/bin/env bash
echo "bats \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/bats"
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
    localhost_postgres_manifold:password)
      printf '%s\n' "${MANIFOLD_PASSWORD-manifold-password}"
      ;;
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
  copy_script_to_fixture "05_run_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/storage/sql/unit"
  cat > "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql" <<'EOF'
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
  make_bats_stub 0
  make_1psa_stub
}

@test "fails on first psql error" {
  #R001
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is unavailable" {
  #R005
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "fails when manifold 1psa credential lookup is empty" {
  #R005
  run env MANIFOLD_PASSWORD= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold password from 1psa item"* ]]
}

@test "fails when manifold 1psa host/port/database/schema lookup is empty or invalid" {
  #R005
  run env ONEPSA_MANIFOLD_HOST= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold host from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_PORT=invalid bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold port from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_DATABASE= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold database from 1psa item"* ]]

  run env ONEPSA_MANIFOLD_SCHEMA= bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to resolve manifold schema from 1psa item"* ]]
}

@test "fails when psql is unavailable" {
  #R010
  rm -f "${STUB_BIN}/psql"
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"psql is required"* ]]
}

@test "fails when go is unavailable" {
  #R010
  rm -f "${STUB_BIN}/go"
  make_psql_stub 0
  make_bats_stub 0
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"go is required"* ]]
}

@test "fails when bats is unavailable" {
  #R010
  rm -f "${STUB_BIN}/bats"
  make_psql_stub 0
  make_go_stub 0
  make_1psa_stub
  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats is required"* ]]
}

@test "resolves SQL unit-test path relative to script location" {
  #R015
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "storage/sql/unit/ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "fails when SQL unit-test file is missing" {
  #R020
  mv "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql" \
    "${FIXTURE_ROOT}/storage/sql/unit/ingest_schema_pgtap.sql.trash"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SQL unit-test file not found"* ]]
}

@test "creates pgtap extension before running SQL unit tests" {
  #R025
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
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
  run env ONEPSA_MANIFOLD_HOST=db.internal ONEPSA_MANIFOLD_PORT=6543 ONEPSA_MANIFOLD_DATABASE=prod ONEPSA_MANIFOLD_SCHEMA=manifold bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-h db.internal" "${CALLS_LOG}"
  grep -F -- "-p 6543" "${CALLS_LOG}"
  grep -F -- "-U manifold" "${CALLS_LOG}"
  grep -F -- "-d prod" "${CALLS_LOG}"
  grep -F -- "schema_name=manifold" "${CALLS_LOG}"
  grep -F -- "SET search_path TO \"manifold\";" "${CALLS_LOG}"
  grep -F "ON_ERROR_STOP=1" "${CALLS_LOG}"
  grep -F "ingest_schema_pgtap.sql" "${CALLS_LOG}"
}

@test "does not run go tests when SQL stage fails" {
  #R030
  make_psql_stub 1
  make_go_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  ! grep -F "go test ./..." "${CALLS_LOG}"
}

@test "fails when go unit tests fail" {
  #R030
  make_psql_stub 0
  make_go_stub 1
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  grep -F "go test ./..." "${CALLS_LOG}"
}

@test "runs go then bats only after SQL unit tests pass" {
  #R030
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  local sql_line
  sql_line="$(grep -n "ingest_schema_pgtap.sql" "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  local go_line
  go_line="$(grep -n "go test ./..." "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  local bats_line
  bats_line="$(grep -n "bats " "${CALLS_LOG}" | cut -d: -f1 | head -n 1)"
  [ -n "$sql_line" ]
  [ -n "$go_line" ]
  [ -n "$bats_line" ]
  [ "$go_line" -gt "$sql_line" ]
  [ "$bats_line" -gt "$go_line" ]
}

@test "fails when go test output includes packages with no test files" {
  #R032
  make_go_stub 0 "no-tests"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"packages without _test.go files detected"* ]]
  [[ "$output" == *"manifold/cmd/manifold"* ]]
}

@test "passes go coverage gate when all packages include test files" {
  #R032
  make_go_stub 0 "with-tests"
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "emits a single pass line after successful SQL and Go unit tests" {
  #R035
  make_go_stub 0 "with-tests"
  make_bats_stub 0
  run bash "${FIXTURE_ROOT}/05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}
