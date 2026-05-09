# Manifold Ingest API Requirements

## Scope

Requirements-only mode: true.
Defines API behavior for future implementation files `cmd/manifold/main.go`, `httpserver/server.go`, and `ingest/handler.go`.

R001  Statement: Expose batch ingest endpoint at `POST /v1/events/batch`.
Design: Route only accepts JSON batch uploads for structured Fountain events uploaded by Piston.
Tests:
- Verify endpoint exists and rejects unsupported methods.

R005  Statement: Enforce `Content-Type: application/json` for ingest requests.
Design: Return `415` with `error_code` `invalid_content_type` for unsupported media types.
Tests:
- Submit ingest request without JSON content type and verify `415`.

R010  Statement: Return predictable JSON envelope for successful acceptance.
Design: Success response contains `accepted`, `batch_id`, `accepted_event_count`, and `rejected_event_count`.
Tests:
- Submit valid batch and verify success envelope fields and types.

R015  Statement: Return predictable JSON envelope for failure outcomes.
Design: Failure response contains `accepted=false`, `batch_id` when known, `error_code`, and operator-readable `message`.
Tests:
- Trigger validation failure and verify stable failure envelope shape.

R020  Statement: Map ingest failure classes to deterministic HTTP status codes.
Design: Use `400`, `401`, `413`, `415`, `422`, `429`, `500`, and `503` exactly for their documented error classes.
Tests:
- Trigger one representative failure per status and verify deterministic mapping.

R025  Statement: Keep v1 acceptance batch-level only.
Design: Accept full batch only when all events validate; reject full batch when any event is invalid with `422`.
Tests:
- Submit mixed-validity batch and verify full rejection.

## Changelog

- 2026-05-08: Initial Manifold ingest API requirements document.
