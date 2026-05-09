package security

import "testing"

func TestIsAuthorized(t *testing.T) {
	validator := NewIngestKeyValidator("top-secret")
	if !validator.IsAuthorized("top-secret") {
		t.Fatalf("expected key to authorize")
	}
	if validator.IsAuthorized("wrong") {
		t.Fatalf("expected wrong key to fail")
	}
}
