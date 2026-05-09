# Ingest Handler Requirements

## Scope

Applies to `ingest/handler.go`.

R001  Statement: Accept only POST JSON ingest requests.
Design: Reject unsupported methods and non-JSON content type with deterministic error envelopes.
Tests:
- Send non-POST and non-JSON requests and verify status and error codes.

R005  Statement: Enforce ingest-key authorization before processing request body.
Design: Validate `X-Manifold-Ingest-Key` and return unauthorized error envelope when invalid.
Tests:
- Send request with wrong key and verify unauthorized response.

R010  Statement: Enforce request-body size and JSON decoding guarantees.
Design: Cap request body size and return deterministic errors for oversized or unreadable JSON payloads.
Tests:
- Submit oversized or malformed payloads and verify expected error responses.

R015  Statement: Run schema validation before persistence.
Design: Decode request into batch structure, validate against ingest limits, and include validation path details when present.
Tests:
- Submit invalid batch payload and verify validation error code and path fields.

R020  Statement: Map storage outcomes to deterministic API responses.
Design: Translate duplicate-batch conflict, storage unavailable, and unexpected storage errors into stable status and error codes.
Tests:
- Simulate each storage failure mode and verify response mapping.

R025  Statement: Return successful acceptance envelope from persistence result.
Design: On successful persistence, return accepted response including batch ID and event counters.
Tests:
- Simulate persistence success and verify acceptance fields in response body.

## Changelog

- 2026-05-09: Split from manifold-level requirements into per-file enforced traceability.
