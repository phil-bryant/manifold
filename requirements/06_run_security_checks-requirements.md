# Run Security Checks Requirements

## Scope

Applies to `06_run_security_checks.sh`.

R001  Statement: Run security checks in strict fail-fast mode from repository root.
Design: Use `bash` strict mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory before lane execution.
Tests:
- Run from a non-repo working directory and verify report output still resolves relative to repository root.

R005  Statement: Fail fast when required tools are missing with actionable install guidance.
Design: Validate required commands before each lane and print `./01_install_prerequisites.sh` guidance when a command is unavailable.
Tests:
- Run SAST lane with missing `semgrep` and verify non-zero failure plus installer guidance output.

R010  Statement: Keep step-06 security checks independent from dependency freshness checks.
Design: Do not invoke `./02_run_dependency_freshness_checks.sh` from step-06; run only SAST and optional DAST lanes within `06_run_security_checks.sh`.
Tests:
- Run step-06 when `02_run_dependency_freshness_checks.sh` is absent and verify SAST execution still succeeds.
- Verify no dependency freshness artifacts are emitted by step-06.

R015  Statement: Run Go-focused SAST scanners and persist machine-readable artifacts.
Design: Require `semgrep`, `gitleaks`, `gosec`, and `govulncheck`; write scanner outputs to `semgrep.json`, `gitleaks.json`, `gosec.json`, and `govulncheck.json` under the report directory.
Tests:
- Run SAST lane with stubs and verify each expected scanner artifact file is generated.

R020  Statement: Aggregate SAST findings into a centralized gating summary.
Design: Build `sast-summary.json` from scanner outputs, include high/critical totals, and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and findings are non-zero.
Tests:
- Seed finding-producing scanner outputs and verify gate fails with explicit SAST gate message.
- Run with clean scanner outputs and verify `sast-summary.json` indicates gate pass.

R025  Statement: Support optional DAST lane with deterministic health-probe artifacts.
Design: When `RUN_DAST=true`, probe `${DAST_BASE_URL}/healthz` via `curl`, write `dast-health.log`, emit `dast-summary.json`, and fail clearly when the probe fails.
Tests:
- Run DAST lane with passing `curl` stub and verify `dast-health.log` + `dast-summary.json` are created.
- Run DAST lane with failing `curl` stub and verify explicit non-zero failure output.

R030  Statement: Emit explicit completion status and report location.
Design: Print lane completion markers and final success output with resolved report directory path.
Tests:
- Run with enabled lanes passing and verify final completion line includes `Reports:`.

## Changelog

- 2026-05-09: Added Manifold step-06 security checks requirements with SAST/DAST lane policy and centralized gating.
