# Manifold Ingest Key Security Requirements

## Scope

Requirements-only mode: true.
Defines ingest authentication and request-security behavior for future files `internal/security/ingestkey.go` and `internal/ingest/handler.go`.

R001  Statement: Require ingest key for batch ingestion.
Design: `POST /v1/events/batch` requires header `X-Manifold-Ingest-Key`.
Tests:
- Omit ingest key and verify `401 unauthorized`.

R005  Statement: Compare ingest key using constant-time logic.
Design: Use constant-time byte comparison against configured key to reduce timing side-channel risk.
Tests:
- Provide wrong key and verify deterministic `401` without alternate error shape.

R010  Statement: Prevent ingest key leakage in logs and error responses.
Design: Never print key values in logs, metrics labels, panic output, or API responses.
Tests:
- Trigger auth failures and verify logs/responses contain no key material.

R015  Statement: Keep authentication scope intentionally simple in v1.
Design: Shared ingest key is the only required auth mechanism unless explicitly extended by later requirements.
Tests:
- Verify service starts and enforces auth with only configured shared key.

## Changelog

- 2026-05-08: Initial Manifold ingest-key security requirements document.
