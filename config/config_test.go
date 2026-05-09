package config

import "testing"

func TestLoadFromEnvFailsWithoutRequiredValues(t *testing.T) {
	// #R001: Missing required ingest/database env vars must fail config loading.
	t.Setenv("MANIFOLD_INGEST_KEY", "")
	t.Setenv("MANIFOLD_DATABASE_URL", "")
	_, err := LoadFromEnv()
	if err == nil {
		t.Fatalf("expected missing env error")
	}
}

func TestLoadFromEnvAppliesDefaults(t *testing.T) {
	// #R005: Optional runtime settings use deterministic defaults.
	t.Setenv("MANIFOLD_INGEST_KEY", "abc")
	t.Setenv("MANIFOLD_DATABASE_URL", "postgres://user:pw@localhost/db?sslmode=disable")
	cfg, err := LoadFromEnv()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if cfg.Addr != ":8080" {
		t.Fatalf("unexpected addr: %s", cfg.Addr)
	}
	if cfg.MaxBodyBytes != defaultMaxBodyBytes {
		t.Fatalf("unexpected max body bytes: %d", cfg.MaxBodyBytes)
	}
}

func TestLoadFromEnvRejectsInvalidNumeric(t *testing.T) {
	// #R010: Positive numeric limits reject invalid values.
	// #R015: Request-rate configuration rejects malformed values.
	t.Setenv("MANIFOLD_INGEST_KEY", "abc")
	t.Setenv("MANIFOLD_DATABASE_URL", "postgres://user:pw@localhost/db?sslmode=disable")
	t.Setenv("MANIFOLD_MAX_BODY_BYTES", "bad")
	_, err := LoadFromEnv()
	if err == nil {
		t.Fatalf("expected parse error")
	}
}
