---
name: Fix DAST Gate Reliability
overview: Make DAST deterministic by removing ZAP/app port contention and align Schemathesis with the intended API contract by tightening the OpenAPI schema for batch ingest payloads.
todos:
  - id: dast-port-separation
    content: Refactor DAST runner defaults and preflight checks to prevent app/ZAP port conflicts
    status: completed
  - id: openapi-batch-tightening
    content: Tighten OpenAPI batch ingest schema to prevent malformed generated payloads
    status: completed
  - id: regen-api-bindings
    content: Regenerate internal OpenAPI bindings and verify handler compatibility
    status: completed
  - id: security-runner-tests
    content: Update BATS coverage for new DAST port behavior and contract expectations
    status: completed
  - id: full-security-validation
    content: Run full security script and verify clean DAST/SAST summary artifacts
    status: completed
isProject: false
---

# Fix DAST Gate Reliability

## Goals
- Eliminate OWASP ZAP startup flakiness caused by local port collisions.
- Resolve Schemathesis contract failure for `POST /v1/events/batch` by tightening the OpenAPI schema (per your preference).
- Keep security gates strict while reducing false negatives/false positives from tooling setup issues.

## Targeted Changes
- Update the DAST runner in [`06_run_security_checks.sh`](06_run_security_checks.sh) to use explicit, non-conflicting defaults for app bind URL vs scanner infrastructure.
  - Introduce a dedicated default app URL/port for auto-booted DAST target (non-8080).
  - Ensure health probe, Schemathesis `--url`, and ZAP target all use that same target URL consistently.
  - Keep overrides via env vars so CI/local can still customize.
- Add preflight guardrails in [`06_run_security_checks.sh`](06_run_security_checks.sh):
  - Validate target port availability before boot.
  - Emit actionable diagnostics when a required port is already occupied.
  - Keep deterministic cleanup semantics for auto-booted processes.
- Tighten request schema for the batch endpoint in [`openapi/manifold.v1.yaml`](openapi/manifold.v1.yaml):
  - Constrain fields that currently let Schemathesis produce borderline payload shapes that decode as `invalid_json` in server paths.
  - Preserve intended valid payload flexibility while making malformed structures unrepresentable at schema level.
- Regenerate API bindings from the updated spec in [`internal/apiv1gen`](internal/apiv1gen) so runtime contract and generated validators stay aligned.
- Confirm server-side request handling remains consistent in [`httpserver/server.go`](httpserver/server.go) and [`ingest/handler.go`](ingest/handler.go) after schema tightening (no behavior drift for legitimate clients).
- Update/extend shell tests in [`tests/sh/06_run_security_checks.bats`](tests/sh/06_run_security_checks.bats) to lock in:
  - Port-separation behavior and diagnostics.
  - Expected DAST lane behavior when Schemathesis passes/fails.

## Validation Plan
- Run focused shell tests for the security runner (`bats tests/sh/06_run_security_checks.bats`).
- Run `./06_run_security_checks.sh` end-to-end and verify:
  - ZAP no longer exits with bind errors.
  - Schemathesis no longer fails on the prior batch-ingest case.
  - `dast-summary.json` reflects true security findings rather than setup failures.
- Re-run unit/integration checks that cover ingest and HTTP request handling.

## Implementation Notes
- Keep gate logic intact (`schemathesis_exit_code==1` should still fail DAST); fix should come from contract/schema correctness, not weakening policy.
- Ensure default port changes remain backward-compatible via environment variable overrides documented in script output/help text.