#!/usr/bin/env bats

load "helpers/common.bash"

setup_fixture() {
  create_repo_fixture
  copy_script_to_fixture "07_run_av_checks.sh"
}

setup() {
  setup_shell_test
  setup_fixture
}

teardown() {
  teardown_shell_test
}

make_clamscan_stub_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "Scanned files: 7"
echo "Infected files: 0"
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

make_clamscan_stub_infected() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "/tmp/eicar.txt: Win.Test.EICAR_HDB-1 FOUND"
echo "Scanned files: 5"
echo "Infected files: 1"
exit 1
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

make_clamscan_stub_exit_2() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "ERROR: scanner failed"
echo "Scanned files: 0"
echo "Infected files: 0"
exit 2
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

make_clamscan_stub_slow_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
sleep 2
echo "Scanned files: 11"
echo "Infected files: 0"
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

make_clamscan_stub_missing_db_then_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
state_file="${CLAMSCAN_STATE_FILE:?}"
if [ ! -f "$state_file" ]; then
  echo "No supported database files found in /var/lib/clamav"
  echo "Scanned files: 0"
  echo "Infected files: 0"
  touch "$state_file"
  exit 2
fi
echo "Scanned files: 9"
echo "Infected files: 0"
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

make_freshclam_stub_ok() {
  cat > "${STUB_BIN}/freshclam" <<'EOF'
#!/usr/bin/env bash
echo "freshclam $*" >> "${CALLS_LOG}"
echo "daily database available for download"
exit 0
EOF
  chmod +x "${STUB_BIN}/freshclam"
}

@test "runs from non-repo cwd and writes reports under script root" {
  #R001
  make_clamscan_stub_clean
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env RUN_CLAMAV=true RUN_DAST=false PATH="${PATH}" \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && bash '${FIXTURE_ROOT}/07_run_av_checks.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" ]
}

@test "fails fast with installer guidance when clamscan is missing" {
  #R005
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: clamscan"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "skips ClamAV lane when RUN_CLAMAV=false with deterministic artifacts" {
  #R010
  run env RUN_CLAMAV=false PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" ]
  run python3 - "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["skipped"] is True
assert payload["exit_code"] == 0
PY
  [ "$status" -eq 0 ]
}

@test "writes scanner artifacts and summary with clean scan output" {
  #R015 #R030
  make_clamscan_stub_clean
  run env PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" ]
  run python3 - "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["scanned_files"] == 7
assert payload["infected_files"] == 0
assert payload["gate_failed"] is False
PY
  [ "$status" -eq 0 ]
}

@test "prints signature freshness line before scan execution" {
  #R020
  make_clamscan_stub_clean
  run env PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV signature freshness:"* ]]
}

@test "prints freshclam guidance when signatures are stale" {
  #R020
  make_clamscan_stub_clean
  local db_dir="${TEST_TMPDIR}/clamdb"
  mkdir -p "$db_dir"
  run python3 - "$db_dir" <<'PY'
from pathlib import Path
import os
import sys
import time

db_dir = Path(sys.argv[1])
sig = db_dir / "main.cvd"
sig.write_text("stub", encoding="utf-8")
old = time.time() - (72 * 3600)
os.utime(sig, (old, old))
PY
  [ "$status" -eq 0 ]
  run env CLAMAV_DB_DIR="$db_dir" CLAMAV_SIGNATURE_MAX_AGE_HOURS=1 PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV signatures appear out of date"* ]]
  [[ "$output" == *"Refresh signatures with: freshclam --stdout"* ]]
}

@test "prints heartbeat progress while waiting for a slow scan" {
  #R025
  make_clamscan_stub_slow_clean
  run env CLAMAV_HEARTBEAT_SECONDS=1 CLAMAV_POLL_SECONDS=1 PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV scan in progress"* ]]
}

@test "fails gate when infected files are detected with fail-on-high enabled" {
  #R030
  make_clamscan_stub_infected
  run env SECURITY_FAIL_ON_HIGH_CRITICAL=true PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV detected infected files"* ]]
  [[ "$output" == *"Antivirus (ClamAV) gate failed"* ]]
}

@test "fails clearly when configured scan target does not exist" {
  #R035
  make_clamscan_stub_clean
  run env CLAMAV_SCAN_TARGET="./does-not-exist" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV scan target not found"* ]]
}

@test "refreshes signatures once and retries when database files are missing" {
  #R040
  make_clamscan_stub_missing_db_then_clean
  make_freshclam_stub_ok
  export CLAMSCAN_STATE_FILE="${TEST_TMPDIR}/clamscan.state"
  run env CLAMSCAN_STATE_FILE="${CLAMSCAN_STATE_FILE}" PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attempting one-time database refresh with freshclam --stdout"* ]]
  [[ "$output" == *"Retrying ClamAV repository scan"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "freshclam --stdout" in text
PY
  [ "$status" -eq 0 ]
}

@test "fails on execution error when clamscan exits greater than one" {
  #R045
  make_clamscan_stub_exit_2
  run env PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV failed to execute."* ]]
}

@test "prints deterministic final completion output with report path" {
  #R050
  make_clamscan_stub_clean
  run env PATH="${PATH}" \
    bash "${FIXTURE_ROOT}/07_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AV checks completed. Reports:"* ]]
}
