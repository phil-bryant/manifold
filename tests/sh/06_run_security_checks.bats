#!/usr/bin/env bats

load "helpers/common.bash"

make_semgrep_stub() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output" ]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[]}' > "$out"
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

make_gitleaks_stub() {
  local body="${1:-[]}"
  cat > "${STUB_BIN}/gitleaks" <<EOF
#!/usr/bin/env bash
report=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--report-path" ]; then
    report="\$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '${body}' > "\$report"
exit 0
EOF
  chmod +x "${STUB_BIN}/gitleaks"
}

make_gosec_stub() {
  local body="${1:-{\"Issues\":[]}}"
  cat > "${STUB_BIN}/gosec" <<EOF
#!/usr/bin/env bash
out=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-out" ]; then
    out="\$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '${body}' > "\$out"
exit 0
EOF
  chmod +x "${STUB_BIN}/gosec"
}

make_govulncheck_stub() {
  local payload="${1:-{}}"
  cat > "${STUB_BIN}/govulncheck" <<EOF
#!/usr/bin/env bash
printf '%s\n' '${payload}'
exit 0
EOF
  chmod +x "${STUB_BIN}/govulncheck"
}

make_curl_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/curl" <<EOF
#!/usr/bin/env bash
echo "ok"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/curl"
}

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "06_run_security_checks.sh"
}

setup() {
  setup_shell_test
  setup_fixture
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd and writes reports under script root" {
  #R001
  make_semgrep_stub
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/06_run_security_checks.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "fails fast with installer guidance when semgrep is missing" {
  #R005
  run env RUN_DAST=false PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: semgrep"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "does not run dependency freshness lane and emits no dependency artifacts" {
  #R010
  make_semgrep_stub
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.txt" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.json" ]
}

@test "writes all SAST scanner artifacts and summary" {
  #R015
  make_semgrep_stub
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/semgrep.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gitleaks.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gosec.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govulncheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "fails SAST gate when findings exist and fail-on-high is enabled" {
  #R020
  make_semgrep_stub
  make_gitleaks_stub '[{"RuleID":"secret"}]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
}

@test "runs DAST health probe and emits DAST artifacts" {
  #R025
  make_curl_stub 0
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-health.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-summary.json" ]
}

@test "fails DAST lane when health probe fails" {
  #R025
  make_curl_stub 1
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST health probe failed"* ]]
}

@test "prints final completion output with report path" {
  #R030
  make_semgrep_stub
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security checks completed. Reports:"* ]]
}
