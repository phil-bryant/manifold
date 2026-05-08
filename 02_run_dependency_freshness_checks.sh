#!/bin/bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Resolve repository root from script location so report and module paths are deterministic.
cd "$SCRIPT_DIR"

REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./.security-reports}"
GO_BIN="${DEPENDENCY_CHECK_GO_BIN:-go}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"
TEXT_REPORT="${REPORT_DIR}/dependency-freshness.txt"
JSON_REPORT="${REPORT_DIR}/dependency-freshness.json"
UPDATES_FILE="$(mktemp)"

major_from_version() {
  local version="$1"
  local normalized major
  normalized="${version#v}"
  major="${normalized%%.*}"
  if [[ -z "$major" ]]; then
    major="0"
  fi
  printf "%s" "$major"
}

#R005: Use configurable Go binary and fail fast when it is unavailable.
if ! command -v "$GO_BIN" >/dev/null 2>&1; then
  echo "❌ Go binary not found on PATH: ${GO_BIN}"
  exit 1
fi

mkdir -p "$REPORT_DIR"
echo "▶ Running Go dependency freshness checks with ${GO_BIN}"

#R010: Discover available module updates from go list and always emit a text artifact.
"$GO_BIN" list -m -u -f '{{if .Update}}{{.Path}} {{.Version}} {{.Update.Version}}{{end}}' all | awk 'NF>0' > "$UPDATES_FILE"
{
  echo "Manifold dependency freshness report"
  echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
} > "$TEXT_REPORT"

total_updates=0
major_updates=0
json_items=""
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path="$(awk '{print $1}' <<<"$line")"
  current="$(awk '{print $2}' <<<"$line")"
  latest="$(awk '{print $3}' <<<"$line")"
  current_major="$(major_from_version "$current")"
  latest_major="$(major_from_version "$latest")"
  is_major="false"
  if [[ "$latest_major" -gt "$current_major" ]]; then
    is_major="true"
    major_updates=$((major_updates + 1))
  fi
  total_updates=$((total_updates + 1))
  printf -- "- %s %s -> %s (major_update=%s)\n" "$path" "$current" "$latest" "$is_major" >> "$TEXT_REPORT"
  if [[ -n "$json_items" ]]; then
    json_items+=","
  fi
  json_items+="{\"path\":\"${path}\",\"current\":\"${current}\",\"latest\":\"${latest}\",\"major_update\":${is_major}}"
done < "$UPDATES_FILE"
if [[ "$total_updates" -eq 0 ]]; then
  echo "No updates available." >> "$TEXT_REPORT"
fi

#R015: Emit machine-readable JSON report with aggregate counts for CI and auditing.
{
  echo "{"
  echo "  \"generated_by\": \"02_run_dependency_freshness_checks.sh\","
  echo "  \"total_updates\": ${total_updates},"
  echo "  \"major_updates\": ${major_updates},"
  echo "  \"fail_on_major\": ${FAIL_ON_MAJOR},"
  echo "  \"modules\": [${json_items}]"
  echo "}"
} > "$JSON_REPORT"

status=0
#R020: Support optional major-version gating for CI freshness enforcement.
if [[ "$FAIL_ON_MAJOR" == "true" ]] && [[ "$major_updates" -gt 0 ]]; then
  echo "❌ Major dependency updates detected (${major_updates}) with DEPENDENCY_FAIL_ON_MAJOR=true"
  status=1
fi

#R025: Print concise operator-readable status with report locations and update counts.
echo "✅ Dependency freshness checks completed."
echo "   - text report: ${TEXT_REPORT}"
echo "   - json report: ${JSON_REPORT}"
echo "   - updates: ${total_updates}"
echo "   - major updates: ${major_updates}"
exit "$status"
