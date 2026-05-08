# Manifold Postgres Storage Requirements

## Scope

Requirements-only mode: true.
Defines storage behavior for future files `internal/storage/postgres.go` and `internal/storage/schema.sql`.

R001  Statement: Persist accepted raw batches in Postgres.
Design: Store full raw batch payload in `ingest_batches.raw_json` with metadata fields and received timestamp.
Tests:
- Ingest valid batch and verify one `ingest_batches` row with raw JSON.

R005  Statement: Persist normalized event rows in Postgres.
Design: Insert one `ingest_events` row per accepted event with normalized columns plus `fields` and `raw_event`.
Tests:
- Ingest N events and verify N normalized rows exist.

R010  Statement: Use one database transaction per batch write.
Design: Insert batch and event rows atomically and commit once all inserts succeed.
Tests:
- Force event insert failure and verify no partial writes persist.

R015  Statement: Return storage-unavailable status when backend is transiently unavailable.
Design: Map transient DB unavailability to `503 storage_unavailable` rather than `500`.
Tests:
- Simulate DB outage and verify `503` response.

R020  Statement: Provide deterministic schema with required indexes.
Design: Maintain `ingest_batches` and `ingest_events` schema and secondary indexes required for timestamp, event name, component, and install-id lookups.
Tests:
- Apply schema and verify tables and required indexes exist.

R025  Statement: Keep v1 raw archive implementation in Postgres unless object storage is configured.
Design: JSONB archive in Postgres is default; raw archive backend interface must allow future S3/R2/GCS implementation.
Tests:
- Verify default mode writes raw payload only to Postgres archive fields.

## Changelog

- 2026-05-08: Initial Manifold Postgres storage requirements document.
