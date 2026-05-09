# Main Entrypoint Requirements

## Scope

Applies to `cmd/manifold/main.go`.

R001  Statement: Start up with explicit dependency wiring and fail-fast behavior.
Design: Build logger, load runtime config, initialize storage, and return non-zero when any required startup dependency fails.
Tests:
- Run entrypoint with invalid environment/database inputs and verify startup exits non-zero.

R005  Statement: Apply database schema before serving traffic.
Design: Call schema application at startup and return non-zero when schema setup fails.
Tests:
- Simulate schema apply failure and verify startup exits before serving requests.

R010  Statement: Support graceful shutdown with bounded timeout.
Design: Listen for SIGTERM/SIGINT and invoke HTTP server shutdown with timeout while preserving non-zero exit on shutdown failure.
Tests:
- Trigger shutdown signal and verify graceful server stop path executes.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
