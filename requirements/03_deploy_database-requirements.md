# Deploy Database Requirements

## Scope

Applies to `03_deploy_database.sh`.

R001  Statement: Run deploy in strict fail-fast mode.
Design: Use `bash` strict mode (`set -euo pipefail`) so deploy aborts on first command or variable failure.
Tests:
- Force `psql` failure and verify script exits non-zero.

R005  Statement: Resolve deploy credentials exclusively from `1psa`.
Design: Read postgres admin password from `localhost_postgres_postgres` and manifold password from `localhost_postgres_manifold` (default `password` field for both), with optional `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD` and `MANIFOLD_PSA_ITEM`/`MANIFOLD_PSA_FIELD` overrides.
Tests:
- Run with `1psa` unavailable and verify explicit non-zero failure output.
- Return empty manifold credential from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse deploy when `psql` is unavailable.
Design: Verify `psql` exists on PATH before attempting schema application.
Tests:
- Run with `psql` missing from PATH and verify explicit non-zero failure output.

R015  Statement: Resolve schema path relative to script location.
Design: Build schema file path from the script directory so deploy works from any current working directory.
Tests:
- Run script from a non-repo working directory and verify schema file still resolves.

R020  Statement: Refuse deploy when schema file is missing.
Design: Validate `internal/storage/schema.sql` exists before invoking `psql`.
Tests:
- Remove schema file in a fixture and verify explicit non-zero failure output.

R025  Statement: Bootstrap manifold role/database and apply schema with fail-fast `psql` execution.
Design: Connect as postgres to create-or-alter role `manifold`, create-or-own database `manifold`, then execute schema apply as user `manifold` using `-w -h localhost -p 5432 -d manifold -v ON_ERROR_STOP=1 -f internal/storage/schema.sql`.
Tests:
- Verify deploy invokes admin `psql` bootstrap commands and manifold schema apply with `ON_ERROR_STOP=1`.

R030  Statement: Emit concise operator-readable success output.
Design: Print one success line after schema apply completes without errors.
Tests:
- Verify success output contains a single `PASS` line.

## Changelog

- 2026-05-09: Replaced teller-oriented deploy requirements with manifold schema deploy requirements.
