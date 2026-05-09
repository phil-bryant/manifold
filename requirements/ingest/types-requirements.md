# Ingest Types Requirements

## Scope

Applies to `ingest/types.go`.

R001  Statement: Re-export core ingest payload model aliases.
Design: Expose ingest package aliases for batch request, event record, and persist result types from the model package.
Tests:
- Compile and use ingest aliases in handler/validation code paths.

R005  Statement: Define API response envelope with stable JSON fields.
Design: API response type includes accepted state, batch counters, error metadata, and optional path context with JSON tags.
Tests:
- Marshal/unmarshal response payload and verify expected fields.

R010  Statement: Define structured validation error type.
Design: Validation error carries machine-readable code and path with human-readable message returned by `Error()`.
Tests:
- Create validation error and verify error string output matches message.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
