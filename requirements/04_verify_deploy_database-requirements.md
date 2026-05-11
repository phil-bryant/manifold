# Verify Deploy Database Requirements

## Scope

Applies to `04_verify_deploy_database.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use POSIX `sh` shebang and `set -eu`.
Tests:
- Cause a command failure and verify script exits non-zero.

R005  Statement: Resolve verification credentials exclusively from `1psa`.
Design: Read manifold password from `localhost_postgres_manifold` `password` plus connection target from `localhost_postgres_manifold` `host`/`port`/`database`/`schema`, then verify schema as user `manifold`.
Tests:
- Run with `1psa` unavailable and verify explicit non-zero failure output.
- Return empty manifold credential from `1psa` and verify explicit non-zero failure output.
- Return empty/invalid manifold host or port from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse verification when `psql` is unavailable.
Design: Verify `psql` exists on PATH before running database checks.
Tests:
- Run with `psql` missing and verify explicit non-zero failure output.

R015  Statement: Verify required manifold ingest tables exist.
Design: Assert `ingest_batches` and `ingest_events` exist in the `1psa`-resolved target schema of the target database and report missing names.
Tests:
- Return a missing table from fixture `psql` output and verify failure details list the table.

R020  Statement: Verify required ingest indexes exist.
Design: Assert required indexes from `storage/schema.sql` exist for timestamp, event name, component, and install-id lookups.
Tests:
- Return a missing index from fixture `psql` output and verify failure details list the index.

R025  Statement: Verify foreign key linkage between events and batches.
Design: Assert a foreign key exists from `ingest_events(batch_id)` to `ingest_batches(batch_id)`.
Tests:
- Return a missing FK check result and verify explicit FK diagnostic failure.

R030  Statement: Print explicit pass/fail verification result.
Design: Print one `✅ PASS:` line only when all checks pass; otherwise print `❌ FAIL:` header, list each failed check, and exit non-zero.
Tests:
- Verify all-pass run emits a single `✅ PASS:` line.
- Verify any failed check emits `❌ FAIL:` details and exits non-zero.

R035  Statement: Execute verification queries with fail-fast psql options.
Design: Run verification SQL via `psql -w -h <1psa host> -p <1psa port> -d <1psa database> -v ON_ERROR_STOP=1 -At` using credentials from `R005`.
Tests:
- Verify query invocations include `ON_ERROR_STOP=1` and host/port resolved from `1psa`.

## Changelog

- 2026-05-11: Read verification schema name from `1psa` and use it explicitly in all object checks.
- 2026-05-11: Read verification database name from `1psa` and verify objects in the active schema instead of hardcoding `public`.
- 2026-05-10: Updated verify target host/port to be sourced from `localhost_postgres_manifold` `host`/`port` fields via `1psa`.
- 2026-05-09: Replaced teller-oriented verify requirements with manifold storage-object verification requirements.
