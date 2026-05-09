package security

import "crypto/subtle"

type IngestKeyValidator struct {
	expected []byte
}

func NewIngestKeyValidator(expected string) IngestKeyValidator {
	// #R001: Store configured ingest key bytes for validator reuse.
	return IngestKeyValidator{expected: []byte(expected)}
}

func (v IngestKeyValidator) IsAuthorized(provided string) bool {
	// #R005: Compare provided ingest key using constant-time semantics.
	return subtle.ConstantTimeCompare(v.expected, []byte(provided)) == 1
}
