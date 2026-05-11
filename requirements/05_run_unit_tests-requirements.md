# Run Unit Tests Requirements

## Scope

Applies to `05_run_unit_tests.sh`.

R001  Statement: Run SQL unit-test script in strict fail-fast mode.
Design: Use `bash` strict mode (`set -euo pipefail`) and abort on first command failure.
Tests:
- Force `psql` to fail and verify script exits non-zero.

R005  Statement: Resolve SQL unit-test credentials exclusively from `1psa`.
Design: Read manifold password from `1psa` item `localhost_postgres_manifold` (default field `password`) and read target `host`/`port`/`database`/`schema` from `localhost_postgres_manifold`; connect as user `manifold`.
Tests:
- Run with `1psa` unavailable and verify explicit non-zero failure output.
- Return empty manifold credential from `1psa` and verify explicit non-zero failure output.

R010  Statement: Refuse unit-test execution when required CLIs are unavailable.
Design: Verify `psql`, `go`, and `bats` exist on PATH before any SQL, Go, or shell unit-test invocation.
Tests:
- Run with `psql` missing from PATH and verify explicit non-zero failure output.
- Run with `go` missing from PATH and verify explicit non-zero failure output.
- Run with `bats` missing from PATH and verify explicit non-zero failure output.

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

R030  Statement: Execute SQL unit tests before Go and Bats unit tests using fail-fast commands.
Design: Run SQL test file with `-w -h <1psa host> -p <1psa port> -d <1psa database> -v ON_ERROR_STOP=1 -v schema_name=<1psa schema> -c "SET search_path TO <1psa schema>" -f <sql-test-file>` using credentials from `R005`, then run `go test ./...` and `bats tests/sh` only after SQL tests succeed.
Tests:
- Verify test invocation includes `ON_ERROR_STOP=1`, configured database URL, and SQL test file path.
- Force SQL stage failure and verify `go test` is not attempted.
- Force `go test` failure and verify script exits non-zero.
- Verify `bats tests/sh` runs only after `go test ./...` succeeds.

R032  Statement: Fail when any Go package has no associated `_test.go` files.
Design: After `go test ./...` succeeds, parse output for `[no test files]` package rows and fail with an explicit list when any are present.
Tests:
- Emit simulated `go test` output with `[no test files]` entries and verify explicit non-zero failure output.
- Emit simulated `go test` output with no `[no test files]` entries and verify run can complete.

R035  Statement: Emit concise operator-readable pass output.
Design: Print one `✅ PASS:` line only after SQL, Go, and Bats unit-test execution succeeds.
Tests:
- Verify successful run emits a single `✅ PASS:` line.

## Changelog

- 2026-05-11: Read SQL unit-test host/port/database/schema from `1psa` and parameterize pgTAP schema checks.
- 2026-05-10: Added Bats execution to step-05 and required `bats` CLI presence before running tests.
- 2026-05-09: Renamed unit-test runner requirements to `05_run_unit_tests.sh`.
