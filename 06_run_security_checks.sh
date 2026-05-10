#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-true}"
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
DAST_BASE_URL="${DAST_BASE_URL:-http://127.0.0.1:8080}"
DAST_ZAP_TARGET_URL="${DAST_ZAP_TARGET_URL:-${DAST_BASE_URL}}"
ZAP_APP_PATH="${ZAP_APP_PATH:-/Applications/ZAP.app}"
DAST_IGNORED_ALERT_REFS="${DAST_IGNORED_ALERT_REFS:-10055-13}"
DAST_HEALTH_PROBE_TIMEOUT_SECONDS="${DAST_HEALTH_PROBE_TIMEOUT_SECONDS:-5}"
DAST_ZAP_TIMEOUT_SECONDS="${DAST_ZAP_TIMEOUT_SECONDS:-180}"

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${SCRIPT_DIR}/${REPORT_DIR#./}"
fi

mkdir -p "$REPORT_DIR"

require_command() {
  local command_name="$1"
  #R005: Fail fast with installer guidance when a required command is missing.
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

print_tool_header() {
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Security Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
}

resolve_zap_baseline() {
  if command -v zap-baseline.py >/dev/null 2>&1; then
    echo "zap-baseline.py"
    return 0
  fi
  if [[ ! -d "${ZAP_APP_PATH}" ]]; then
    return 1
  fi
  python3 - "${ZAP_APP_PATH}" <<'PY'
import os
import sys

zap_app_path = sys.argv[1]
candidates = [
    os.path.join(zap_app_path, "Contents", "Resources", "zap-baseline.py"),
    os.path.join(zap_app_path, "Contents", "Java", "zap-baseline.py"),
    os.path.join(zap_app_path, "Contents", "Java", "scripts", "zap-baseline.py"),
]
for candidate in candidates:
    if os.path.isfile(candidate):
        print(candidate)
        raise SystemExit(0)
for root, _dirs, files in os.walk(zap_app_path):
    if "zap-baseline.py" in files:
        print(os.path.join(root, "zap-baseline.py"))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_zap_cli() {
  local candidate=""
  if command -v ZAP.sh >/dev/null 2>&1; then
    echo "ZAP.sh"
    return 0
  fi
  if command -v zap.sh >/dev/null 2>&1; then
    echo "zap.sh"
    return 0
  fi
  candidate="${ZAP_APP_PATH}/Contents/MacOS/ZAP.sh"
  if [[ -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi
  candidate="${ZAP_APP_PATH}/Contents/Java/zap.sh"
  if [[ -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi
  return 1
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
command = sys.argv[2:]
if timeout_seconds <= 0:
    timeout_seconds = 1

proc = subprocess.Popen(command, preexec_fn=os.setsid)
try:
    proc.wait(timeout=timeout_seconds)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    raise SystemExit(124)
PY
}

run_sast_lane() {
  #R015: Run Go-focused SAST scanners and persist machine-readable artifacts.
  if [[ "$RUN_SAST" != "true" ]]; then
    echo "ℹ️  SAST lane skipped."
    return 0
  fi

  require_command semgrep
  require_command shellcheck
  require_command gitleaks
  require_command gosec
  require_command govulncheck
  require_command python3

  echo "▶ Running SAST lane"

  print_tool_header \
    "Semgrep" \
    "Static pattern-based scanning for security and correctness issues." \
    "Uses curated security and Go rules against the repository source tree." \
    "https://semgrep.dev/docs/"
  echo "▶ Running Semgrep"
  semgrep scan \
    --config "p/security-audit" \
    --config "p/golang" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

  print_tool_header \
    "ShellCheck" \
    "Static linting for shell scripts with security and reliability checks." \
    "Flags risky shell patterns, quoting bugs, and execution pitfalls." \
    "https://www.shellcheck.net/"
  echo "▶ Running ShellCheck"
  set +e
  shellcheck \
    --format json \
    --external-sources \
    --source-path SCRIPTDIR \
    ./*.sh > "${REPORT_DIR}/shellcheck.json"
  SHELLCHECK_EXIT=$?
  set -e
  if [[ "$SHELLCHECK_EXIT" -gt 1 ]]; then
    echo "❌ shellcheck failed to execute."
    exit 1
  fi

  print_tool_header \
    "Gitleaks" \
    "Scans repository content for hard-coded secrets and credentials." \
    "Detects leaked tokens, keys, and other sensitive data patterns." \
    "https://github.com/gitleaks/gitleaks"
  echo "▶ Running Gitleaks"
  set +e
  gitleaks detect \
    --no-banner \
    --report-format json \
    --report-path "${REPORT_DIR}/gitleaks.json"
  GITLEAKS_EXIT=$?
  set -e
  if [[ "$GITLEAKS_EXIT" -gt 1 ]]; then
    echo "❌ gitleaks failed to execute."
    exit 1
  fi

  print_tool_header \
    "gosec" \
    "Static security analyzer focused on vulnerable Go code patterns." \
    "Surfaces risky API usage and common implementation weaknesses." \
    "https://github.com/securego/gosec"
  echo "▶ Running gosec"
  set +e
  gosec \
    -fmt=json \
    -exclude-dir=.gomodcache \
    -out "${REPORT_DIR}/gosec.json" \
    ./...
  GOSEC_EXIT=$?
  set -e
  if [[ "$GOSEC_EXIT" -gt 1 ]]; then
    echo "❌ gosec failed to execute."
    exit 1
  fi

  print_tool_header \
    "govulncheck" \
    "Go vulnerability scanner mapped to known ecosystem advisories." \
    "Evaluates project modules and reachable vulnerable symbols." \
    "https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck"
  echo "▶ Running govulncheck"
  set +e
  govulncheck -json ./... > "${REPORT_DIR}/govulncheck.json"
  GOVULNCHECK_EXIT=$?
  set -e
  if [[ "$GOVULNCHECK_EXIT" -gt 1 ]] && [[ ! -s "${REPORT_DIR}/govulncheck.json" ]]; then
    echo "❌ govulncheck failed to execute."
    exit 1
  fi

  #R020: Aggregate SAST findings into a centralized gate summary.
  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_HIGH_CRITICAL}" "${SHELLCHECK_EXIT}" "${GITLEAKS_EXIT}" "${GOSEC_EXIT}" "${GOVULNCHECK_EXIT}"
import json
import re
import sys
from pathlib import Path
from typing import Any

report_dir = Path(sys.argv[1])
fail_on_high = sys.argv[2].lower() == "true"
shellcheck_exit = int(sys.argv[3])
gitleaks_exit = int(sys.argv[4])
gosec_exit = int(sys.argv[5])
govulncheck_exit = int(sys.argv[6])

semgrep_path = report_dir / "semgrep.json"
shellcheck_path = report_dir / "shellcheck.json"
gitleaks_path = report_dir / "gitleaks.json"
gosec_path = report_dir / "gosec.json"
govulncheck_path = report_dir / "govulncheck.json"

for required in [semgrep_path, shellcheck_path, gitleaks_path, gosec_path, govulncheck_path]:
    if not required.exists():
        print(f"Missing report file: {required}")
        sys.exit(1)

def load_first_json(path: Path, fallback: Any) -> Any:
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return fallback
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        try:
            parsed, _idx = decoder.raw_decode(text)
            return parsed
        except json.JSONDecodeError:
            return fallback

semgrep = load_first_json(semgrep_path, {"results": []})
semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
semgrep_high = sum(
    1
    for item in semgrep_results
    if str(item.get("extra", {}).get("severity", "")).upper() in {"CRITICAL", "ERROR", "HIGH"}
)

shellcheck = load_first_json(shellcheck_path, [])
if isinstance(shellcheck, list):
    shellcheck_high = sum(
        1
        for issue in shellcheck
        if str(issue.get("level", "")).lower() in {"error", "warning"}
    )
elif isinstance(shellcheck, dict) and isinstance(shellcheck.get("comments"), list):
    shellcheck_high = sum(
        1
        for issue in shellcheck.get("comments", [])
        if str(issue.get("level", "")).lower() in {"error", "warning"}
    )
else:
    shellcheck_high = 0

gitleaks = load_first_json(gitleaks_path, [])
if isinstance(gitleaks, list):
    gitleaks_findings = len(gitleaks)
elif isinstance(gitleaks, dict) and isinstance(gitleaks.get("findings"), list):
    gitleaks_findings = len(gitleaks.get("findings", []))
else:
    gitleaks_findings = 0

gosec = load_first_json(gosec_path, {"Issues": []})
issues = gosec.get("Issues", []) if isinstance(gosec, dict) else []
gosec_high = sum(1 for issue in issues if str(issue.get("severity", "")).upper() in {"HIGH", "MEDIUM"})

govulncheck_text = govulncheck_path.read_text(encoding="utf-8", errors="replace")
govulncheck_findings = len(re.findall(r'"finding"\s*:', govulncheck_text))

high_critical_total = shellcheck_high + semgrep_high + gitleaks_findings + gosec_high + govulncheck_findings
summary = {
    "shellcheck_high_critical": shellcheck_high,
    "semgrep_high_critical": semgrep_high,
    "gitleaks_findings": gitleaks_findings,
    "gosec_high_critical": gosec_high,
    "govulncheck_findings": govulncheck_findings,
    "shellcheck_exit_code": shellcheck_exit,
    "gitleaks_exit_code": gitleaks_exit,
    "gosec_exit_code": gosec_exit,
    "govulncheck_exit_code": govulncheck_exit,
    "high_critical_total": high_critical_total,
    "gate_failed": fail_on_high and high_critical_total > 0,
}

summary_path = report_dir / "sast-summary.json"
with summary_path.open("w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")

print("Static Application Security Testing (SAST) summary")
print(json.dumps(summary, indent=2))
if fail_on_high and high_critical_total > 0:
    print("❌ Static Application Security Testing (SAST) gate failed: High/Critical findings detected.")
    sys.exit(1)
PY
  echo "✅ Static Application Security Testing (SAST) checks completed."
}

run_dast_lane() {
  #R025: Run DAST lane by default unless explicitly opted out.
  if [[ "$RUN_DAST" != "true" ]]; then
    echo "ℹ️  DAST lane skipped."
    return 0
  fi

  require_command curl
  require_command python3
  local zap_runner_cmd=""
  local zap_runner_mode=""
  if zap_runner_cmd="$(resolve_zap_baseline)"; then
    zap_runner_mode="baseline"
  elif zap_runner_cmd="$(resolve_zap_cli)"; then
    zap_runner_mode="cli"
  else
    echo "❌ Missing required command: zap-baseline.py or ZAP.sh"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    echo "If ZAP.app is installed elsewhere, set ZAP_APP_PATH and rerun."
    exit 1
  fi

  #R030: Probe /healthz before launching dynamic scanning.
  print_tool_header \
    "curl" \
    "HTTP health probe to validate target service availability." \
    "Confirms /healthz is reachable before dynamic scanning starts." \
    "https://curl.se/"
  echo "▶ Running DAST lane health probe against ${DAST_BASE_URL}"
  set +e
  run_with_timeout "${DAST_HEALTH_PROBE_TIMEOUT_SECONDS}" \
    curl -fsS --max-time "${DAST_HEALTH_PROBE_TIMEOUT_SECONDS}" "${DAST_BASE_URL}/healthz" > "${REPORT_DIR}/dast-health.log"
  DAST_HEALTH_EXIT=$?
  set -e
  if [[ "$DAST_HEALTH_EXIT" -eq 124 ]]; then
    echo "❌ DAST health probe timed out after ${DAST_HEALTH_PROBE_TIMEOUT_SECONDS}s: ${DAST_BASE_URL}/healthz"
    exit 1
  fi
  if [[ "$DAST_HEALTH_EXIT" -ne 0 ]]; then
    echo "❌ DAST health probe failed: ${DAST_BASE_URL}/healthz"
    exit 1
  fi

  #R035: Execute OWASP ZAP baseline via host-native zap-baseline.py.
  local zap_target_url="${DAST_ZAP_TARGET_URL}"

  print_tool_header \
    "OWASP ZAP Baseline" \
    "Dynamic web scanner for common HTTP application vulnerabilities." \
    "Runs baseline scan mode and emits JSON alert report artifacts." \
    "https://www.zaproxy.org/"
  echo "▶ Running real DAST scan with OWASP ZAP baseline against ${zap_target_url}"
  local zap_report_path="${REPORT_DIR}/dast-zap-report.json"
  local zap_exit=0
  set +e
  if [[ "${zap_runner_mode}" == "baseline" && "${zap_runner_cmd}" == "zap-baseline.py" ]]; then
    run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
      zap-baseline.py \
      -t "${zap_target_url}" \
      -J "${zap_report_path}" \
      -m 1
    zap_exit=$?
  elif [[ "${zap_runner_mode}" == "baseline" ]]; then
    run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
      python3 "${zap_runner_cmd}" \
      -t "${zap_target_url}" \
      -J "${zap_report_path}" \
      -m 1
    zap_exit=$?
  else
    run_with_timeout "${DAST_ZAP_TIMEOUT_SECONDS}" \
      "${zap_runner_cmd}" \
      -cmd \
      -quickurl "${zap_target_url}" \
      -quickout "${zap_report_path}"
    zap_exit=$?
  fi
  set -e

  if [[ "$zap_exit" -eq 124 ]]; then
    echo "❌ OWASP ZAP baseline scan timed out after ${DAST_ZAP_TIMEOUT_SECONDS}s."
    exit 1
  fi
  if [[ "$zap_exit" -eq 3 ]]; then
    echo "❌ OWASP ZAP baseline scan failed to execute."
    exit 1
  fi
  if [[ ! -s "${zap_report_path}" ]]; then
    echo "❌ OWASP ZAP baseline report was not generated."
    exit 1
  fi

  #R040: Summarize DAST findings and enforce medium/high gate policy.
  python3 - <<'PY' "${REPORT_DIR}/dast-summary.json" "${DAST_BASE_URL}" "${zap_target_url}" "${zap_report_path}" "${FAIL_ON_HIGH_CRITICAL}" "${zap_exit}" "${DAST_IGNORED_ALERT_REFS}"
import json
import sys
from urllib.parse import urlparse

summary_path = sys.argv[1]
base_url = sys.argv[2]
zap_target = sys.argv[3]
zap_report_path = sys.argv[4]
fail_on_high = sys.argv[5].lower() == "true"
zap_exit = int(sys.argv[6])
ignored_alert_refs = {value.strip() for value in sys.argv[7].split(",") if value.strip()}

def load_first_json(path: str):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read().strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        parsed, _idx = decoder.raw_decode(text)
        return parsed

zap_report = load_first_json(zap_report_path)

sites = zap_report.get("site", []) if isinstance(zap_report, dict) else []
alerts = []
for site in sites:
    if isinstance(site, dict):
        site_alerts = site.get("alerts", [])
        if isinstance(site_alerts, list):
            alerts.extend(site_alerts)

target = urlparse(zap_target)
target_host = (target.hostname or "").lower()
target_port = target.port or (443 if target.scheme.lower() == "https" else 80)

def is_target_scoped(alert):
    instances = alert.get("instances", [])
    if not isinstance(instances, list) or not instances:
        return True
    for instance in instances:
        if not isinstance(instance, dict):
            continue
        uri = str(instance.get("uri", "")).strip()
        if not uri:
            continue
        parsed = urlparse(uri)
        host = (parsed.hostname or "").lower()
        port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80)
        if host == target_host and port == target_port:
            return True
    return False

scoped_alerts = [alert for alert in alerts if is_target_scoped(alert)]

filtered_alerts = [
    alert for alert in scoped_alerts
    if str(alert.get("alertRef", "")).strip() not in ignored_alert_refs
]

high_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "3")
medium_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "2")
low_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "1")
info_count = sum(1 for alert in filtered_alerts if str(alert.get("riskcode", "")) == "0")
total_alerts = len(alerts)
scoped_total = len(scoped_alerts)
ignored_alerts = scoped_total - len(filtered_alerts)
out_of_scope_alerts = total_alerts - scoped_total
gate_failed = fail_on_high and (high_count + medium_count > 0)

payload = {
    "health_probe_target": base_url,
    "zap_target": zap_target,
    "zap_report": zap_report_path,
    "zap_exit_code": zap_exit,
    "zap_alerts": {
        "high": high_count,
        "medium": medium_count,
        "low": low_count,
        "info": info_count,
        "total": total_alerts,
        "scoped_total": scoped_total,
        "ignored": ignored_alerts,
        "out_of_scope_ignored": out_of_scope_alerts,
    },
    "ignored_alert_refs": sorted(ignored_alert_refs),
    "healthz_passed": True,
    "gate_failed": gate_failed,
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
print("Dynamic Application Security Testing (DAST) summary")
print(json.dumps(payload, indent=2))
if gate_failed:
    print("❌ Dynamic Application Security Testing (DAST) gate failed: Medium/High alerts detected.")
    sys.exit(1)
PY
  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
}

#R010: Keep security checks scoped to SAST/DAST so step-02 remains independent.
run_sast_lane
run_dast_lane

#R045: Emit explicit completion status and report location.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
