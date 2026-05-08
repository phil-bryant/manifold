# Install Prerequisites Requirements

## Scope

Applies to `01_install_prerequisites.sh` and local macOS setup required before running this repository's Go/backend build and test targets.

R001  Statement: Run with `bash` in strict fail-fast mode.
Design: Use `set -euo pipefail` and exit non-zero on unrecoverable failures.
Tests:
- Force a failing command and verify installer exits non-zero.

R005  Statement: Verify Homebrew exists before Homebrew package actions.
Design: Check `brew` on `PATH`; print install guidance when missing.
Tests:
- Run with `brew` unavailable and verify clear failure guidance.

R010  Statement: Ensure Go toolchain is available for Manifold development.
Design: Require `go` on `PATH`; install Homebrew formula `go` when missing, then verify command resolution.
Tests:
- Run without `go` and verify installer attempts `brew install go`.
- Rerun with `go` already installed and verify no reinstall.

R015  Statement: Enforce a minimum Go version required by this repository.
Design: Parse `go version` output and fail with actionable guidance when the detected version is below configured minimum.
Tests:
- Simulate lower-than-minimum version output and verify explicit failure.
- Simulate acceptable version output and verify pass.

R020  Statement: Ensure Postgres CLI tooling is available for local readiness and diagnostics.
Design: Require `psql`; when missing, install Homebrew formula `libpq` and accept either PATH-discoverable `psql` or `$(brew --prefix libpq)/bin/psql`.
Tests:
- Simulate missing `psql` and verify installer attempts `brew install libpq`.
- Simulate fallback `$(brew --prefix libpq)/bin/psql` and verify success.

R025  Statement: Ensure primary Go lint tooling is available.
Design: Require `golangci-lint`; install Homebrew formula `golangci-lint` when missing and fail when still unavailable.
Tests:
- Run without `golangci-lint` and verify installer attempts `brew install golangci-lint`.

R030  Statement: Ensure SAST/security tooling required by this repository is available.
Design: Verify/install `shellcheck`, `semgrep`, and `gitleaks` before completion so security and shell-policy lanes are runnable.
Tests:
- Run installer without those tools and verify each required formula install is attempted.
- Rerun installer and verify already-installed tools are not reinstalled.

R035  Statement: Print explicit status for each prerequisite phase.
Design: Emit clear checking/install/success/failure output for Homebrew, Go, Go version, Postgres CLI, lint toolchain, and security tools.
Tests:
- Run installer and verify phase status output appears for all major checks.

R040  Statement: Keep installer idempotent across reruns.
Design: Skip install/setup steps when dependencies are already satisfied.
Tests:
- Run installer twice and verify the second run performs no unnecessary installs.

R045  Statement: Print final readiness guidance for local development.
Design: End with success output that references repository commands (`go test ./...`, `go test -race ./...`, `golangci-lint run`).
Tests:
- On successful run, verify final guidance includes those commands.

R050  Statement: Keep local setup guidance explicit for database-dependent checks.
Design: Success guidance includes reminder to export `MANIFOLD_DATABASE_URL` before running readiness checks.
Tests:
- Run installer successfully and verify final guidance includes `MANIFOLD_DATABASE_URL`.

## Changelog

- 2026-05-08: Reswizzled installer requirements for Manifold Go backend prerequisites and strict dev tooling.
