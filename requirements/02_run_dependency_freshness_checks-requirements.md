# Run Dependency Freshness Checks Requirements

## Scope

Applies to `02_run_dependency_freshness_checks.sh` and dependency freshness reporting for this Go repository.

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before any report or module operations.
Tests:
- Run from a non-root directory and verify reports are still written under repository-root `.security-reports`.

R005  Statement: Select the Go binary predictably and fail clearly when unavailable.
Design: Use `DEPENDENCY_CHECK_GO_BIN` when provided, default to `go`, and fail with actionable output when command resolution fails.
Tests:
- Run with a stubbed `go` on `PATH` and verify the selected binary is reported.
- Set `DEPENDENCY_CHECK_GO_BIN` to a missing command and verify non-zero failure.

R010  Statement: Discover module updates and always emit a text report.
Design: Execute `go list -m -u` over all modules, normalize update rows, and write `dependency-freshness.txt` with one line per update.
Tests:
- Run with update-producing stub output and verify text report includes module update entries.

R015  Statement: Emit machine-readable dependency freshness JSON.
Design: Always write `dependency-freshness.json` including total update count, major update count, and per-module current/latest version data.
Tests:
- Run with update-producing stub output and verify JSON report contains counts and module fields.

R020  Statement: Enforce dependency freshness failures when updates are available.
Design: When `DEPENDENCY_FAIL_ON_UPDATES=true` (default), exit non-zero if any dependency update is available. Keep `DEPENDENCY_FAIL_ON_MAJOR` as an additional gate for major-version boundaries.
Tests:
- Run with updates present and default configuration and verify non-zero exit.
- Run with updates present and `DEPENDENCY_FAIL_ON_UPDATES=false` and verify zero exit unless other enabled gates fail.
- Run with major update present and `DEPENDENCY_FAIL_ON_MAJOR=true` and verify non-zero exit.

R025  Statement: Emit concise status output for operators and CI logs.
Design: Print selected binary, report file paths, and update counters at completion for quick run diagnostics.
Tests:
- Run script successfully and verify output includes report paths plus update and major-update counts.

## Changelog

- 2026-05-08: Reswizzled from copied Python/Teller/Postgres flow to Manifold-native Go module freshness checks.
