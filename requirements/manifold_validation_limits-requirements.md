# Manifold Validation And Limits Requirements

## Scope

Requirements-only mode: true.
Defines validation and payload-limit behavior for future files `internal/ingest/types.go`, `internal/ingest/validate.go`, and `internal/ingest/handler.go`.

R001  Statement: Validate batch envelope fields before persistence.
Design: Require non-empty `batch_id`, parseable `sent_at`, and non-empty `events` array.
Tests:
- Omit each required batch field and verify `422 invalid_schema`.

R005  Statement: Validate event required fields and supported enum values.
Design: Require `schema_version=1`, non-empty `event_id`, parseable `timestamp`, allowed `level`, and stable identifiers for `event` and `component`.
Tests:
- Send invalid schema version, level, and identifier format and verify `422`.

R010  Statement: Enforce request body size limit.
Design: Cap body bytes with configurable max; reject oversized payloads with `413 payload_too_large`.
Tests:
- Submit payload above configured max and verify `413`.

R015  Statement: Enforce max events per batch.
Design: Reject batches where `len(events)` exceeds configured limit with `422 too_many_events` or `413` per configured policy.
Tests:
- Submit `max+1` events and verify deterministic rejection.

R020  Statement: Enforce per-event payload size and field count limits.
Design: Reject events exceeding configured event-size limit or `fields` key-count limit.
Tests:
- Submit event larger than max bytes and verify rejection.
- Submit event with fields count over limit and verify rejection.

R025  Statement: Restrict field value types and nested structures in v1.
Design: Accept only scalar JSON values (`string`, `number`, `boolean`, `null`) in `fields`; reject nested arrays/objects.
Tests:
- Submit nested object or array in `fields` and verify `422`.

R030  Statement: Block suspicious sensitive field keys.
Design: Reject keys matching denylist values like `auth_token`, `password`, `secret`, `access_token`, `refresh_token`, `bearer`, `authorization`.
Tests:
- Submit event field key `auth_token` and verify `422`.

R035  Statement: Enforce maximum string value size in user-provided fields.
Design: Reject strings exceeding configured per-value byte limit to prevent giant payload abuse.
Tests:
- Submit oversized string field and verify deterministic rejection.

R040  Statement: Return structured validation errors with location context.
Design: Validation failures include `error_code`, `message`, and optional data path like `events[3].fields.duration_ms`.
Tests:
- Trigger nested validation error and verify path context is present.

## Changelog

- 2026-05-08: Initial Manifold validation and limits requirements document.
