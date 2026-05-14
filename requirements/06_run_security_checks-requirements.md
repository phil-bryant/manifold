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

R015  Statement: Run SAST scanners (including shell script linting and credential-pattern scanners) and persist machine-readable artifacts.
Design: Require `semgrep`, `shellcheck`, `gitleaks`, `detect-secrets`, `gosec`, and `govulncheck`; run `detect-secrets` with explicit file exclusion support (default excludes `.gomodcache` plus requirements markdown via `DETECT_SECRETS_EXCLUDE_FILES_REGEX` to prevent deterministic documentation-only false positives); write scanner outputs to `semgrep.json`, `shellcheck.json`, `gitleaks.json`, `detect-secrets.json`, `gosec.json`, and `govulncheck.json` under the report directory.
Tests:
- Run SAST lane with stubs and verify each expected scanner artifact file is generated.
- Verify `detect-secrets` invocation includes the default `.gomodcache` and requirements-doc exclusion regex.

R020  Statement: Aggregate SAST findings into a centralized gating summary.
Design: Build `sast-summary.json` from scanner outputs, include high/critical totals, count `detect-secrets` findings after applying the same exclusion regex policy used during scan invocation, and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and findings are non-zero.
Tests:
- Seed finding-producing scanner outputs and verify gate fails with explicit SAST gate message.
- Run with clean scanner outputs and verify `sast-summary.json` indicates gate pass.
- Verify findings under `.gomodcache` are excluded from detect-secrets gate totals while in-scope findings still fail the gate.

R025  Statement: Enable DAST by default while allowing explicit opt-out and deterministic local target boot.
Design: Default `RUN_DAST` to `true` and execute the DAST lane unless `RUN_DAST=false`; default `DAST_AUTO_BOOT=true` to launch `go run ./cmd/manifold` with `MANIFOLD_ADDR` derived from `DAST_BASE_URL`, require `1psa`, construct runtime `MANIFOLD_DATABASE_URL` directly from `localhost_postgres_manifold` fields `username`, `password`, `host`, and `port` (plus default db name `manifold`), and inject `MANIFOLD_INGEST_KEY` from `DAST_AUTO_BOOT_INGEST_KEY` (defaulting to `${MANIFOLD_INGEST_KEY:-local-ingest-key}`).
Tests:
- Run without setting `RUN_DAST` and verify DAST executes.
- Run with `RUN_DAST=false` and verify the lane is skipped with explicit skip output.
- Run with auto-boot enabled and verify `go run ./cmd/manifold` is invoked with DB URL injected from `1psa` fields and an ingest key environment value.

R030  Statement: Probe service health before launching DAST scanning.
Design: Require a successful `curl` probe to `${DAST_BASE_URL}/healthz`; when `DAST_AUTO_BOOT=true`, wait up to `DAST_AUTO_BOOT_TIMEOUT_SECONDS` for service readiness, write `dast-health.log`, and fail with explicit diagnostics when the probe fails.
Tests:
- Run DAST lane with failing `curl` stub and verify explicit non-zero failure output.
- Run DAST lane with passing `curl` and verify `dast-health.log` is created.
- Run DAST lane with auto-boot enabled and failing health probe and verify startup log diagnostics are printed.

R035  Statement: Execute OWASP ZAP baseline scans with deterministic runner fallback.
Design: Resolve host-native runner from PATH `zap-baseline.py` or ZAP CLI (`ZAP.sh`/`zap.sh`) under PATH/`ZAP_APP_PATH` (`/Applications/ZAP.app` by default), execute against `DAST_ZAP_TARGET_URL` (defaulting to `DAST_BASE_URL`) with bounded runtime via `DAST_ZAP_TIMEOUT_SECONDS`, and fail clearly when runner discovery, scanner execution, timeout, or report generation fails.
Tests:
- Run DAST lane with local `zap-baseline.py` stub and verify `dast-zap-report.json` is created.
- Run DAST lane without `zap-baseline.py` and without ZAP CLI and verify explicit missing-command failure output.
- Run DAST lane with ZAP CLI available only under `ZAP_APP_PATH` and verify scan invocation succeeds.

