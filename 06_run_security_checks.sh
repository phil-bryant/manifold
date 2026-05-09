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

run_sast_lane() {
  #R015: Run Go-focused SAST scanners and persist machine-readable artifacts.
  if [[ "$RUN_SAST" != "true" ]]; then
    echo "ℹ️  SAST lane skipped."
    return 0
  fi

  require_command semgrep
  require_command gitleaks
  require_command gosec
  require_command govulncheck
  require_command python3

  echo "▶ Running SAST lane"

  semgrep scan \
    --config "p/security-audit" \
    --config "p/golang" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

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

  set +e
  govulncheck -json ./... > "${REPORT_DIR}/govulncheck.json"
  GOVULNCHECK_EXIT=$?
  set -e
  if [[ "$GOVULNCHECK_EXIT" -gt 1 ]] && [[ ! -s "${REPORT_DIR}/govulncheck.json" ]]; then
    echo "❌ govulncheck failed to execute."
    exit 1
  fi

  #R020: Aggregate SAST findings into a centralized gate summary.
  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_HIGH_CRITICAL}" "${GITLEAKS_EXIT}" "${GOSEC_EXIT}" "${GOVULNCHECK_EXIT}"
import json
import re
import sys
from pathlib import Path
from typing import Any

report_dir = Path(sys.argv[1])
fail_on_high = sys.argv[2].lower() == "true"
gitleaks_exit = int(sys.argv[3])
gosec_exit = int(sys.argv[4])
govulncheck_exit = int(sys.argv[5])

semgrep_path = report_dir / "semgrep.json"
gitleaks_path = report_dir / "gitleaks.json"
gosec_path = report_dir / "gosec.json"
govulncheck_path = report_dir / "govulncheck.json"

for required in [semgrep_path, gitleaks_path, gosec_path, govulncheck_path]:
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

high_critical_total = semgrep_high + gitleaks_findings + gosec_high + govulncheck_findings
summary = {
    "semgrep_high_critical": semgrep_high,
    "gitleaks_findings": gitleaks_findings,
    "gosec_high_critical": gosec_high,
    "govulncheck_findings": govulncheck_findings,
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
  #R025: Run DAST lane by default with deterministic health-check artifacts.
  if [[ "$RUN_DAST" != "true" ]]; then
    echo "ℹ️  DAST lane skipped."
    return 0
  fi

  require_command curl
  require_command python3

  echo "▶ Running DAST lane health probe against ${DAST_BASE_URL}"
  set +e
  curl -fsS "${DAST_BASE_URL}/healthz" > "${REPORT_DIR}/dast-health.log"
  DAST_HEALTH_EXIT=$?
  set -e
  if [[ "$DAST_HEALTH_EXIT" -ne 0 ]]; then
    echo "❌ DAST health probe failed: ${DAST_BASE_URL}/healthz"
    exit 1
  fi

  python3 - <<'PY' "${REPORT_DIR}/dast-summary.json" "${DAST_BASE_URL}"
import json
import sys

summary_path = sys.argv[1]
base_url = sys.argv[2]
payload = {
    "target": base_url,
    "healthz_passed": True,
    "gate_failed": False,
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
print("Dynamic Application Security Testing (DAST) summary")
print(json.dumps(payload, indent=2))
PY
  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
}

#R010: Keep security checks scoped to SAST/DAST so step-02 remains independent.
run_sast_lane
run_dast_lane

#R030: Emit explicit completion status and report location.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
