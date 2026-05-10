# Manifold

Manifold is a batch ingest service for structured Fountain events.

## Prerequisites

- Go 1.24+
- PostgreSQL 14+ reachable from `MANIFOLD_DATABASE_URL`

## Required Environment

- `MANIFOLD_INGEST_KEY`: shared key expected in `X-Manifold-Ingest-Key`
- `MANIFOLD_DATABASE_URL`: Postgres DSN used for writes and readiness checks

Optional runtime values:

- `MANIFOLD_ADDR` (default `:8080`)
- `MANIFOLD_MAX_BODY_BYTES` (default `1048576`)
- `MANIFOLD_MAX_EVENTS_PER_BATCH` (default `1000`)
- `MANIFOLD_MAX_EVENT_BYTES` (default `65536`)
- `MANIFOLD_MAX_FIELDS_PER_EVENT` (default `128`)
- `MANIFOLD_MAX_FIELD_STRING_BYTES` (default `2048`)
- `MANIFOLD_REQUESTS_PER_MINUTE` (default `0`, disabled)

## Local Startup

```bash
export MANIFOLD_INGEST_KEY="local-ingest-key"
export MANIFOLD_DATABASE_URL="postgres://localhost:5432/manifold?sslmode=disable"
go run ./cmd/manifold
```

## Database Setup

Manifold applies schema automatically at startup from `storage/schema.sql`.

To provision manually:

```bash
./03_deploy_database.sh
./04_verify_deploy_database.sh
./05_run_unit_tests.sh
./06_run_security_checks.sh
./07_run_av_checks.sh
```

`03_deploy_database.sh` uses `1psa` items:

- `localhost_postgres_postgres` for postgres admin password
- `localhost_postgres_manifold` for manifold user password

`05_run_unit_tests.sh` runs pgTAP SQL unit tests first, then `go test ./...`.
Security/dependency check reports are written to `.security-reports/` and are intentionally ignored by Git.

## Ingest API

`POST /v1/events/batch` expects `Content-Type: application/json` and `X-Manifold-Ingest-Key`.

```bash
curl -i \
  -H "Content-Type: application/json" \
  -H "X-Manifold-Ingest-Key: ${MANIFOLD_INGEST_KEY}" \
  -H "X-Request-ID: req-local-1" \
  -d '{
    "batch_id":"batch-123",
    "sent_at":"2026-05-08T02:00:00Z",
    "events":[
      {
        "schema_version":1,
        "event_id":"evt-1",
        "timestamp":"2026-05-08T02:00:00Z",
        "level":"info",
        "event":"startup",
        "component":"manifold",
        "install_id":"dev-1",
        "fields":{"duration_ms":12}
      }
    ]
  }' \
  http://localhost:8080/v1/events/batch
```

Success response shape:

```json
{
  "accepted": true,
  "batch_id": "batch-123",
  "accepted_event_count": 1,
  "duplicate_event_count": 0,
  "rejected_event_count": 0
}
```

Failure response shape:

```json
{
  "accepted": false,
  "batch_id": "batch-123",
  "error_code": "invalid_schema",
  "message": "schema_version must be 1",
  "path": "events[0].schema_version"
}
```

## Health And Readiness

- `GET /healthz`: process liveness and always `200` while process is alive
- `GET /readyz`: checks database reachability and returns `503` when storage is unavailable

## Status And Error Code Notes

- `400 invalid_json`
- `401 unauthorized`
- `409 duplicate_batch_conflict`
- `413 payload_too_large`
- `415 invalid_content_type`
- `422 invalid_schema` or `too_many_events`
- `429 rate_limited`
- `500 internal_error`
- `503 storage_unavailable`

## Troubleshooting

- Auth failures (`401`): verify `X-Manifold-Ingest-Key` matches `MANIFOLD_INGEST_KEY`.
- Payload validation failures (`422`): inspect `path` and `message` in JSON error.
- Storage outages (`503`): check PostgreSQL reachability and DSN correctness.

## Deployment Assumptions

V1 uses one shared ingest key for authentication and Postgres for both raw batch archive and normalized events. Object storage is a non-goal
for v1 and can be added later behind a storage abstraction.
