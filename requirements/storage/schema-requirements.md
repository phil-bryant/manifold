# Embedded Schema Requirements

## Scope

Applies to `storage/schema.go`.

R001  Statement: Embed SQL schema into storage package binary.
Design: Use Go embed directive to load `schema.sql` into exported schema string for startup schema application.
Tests:
- Access embedded schema string and verify it is non-empty in storage tests.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
