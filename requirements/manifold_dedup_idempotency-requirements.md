# Manifold Deduplication And Idempotency Requirements

## Scope

Requirements-only mode: true.
Defines deduplication/idempotency behavior for future files `ingest/handler.go` and `storage/postgres.go`.

R001  Statement: Deduplicate events by `event_id`.
Design: `ingest_events.event_id` is unique; duplicates are treated as already accepted and do not fail ingest.
Tests:
- Submit duplicate `event_id` and verify idempotent acceptance behavior.

R005  Statement: Keep duplicate batch submission idempotent when payload is equivalent.
Design: Repeated `batch_id` with equivalent payload must return acceptance without creating conflicting records.
Tests:
- Submit identical batch twice and verify success on second submission.

R010  Statement: Reject conflicting duplicate batches.
Design: Repeated `batch_id` with meaningfully different payload returns `409 duplicate_batch_conflict`.
Tests:
- Submit same `batch_id` with different payload and verify `409`.

R015  Statement: Preserve deterministic acceptance counts in duplicate scenarios.
Design: Success envelope counts accepted rows and duplicate rows consistently so uploader retries are safe.
Tests:
- Retry accepted batch and verify response counts remain predictable.

## Changelog

- 2026-05-08: Initial Manifold deduplication and idempotency requirements document.
