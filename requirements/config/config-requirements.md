# Runtime Config Requirements

## Scope

Applies to `config/config.go`.

R001  Statement: Require core ingest and database configuration.
Design: Config loading fails when ingest key or database URL environment variables are missing.
Tests:
- Load config without required variables and verify non-nil error.

R005  Statement: Apply deterministic defaults for optional settings.
Design: Populate default address and ingestion limit values when optional environment variables are unset.
Tests:
- Load config with only required variables and verify defaults.

R010  Statement: Validate positive numeric limit configuration.
Design: Reject malformed or non-positive numeric values for body/event/field limits.
Tests:
- Set invalid numeric value for each positive limit and verify error.

R015  Statement: Validate non-negative request-rate configuration.
Design: Reject malformed or negative request-rate values while allowing zero as disabled rate limiting.
Tests:
- Set invalid and negative request-rate values and verify error.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
