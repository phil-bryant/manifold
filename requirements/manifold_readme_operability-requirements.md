# Manifold README Operability Requirements

## Scope

Requirements-only mode: true.
Defines operator documentation requirements for future file `README.md`.

R001  Statement: Document local startup workflow for developers.
Design: README includes prerequisite summary, required environment variables, and run command sequence.
Tests:
- Review README and verify local startup steps are complete and executable.

R005  Statement: Document ingest request example and expected responses.
Design: Include canonical curl example for `POST /v1/events/batch` plus success and failure response shapes.
Tests:
- Run documented curl example against local service and verify response matches documented schema.

R010  Statement: Document database setup and schema initialization.
Design: README includes Postgres provisioning notes and schema/migration application workflow.
Tests:
- Follow README database section on a clean environment and verify ingest tables are created.

R015  Statement: Document operational endpoints and troubleshooting flow.
Design: README explains `/healthz`, `/readyz`, key status/error codes, and common operator actions.
Tests:
- Validate README includes troubleshooting guidance for auth failure, payload rejection, and database outage cases.

R020  Statement: Document deployment assumptions for v1.
Design: README states simple shared-key auth model, Postgres requirement, and optional raw archive backend direction.
Tests:
- Verify deployment section clearly states v1 architecture boundaries and non-goals.

## Changelog

- 2026-05-08: Initial Manifold README operability requirements document.
