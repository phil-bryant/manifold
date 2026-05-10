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

make_shellcheck_stub() {
  local body="${1:-[]}"
  cat > "${STUB_BIN}/shellcheck" <<EOF
#!/usr/bin/env bash
printf '%s' '${body}'
exit 0
EOF
  chmod +x "${STUB_BIN}/shellcheck"
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
if [ -n "\${GOSEC_EXPECT_ARGS_CONTAIN:-}" ]; then
  case " \$* " in
    *"\${GOSEC_EXPECT_ARGS_CONTAIN}"*) ;;
    *)
      echo "missing expected gosec arg: \${GOSEC_EXPECT_ARGS_CONTAIN}" >&2
      exit 2
      ;;
  esac
fi
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

make_zap_baseline_stub() {
  local report_body="${1:-{\"site\":[{\"alerts\":[]}]}}"
  local exit_code="${2:-0}"
  cat > "${STUB_BIN}/zap-baseline.py" <<EOF
#!/usr/bin/env bash
report=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-J" ]; then
    report="\$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '${report_body}' > "\$report"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/zap-baseline.py"
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
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
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

@test "fails fast with installer guidance when shellcheck is missing" {
  #R005
  make_semgrep_stub
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: shellcheck"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "does not run dependency freshness lane and emits no dependency artifacts" {
  #R010
  make_semgrep_stub
  make_shellcheck_stub '[]'
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
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/semgrep.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/shellcheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gitleaks.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gosec.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/govulncheck.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/sast-summary.json" ]
}

@test "fails SAST gate when findings exist and fail-on-high is enabled" {
  #R020
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[{"RuleID":"secret"}]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST) gate failed"* ]]
}

@test "invokes gosec with gomodcache excluded" {
  #R015
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false GOSEC_EXPECT_ARGS_CONTAIN="-exclude-dir=.gomodcache" PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "runs DAST health probe and emits DAST artifacts by default" {
  #R025 #R030 #R035 #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-health.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap-report.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-summary.json" ]
}

@test "skips DAST lane only when explicitly opted out" {
  #R025
  run env RUN_SAST=false RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST lane skipped."* ]]
}

@test "fails DAST lane when health probe fails" {
  #R030
  make_curl_stub 1
  make_zap_baseline_stub '{"site":[{"alerts":[]}]}' 0
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST health probe failed"* ]]
}

@test "fails DAST gate when zap reports medium/high alerts" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"2","alertRef":"00000","instances":[{"uri":"http://127.0.0.1:8080/risky"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DAST) gate failed"* ]]
}

@test "ignores configured DAST alert refs during gate evaluation" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"2","alertRef":"10055-13","instances":[{"uri":"http://127.0.0.1:8080/known-noise"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DAST) summary"* || "$output" == *"DAST) checks completed."* ]]
}

@test "ignores out-of-scope DAST alerts for gate evaluation" {
  #R040
  make_curl_stub 0
  make_zap_baseline_stub '{"site":[{"alerts":[{"riskcode":"3","alertRef":"90000","instances":[{"uri":"http://127.0.0.1:9999/off-target"}]}]}]}' 1
  run env RUN_SAST=false RUN_DAST=true PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
}

@test "fails DAST lane when no ZAP runner is available" {
  #R035
  make_curl_stub 0
  run env RUN_SAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" ZAP_APP_PATH="${TEST_TMPDIR}/missing-zap-app" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command: zap-baseline.py or ZAP.sh"* ]]
}

@test "runs DAST lane when ZAP.sh is discovered via ZAP_APP_PATH" {
  #R035
  make_curl_stub 0
  local zap_app_path="${TEST_TMPDIR}/Applications/ZAP.app"
  mkdir -p "${zap_app_path}/Contents/MacOS"
  cat > "${zap_app_path}/Contents/MacOS/ZAP.sh" <<'EOF'
#!/usr/bin/env bash
report=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-quickout" ] && [ "$#" -ge 2 ]; then
    report="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"site":[{"alerts":[]}]}' > "$report"
exit 0
EOF
  chmod +x "${zap_app_path}/Contents/MacOS/ZAP.sh"
  run env RUN_SAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" ZAP_APP_PATH="${zap_app_path}" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dast-zap-report.json" ]
}

@test "prints final completion output with report path" {
  #R045
  make_semgrep_stub
  make_shellcheck_stub '[]'
  make_gitleaks_stub '[]'
  make_gosec_stub '{"Issues":[]}'
  make_govulncheck_stub '{}'
  run env RUN_DAST=false PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/06_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security checks completed. Reports:"* ]]
}
