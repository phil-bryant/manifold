# HTTP Server Requirements

## Scope

Applies to `httpserver/server.go`.

R001  Statement: Register ingest, health, and readiness routes on startup.
Design: Initialize server mux with `/v1/events/batch`, `/healthz`, and `/readyz` handlers before serving.
Tests:
- Create server and verify each route responds through handler.

R005  Statement: Preserve request ID continuity across request and response.
Design: Accept valid incoming `X-Request-ID`, generate one when invalid/missing, and return it in response headers.
Tests:
- Send requests with valid and invalid IDs and verify response header behavior.

R010  Statement: Enforce optional per-minute rate limiting with deterministic 429 responses.
Design: When enabled, reject over-limit requests with JSON response payload and skip downstream handler execution.
Tests:
- Configure limiter, exceed quota, and verify 429 response contract.

R015  Statement: Report readiness based on storage reachability.
Design: Return ready endpoint success when ping passes and `503 storage_unavailable` when ping fails.
Tests:
- Simulate ping failure and verify readiness endpoint status and payload.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
