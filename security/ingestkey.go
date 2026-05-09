package security

import "crypto/subtle"

type IngestKeyValidator struct {
	expected []byte
}

func NewIngestKeyValidator(expected string) IngestKeyValidator {
	return IngestKeyValidator{expected: []byte(expected)}
}

func (v IngestKeyValidator) IsAuthorized(provided string) bool {
	return subtle.ConstantTimeCompare(v.expected, []byte(provided)) == 1
}