R040  Statement: Run Schemathesis contract testing and aggregate DAST findings into a centralized gating summary.
Design: When `RUN_SCHEMATHESIS=true`, execute `schemathesis run` against `SCHEMATHESIS_SCHEMA_PATH` and `${DAST_BASE_URL}`, emit `schemathesis.log` and `schemathesis-junit.xml`, and include Schemathesis result state in `dast-summary.json`; aggregate OWASP ZAP alerts scoped to `DAST_ZAP_TARGET_URL` host/port instances, allow configurable alert-ref suppression via `DAST_IGNORED_ALERT_REFS` (default includes known API-noise `10055-13` and ZAP daemon UI noise `10062`), and fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and unsuppressed in-scope medium/high alerts or Schemathesis contract failures are present.
Tests:
- Run DAST lane with clean scanner output and verify `dast-summary.json` indicates gate pass.
- Run DAST lane with medium/high scanner findings and verify explicit DAST gate failure output.
- Run DAST lane with only suppressed medium alert refs and verify gate pass.
- Run DAST lane with off-target alert instances and verify they are excluded from gate evaluation.
- Run DAST lane with Schemathesis contract failures and verify gate failure output.

R045  Statement: Emit explicit completion status and report location.
Design: Print lane completion markers and final success output with resolved report directory path.
Tests:
- Run with enabled lanes passing and verify final completion line includes `Reports:`.

R050  Statement: Emit live DAST execution context and progress visibility in console output.
Design: Before running OWASP ZAP, print the resolved runner identity, DAST timeout value, report artifact path, and dedicated live log artifact path; stream ZAP command output to console while simultaneously persisting it to `dast-zap.log` so operators can observe scan progress during execution.
Tests:
- Run DAST lane with stubs and verify console output includes runner resolution, timeout, report artifact, and live log artifact lines.
- Run DAST lane with ZAP CLI fallback and verify invocation includes `-quickprogress` and streamed output is captured in `dast-zap.log`.

## Changelog

- 2026-05-13: Added DAST auto-boot ingest key injection requirement and failure-log diagnostics expectation for health probe failures.
- 2026-05-10: Added default DAST suppression for ZAP daemon UI alert `10062` to avoid deterministic host-runner false positives.
- 2026-05-10: Added live ZAP progress streaming and `dast-zap.log` artifact requirements for DAST observability.
- 2026-05-10: Removed `MANIFOLD_DATABASE_URL_1PSA_REF` requirement for DAST auto-boot; DB URL is now composed directly from `localhost_postgres_manifold` fields.
- 2026-05-10: Added default detect-secrets exclusions for requirements markdown to avoid deterministic documentation-only false positives.
- 2026-05-10: Removed host/port env references for DAST auto-boot; host/port now come directly from `localhost_postgres_manifold` item fields.
- 2026-05-10: Updated DAST auto-boot to require dedicated `1psa` host/port references and apply them to the runtime Postgres DSN.
- 2026-05-10: Updated DAST auto-boot to require `1psa` + `MANIFOLD_DATABASE_URL_1PSA_REF` and resolve DB URL exclusively through `1psa read`.
- 2026-05-10: Added DAST auto-boot lifecycle for `go run ./cmd/manifold` and Schemathesis contract-testing integration.
- 2026-05-10: Added `detect-secrets` to step-06 SAST tooling, artifacts, and gate summary.
- 2026-05-10: Added explicit console observability requirement for live DAST execution context output.
- 2026-05-10: Added configurable DAST alert-ref suppression (`DAST_IGNORED_ALERT_REFS`) for known API-focused false positives.
- 2026-05-10: Added `ZAP_APP_PATH`-based discovery fallback for host-native `zap-baseline.py`.
- 2026-05-10: Split DAST requirements into granular execution, health-probe, scanner, and gate controls.
- 2026-05-09: Added `shellcheck` to step-06 SAST toolchain, artifacts, and gating summary inputs.
- 2026-05-09: Restored DAST lane in step-06 for server health probing and artifact generation.
- 2026-05-09: Updated step-06 requirements so DAST defaults to enabled with explicit `RUN_DAST=false` opt-out.
- 2026-05-09: Added Manifold step-06 security checks requirements with SAST/DAST lane policy and centralized gating.
- 2026-05-09: Expanded DAST lane to run health probe plus OWASP ZAP baseline scan with scanner-backed gating artifacts.
