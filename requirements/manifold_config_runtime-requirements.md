# Manifold Configuration And Runtime Requirements

## Scope

Requirements-only mode: true.
Defines runtime configuration behavior for future files `cmd/manifold/main.go` and `internal/config/config.go`.

R001  Statement: Require critical runtime configuration.
Design: Service startup fails fast when `MANIFOLD_INGEST_KEY` or `MANIFOLD_DATABASE_URL` is missing.
Tests:
- Start service with each required variable missing and verify non-zero startup failure.

R005  Statement: Provide stable defaults for optional runtime configuration.
Design: Default values include `MANIFOLD_ADDR=:8080`, body/event limits, and raw archive disabled unless explicitly enabled.
Tests:
- Start service with only required variables and verify defaults are applied.

R010  Statement: Parse and validate numeric limit configuration defensively.
Design: Reject invalid numeric env values and fail with explicit startup guidance.
Tests:
- Provide non-numeric limit variable and verify startup error.

R015  Statement: Keep configuration loading deterministic and explicit.
Design: Centralize config parsing, derive immutable config object at startup, and avoid runtime mutation of limit/security settings.
Tests:
- Verify config loader produces consistent values across repeated startup with same environment.

R020  Statement: Keep deployment surface simple.
Design: Service starts with environment variables alone and no mandatory external control plane.
Tests:
- Run service in local environment with env-only config and verify startup succeeds.

## Changelog

- 2026-05-08: Initial Manifold configuration and runtime requirements document.
