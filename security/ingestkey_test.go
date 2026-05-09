package security

import "testing"

func TestIsAuthorized(t *testing.T) {
	// #R001: Validator is created from configured expected key.
	// #R005: Authorization checks use deterministic key comparison outcomes.
	validator := NewIngestKeyValidator("top-secret")
	if !validator.IsAuthorized("top-secret") {
		t.Fatalf("expected key to authorize")
	}
	if validator.IsAuthorized("wrong") {
		t.Fatalf("expected wrong key to fail")
	}
}
