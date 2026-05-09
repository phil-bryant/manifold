# Ingest Validation Requirements

## Scope

Applies to `ingest/validate.go`.

R001  Statement: Validate batch envelope required fields.
Design: Require non-empty batch ID, RFC3339 sent-at value, and at least one event.
Tests:
- Omit each required batch field and verify validation error code/path.

R005  Statement: Enforce maximum events-per-batch limit.
Design: Reject batches whose event count exceeds configured maximum with deterministic error response metadata.
Tests:
- Submit batch above configured limit and verify too-many-events error.

R010  Statement: Validate event schema and identifier constraints.
Design: Require schema version 1, non-empty event ID, RFC3339 timestamp, allowed level, and valid event/component identifiers.
Tests:
- Submit invalid schema/version/identifier values and verify deterministic validation errors.

R015  Statement: Enforce per-event field and payload limits.
Design: Reject events exceeding field count, encoded event size, or max field string size constraints.
Tests:
- Submit oversized event payload/fields and verify validation rejection.

R020  Statement: Restrict field value types and deny sensitive keys.
Design: Allow only scalar field values and reject denylisted sensitive keys with path-aware validation errors.
Tests:
- Submit nested field values and denylisted keys and verify deterministic validation failures.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
