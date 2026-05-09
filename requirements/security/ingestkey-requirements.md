# Ingest Key Security Requirements

## Scope

Applies to `security/ingestkey.go`.

R001  Statement: Build ingest-key validator from configured secret.
Design: Validator constructor stores expected key bytes for later authorization checks.
Tests:
- Build validator and confirm expected key authorizes successfully.

R005  Statement: Authorize with constant-time key comparison.
Design: Authorization compares provided and configured key values using constant-time byte comparison.
Tests:
- Verify valid and invalid keys return deterministic authorization outcome.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
