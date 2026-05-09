# Domain Model Types Requirements

## Scope

Applies to `model/types.go`.

R001  Statement: Define batch request contract for ingest payloads.
Design: Batch request model includes batch ID, sent-at timestamp, and list of event records with JSON tags.
Tests:
- Decode fixture payload into model and verify required fields are present.

R005  Statement: Define normalized event record contract.
Design: Event record model includes schema/version identity fields, source metadata, and arbitrary event fields map with JSON tags.
Tests:
- Decode event payload and verify fields map and identifiers round-trip.

R010  Statement: Define persistence result counters contract.
Design: Persist result model provides batch ID plus accepted and duplicate counters returned by storage layer.
Tests:
- Build persistence result in storage path and verify counters propagate to response.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
