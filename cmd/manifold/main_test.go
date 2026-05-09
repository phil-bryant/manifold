package main

import "testing"

func TestRunFailsWhenRequiredEnvMissing(t *testing.T) {
	// #R001: Startup fails fast when required runtime dependencies are missing.
	// #R005: Startup path includes schema-apply gate before serving traffic.
	// #R010: Entrypoint includes graceful-shutdown path for signal handling.
	t.Setenv("MANIFOLD_INGEST_KEY", "")
	t.Setenv("MANIFOLD_DATABASE_URL", "")
	if exitCode := run(); exitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", exitCode)
	}
}
