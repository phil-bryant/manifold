#!/usr/bin/env bats

setup() {
  export REPO_ROOT SCRIPT_PATH TMP_ROOT STUB_BIN
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT_PATH="${REPO_ROOT}/02_run_dependency_freshness_checks.sh"
  TMP_ROOT="$(mktemp -d)"
  STUB_BIN="${TMP_ROOT}/bin"
  mkdir -p "${STUB_BIN}"
}

teardown() {
  if [ -d "${TMP_ROOT}" ]; then
    mv "${TMP_ROOT}" "${TMP_ROOT}.trash.$$" || true
  fi
}

create_go_stub() {
  local fixture_root="$1"
  cat > "${STUB_BIN}/go" <<EOF
#!/bin/bash
printf "go %s\n" "\$*" >> "${TMP_ROOT}/calls.log"
if [ "\$1" = "list" ] && [ "\$2" = "-m" ] && [ "\$3" = "-u" ]; then
  cat <<'UPDATES'
github.com/jackc/pgx/v5 v5.7.6 v5.8.0
example.com/legacy/v2 v2.4.0 v3.0.0
UPDATES
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  cp "${SCRIPT_PATH}" "${fixture_root}/02_run_dependency_freshness_checks.sh"
  chmod +x "${fixture_root}/02_run_dependency_freshness_checks.sh"
}

@test "R001,R005,R010,R015,R025: runs from non-root and writes manifold freshness artifacts" {
  #R001 #R005 #R010 #R015 #R025
  local fixture_root script_output
  fixture_root="$(mktemp -d)"
  create_go_stub "${fixture_root}"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" /bin/bash "${fixture_root}/02_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  script_output="$output"
  [ -f "${fixture_root}/.security-reports/dependency-freshness.txt" ]
  [ -f "${fixture_root}/.security-reports/dependency-freshness.json" ]
  run rg "github.com/jackc/pgx/v5 v5.7.6 -> v5.8.0" "${fixture_root}/.security-reports/dependency-freshness.txt"
  [ "$status" -eq 0 ]
  run rg "\"total_updates\": 2" "${fixture_root}/.security-reports/dependency-freshness.json"
  [ "$status" -eq 0 ]
  run rg "\"major_updates\": 1" "${fixture_root}/.security-reports/dependency-freshness.json"
  [ "$status" -eq 0 ]
  run rg "\"fail_on_updates\": true" "${fixture_root}/.security-reports/dependency-freshness.json"
  [ "$status" -eq 0 ]
  [[ "$script_output" == *"json report:"* ]]
}

@test "R005: fails fast when configured Go binary is missing" {
  #R005
  local fixture_root
  fixture_root="$(mktemp -d)"
  cp "${SCRIPT_PATH}" "${fixture_root}/02_run_dependency_freshness_checks.sh"
  chmod +x "${fixture_root}/02_run_dependency_freshness_checks.sh"
  run env PATH="/usr/bin:/bin" DEPENDENCY_CHECK_GO_BIN="go-does-not-exist" /bin/bash "${fixture_root}/02_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Go binary not found on PATH"* ]]
}

@test "R020: fails when major updates exist and fail-on-major is enabled" {
  #R020
  local fixture_root
  fixture_root="$(mktemp -d)"
  create_go_stub "${fixture_root}"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" DEPENDENCY_FAIL_ON_MAJOR=true /bin/bash "${fixture_root}/02_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Major dependency updates detected"* ]]
  run rg "\"major_updates\": 1" "${fixture_root}/.security-reports/dependency-freshness.json"
  [ "$status" -eq 0 ]
}

@test "R020: fails by default when any updates are available" {
  #R020
  local fixture_root
  fixture_root="$(mktemp -d)"
  create_go_stub "${fixture_root}"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" /bin/bash "${fixture_root}/02_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dependency updates detected"* ]]
}

@test "R020: allows updates when fail-on-updates is disabled" {
  #R020
  local fixture_root
  fixture_root="$(mktemp -d)"
  create_go_stub "${fixture_root}"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" DEPENDENCY_FAIL_ON_UPDATES=false DEPENDENCY_FAIL_ON_MAJOR=false /bin/bash "${fixture_root}/02_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
}
