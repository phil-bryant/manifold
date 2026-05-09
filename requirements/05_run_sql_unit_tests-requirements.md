# Run SQL Unit Tests Requirements

## Scope

Applies to `05_run_sql_unit_tests.sh`.

R001  Statement: Run SQL unit-test script in strict fail-fast mode.
Design: Use `bash` strict mode (`set -euo pipefail`) and abort on first command failure.
Tests:
- Force `psql` to fail and verify script exits non-zero.

R005  Statement: Resolve SQL unit-test credentials exclusively from `1psa`.
Design: Read manifold password from `1psa` item `localhost_postgres_manifold` (default field `password`) and connect only to local `localhost:5432/manifold` as user `manifold`.
Tests:
- Run with `1psa` unavailable and verify explicit non-zero failure output.
- Return empty manifold credential from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse SQL unit-test execution when `psql` is unavailable.
Design: Verify `psql` exists on PATH before any SQL invocation.
Tests:
- Run with `psql` missing from PATH and verify explicit non-zero failure output.

R015  Statement: Resolve SQL unit-test file path relative to script location.
Design: Build SQL test file path from script directory so execution is independent of caller working directory.
Tests:
- Run script from a non-repo working directory and verify SQL unit-test path resolves correctly.

R020  Statement: Refuse SQL unit-test execution when SQL test file is missing.
Design: Validate required SQL unit-test file exists before running `psql`.
Tests:
- Move SQL test file out of place in fixture and verify explicit non-zero failure output.

R025  Statement: Ensure pgTAP extension exists before running SQL unit tests.
Design: Execute `CREATE EXTENSION IF NOT EXISTS pgtap;` via local `psql` using credentials resolved from `R005`.
Tests:
- Verify script invokes extension-create SQL before test-file execution.

R030  Statement: Execute SQL unit tests via fail-fast `psql` invocation.
Design: Run test SQL file with `-w -h localhost -p 5432 -d manifold -v ON_ERROR_STOP=1 -f <sql-test-file>` using credentials resolved from `R005`.
Tests:
- Verify test invocation includes `ON_ERROR_STOP=1`, configured database URL, and SQL test file path.

R035  Statement: Emit concise operator-readable pass output.
Design: Print one `✅ PASS:` line only after SQL unit-test execution succeeds.
Tests:
- Verify successful run emits a single `✅ PASS:` line.

## Changelog

- 2026-05-09: Added manifold SQL unit-test runner requirements.
