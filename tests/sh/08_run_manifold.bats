#!/usr/bin/env bats

load "helpers/common.bash"

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "08_run_manifold.sh"
}

setup() {
  setup_shell_test
  setup_fixture
}

teardown() {
  teardown_shell_test
}

make_go_stub() {
  cat > "${STUB_BIN}/go" <<'EOF'
#!/usr/bin/env bash
{
  echo "go $*"
  echo "PWD=$PWD"
  echo "MANIFOLD_ADDR=${MANIFOLD_ADDR:-}"
  echo "MANIFOLD_DATABASE_URL=${MANIFOLD_DATABASE_URL:-}"
  echo "MANIFOLD_INGEST_KEY=${MANIFOLD_INGEST_KEY:-}"
} >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
}

make_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "username" ]; then
  printf '%s' "${ONEPSA_DATABASE_USERNAME_VALUE-manifold}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "password" ]; then
  printf '%s' "${ONEPSA_DATABASE_PASSWORD_VALUE-manifold-password}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  printf '%s' "${ONEPSA_DATABASE_HOST_VALUE-localhost}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  printf '%s' "${ONEPSA_DATABASE_PORT_VALUE-5432}"
  exit 0
fi
if [ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  printf '%s' "${ONEPSA_DATABASE_NAME_VALUE-manifold}"
  exit 0
fi
exit 2
EOF
  chmod +x "${STUB_BIN}/1psa"
}

@test "runs from non-repo cwd and executes go run from script root" {
  #R001
  make_go_stub
  make_1psa_stub
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${PATH}" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/08_run_manifold.sh'"
  [ "$status" -eq 0 ]
  run grep -F "PWD=${FIXTURE_ROOT}" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "fails fast with installer guidance when go is missing" {
  #R005
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: go"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "composes MANIFOLD_DATABASE_URL from 1psa when unset" {
  #R010
  make_go_stub
  make_1psa_stub
  # pragma: allowlist nextline secret
  run env ONEPSA_DATABASE_USERNAME_VALUE="user+name" ONEPSA_DATABASE_PASSWORD_VALUE="pa:ss@word" ONEPSA_DATABASE_HOST_VALUE="db.internal" ONEPSA_DATABASE_PORT_VALUE="6543" ONEPSA_DATABASE_NAME_VALUE="manifold_prod" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -eq 0 ]
  # pragma: allowlist nextline secret
  run grep -F "MANIFOLD_DATABASE_URL=postgres://user%2Bname:pa%3Ass%40word@db.internal:6543/manifold_prod?sslmode=disable" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "fails clearly when required 1psa host is empty" {
  #R015
  make_go_stub
  make_1psa_stub
  run env ONEPSA_DATABASE_HOST_VALUE= PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty MANIFOLD_DATABASE_HOST"* ]]
}

@test "fails clearly when required 1psa port is invalid" {
  #R015
  make_go_stub
  make_1psa_stub
  run env ONEPSA_DATABASE_PORT_VALUE="not-a-port" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid MANIFOLD_DATABASE_PORT"* ]]
}

@test "uses explicit MANIFOLD_DATABASE_URL without requiring 1psa" {
  #R020
  make_go_stub
  run env MANIFOLD_DATABASE_URL="postgres://direct/db?sslmode=disable" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -eq 0 ]
  run grep -F "MANIFOLD_DATABASE_URL=postgres://direct/db?sslmode=disable" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "prints startup context and launches go run with runtime env" {
  #R025
  make_go_stub
  make_1psa_stub
  run env MANIFOLD_ADDR="127.0.0.1:9090" MANIFOLD_INGEST_KEY="from-env-key" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/08_run_manifold.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MANIFOLD_DATABASE_URL source=1psa"* ]]
  [[ "$output" == *"Launch command: go run ./cmd/manifold"* ]]
  run grep -F "go run ./cmd/manifold" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "MANIFOLD_ADDR=127.0.0.1:9090" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "MANIFOLD_INGEST_KEY=from-env-key" "${CALLS_LOG}"  # pragma: allowlist secret
  [ "$status" -eq 0 ]
}
