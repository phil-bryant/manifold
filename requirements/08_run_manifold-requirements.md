# Run Manifold Requirements

## Scope

Applies to `08_run_manifold.sh`.

R001  Statement: Run manifold startup in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` to that directory before startup logic.
Tests:
- Run from a non-repo working directory and verify launch context still resolves under script root.

R005  Statement: Fail fast with installer guidance when required commands are missing.
Design: Validate required commands with a shared helper and print `./01_install_prerequisites.sh` guidance when a command is unavailable.
Tests:
- Run with `go` missing and verify explicit non-zero failure plus installer guidance output.

R010  Statement: Compose `MANIFOLD_DATABASE_URL` from `1psa` when no explicit URL override is provided.
Design: When `MANIFOLD_DATABASE_URL` is unset, require `1psa` and `python3`, read `username`/`password`/`host`/`port`/`database` from `localhost_postgres_manifold` (configurable item), and build a URL-encoded Postgres DSN.
Tests:
- Run without `MANIFOLD_DATABASE_URL` and verify runtime uses `1psa`-composed DSN.

R015  Statement: Fail clearly when required `1psa` database fields are missing or invalid.
Design: Reject unreadable or empty `1psa` fields and reject non-numeric or out-of-range database ports before launch.
Tests:
- Return empty `host` from `1psa` and verify explicit non-zero failure output.
- Return invalid `port` from `1psa` and verify explicit non-zero failure output.

R020  Statement: Honor explicit `MANIFOLD_DATABASE_URL` overrides without requiring `1psa`.
Design: If `MANIFOLD_DATABASE_URL` is already set, skip `1psa` resolution and run with the provided value.
Tests:
- Run with explicit `MANIFOLD_DATABASE_URL` and verify startup succeeds when `1psa` is absent.

R025  Statement: Emit startup context and launch manifold with deterministic runtime env.
Design: Print startup context (`MANIFOLD_ADDR`, DB URL source, command), then execute `go run ./cmd/manifold` with `MANIFOLD_ADDR`, `MANIFOLD_DATABASE_URL`, and `MANIFOLD_INGEST_KEY`.
Tests:
- Verify startup output includes launch command and DB URL source marker.
- Verify `go run ./cmd/manifold` receives resolved runtime environment values.

## Changelog

- 2026-05-11: Added step-08 manifold runtime launcher requirements with 1psa DB URL composition and env override policy.
