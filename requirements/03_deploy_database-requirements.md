# Deploy Database Requirements

## Scope

Applies to `03_deploy_database.sh`.

R001  Statement: Run deploy in strict fail-fast mode.
Design: Use `bash` strict mode (`set -euo pipefail`) so deploy aborts on first command or variable failure.
Tests:
- Force `psql` failure and verify script exits non-zero.

R005  Statement: Resolve deploy credentials exclusively from `1psa`.
Design: Read postgres admin password from `localhost_postgres_postgres`; read manifold password plus connection target `host`/`port`/`database`/`schema` from `localhost_postgres_manifold` (`password`, `host`, `port`, `database`, `schema` fields), with optional item/field overrides for password retrieval.
Tests:
- Run with `1psa` unavailable and verify explicit non-zero failure output.
- Return empty manifold credential from `1psa` and verify explicit non-zero failure output.
- Return empty manifold host/port from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse deploy when `psql` is unavailable.
Design: Verify `psql` exists on PATH before attempting schema application.
Tests:
- Run with `psql` missing from PATH and verify explicit non-zero failure output.

R015  Statement: Resolve schema path relative to script location.
Design: Build schema file path from the script directory so deploy works from any current working directory.
Tests:
- Run script from a non-repo working directory and verify schema file still resolves.

R020  Statement: Refuse deploy when schema file is missing.
Design: Validate `storage/schema.sql` exists before invoking `psql`.
Tests:
- Remove schema file in a fixture and verify explicit non-zero failure output.

R025  Statement: Bootstrap manifold role/database and apply schema with fail-fast `psql` execution.
Design: Connect as postgres to create-or-alter role `manifold`, create-or-own database from `1psa` `database`, ensure schema from `1psa` `schema` exists and is owned by manifold, then execute schema apply as user `manifold` using `-w -h <1psa host> -p <1psa port> -d <1psa database> -v ON_ERROR_STOP=1 -c "SET search_path TO <1psa schema>" -f storage/schema.sql`.
Tests:
- Verify deploy invokes admin `psql` bootstrap commands and manifold schema apply with `ON_ERROR_STOP=1`.

R030  Statement: Emit concise operator-readable success output.
Design: Print one success line after schema apply completes without errors.
Tests:
- Verify success output contains a single `PASS` line.

## Changelog

- 2026-05-11: Read deploy target schema name from `1psa`, create that schema, and apply storage schema using that schema search path.
- 2026-05-11: Read deploy target database name from `1psa` instead of hardcoding `manifold`.
- 2026-05-10: Updated deploy target host/port to be sourced from `localhost_postgres_manifold` `host`/`port` fields via `1psa`.
- 2026-05-09: Replaced teller-oriented deploy requirements with manifold schema deploy requirements.
