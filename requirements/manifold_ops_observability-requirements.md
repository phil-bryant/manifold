# Manifold Operations And Observability Requirements

## Scope

Requirements-only mode: true.
Defines runtime endpoints and operational telemetry behavior for future files `httpserver/server.go` and `logging/logging.go`.

R001  Statement: Expose liveness endpoint independent of database state.
Design: `GET /healthz` returns `200` when process is alive even if dependencies are degraded.
Tests:
- Stop database and verify `/healthz` still returns `200`.

R005  Statement: Expose readiness endpoint dependent on database reachability.
Design: `GET /readyz` checks database connectivity and returns non-`200` when unavailable.
Tests:
- Simulate unavailable database and verify `/readyz` failure.

R010  Statement: Emit one structured request log per request.
Design: Request logs include `request_id`, `path`, `status`, `duration_ms`, and ingest-context fields when available.
Tests:
- Send ingest request and verify one structured log record with required fields.

R015  Statement: Avoid sensitive payload logging by default.
Design: Do not log full request body, ingest key, or raw event fields unless explicit debug mode is enabled.
Tests:
- Submit ingest request and verify logs omit sensitive request body/key details.

R020  Statement: Preserve request ID continuity.
Design: Accept reasonable incoming `X-Request-ID`, generate one when absent, and return `X-Request-ID` in responses.
Tests:
- Send request with and without `X-Request-ID` and verify response header behavior.

R025  Statement: Keep telemetry dependencies lightweight in v1.
Design: Use built-in logging and simple counters/timers without hard dependency on OpenTelemetry unless trivial.
Tests:
- Run service without OpenTelemetry stack and verify observability outputs still function.

## Changelog

- 2026-05-08: Initial Manifold operations and observability requirements document.
