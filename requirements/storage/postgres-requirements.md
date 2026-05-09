# Postgres Store Requirements

## Scope

Applies to `storage/postgres.go`.

R001  Statement: Initialize and verify database connectivity on store creation.
Design: Construct SQL store with pgx driver and ping database before returning store handle.
Tests:
- Connect to configured database and verify store creation succeeds.

R005  Statement: Apply schema and readiness probes through store interface.
Design: Expose schema execution and ping methods delegating to underlying database connection.
Tests:
- Apply schema and run ping in integration tests.

R010  Statement: Persist each ingest batch within one transaction.
Design: Begin transaction, process batch/event writes atomically, commit on success, and rollback on failure.
Tests:
- Force failure during persistence and verify transaction does not partially commit.

R015  Statement: Enforce batch-id idempotency and conflict detection.
Design: Compare payload hash for existing batch IDs; accept identical payloads and reject conflicting payloads.
Tests:
- Persist duplicate equivalent batch and conflicting batch IDs and verify deterministic outcomes.

R020  Statement: Persist events with duplicate-event tolerance.
Design: Insert event rows with `ON CONFLICT(event_id) DO NOTHING` and track duplicate counts in persistence result.
Tests:
- Persist duplicate event IDs and verify duplicate counters are incremented.

R025  Statement: Detect transient storage-unavailable conditions.
Design: Classify network and selected Postgres SQLSTATE failures as unavailable for higher-layer status mapping.
Tests:
- Provide representative network/Postgres errors and verify unavailable classification.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
