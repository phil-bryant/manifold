package storage

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"manifold/model"
)

func TestPersistBatchIntegration(t *testing.T) {
	// #R001: Store initialization succeeds when database connectivity is valid.
	// #R005: Store exposes schema apply/readiness interfaces used in setup.
	// #R010: Batch persistence writes occur through transactional storage path.
	// #R020: Event persistence tracks inserted/duplicate counts.
	// #R001: Embedded schema string is available for schema application.
	dsn := os.Getenv("MANIFOLD_DATABASE_URL")
	if dsn == "" {
		t.Skip("MANIFOLD_DATABASE_URL is required for integration test")
	}
	store, err := NewPostgresStore(dsn)
	if err != nil {
		t.Fatalf("store init failed: %v", err)
	}
	defer func() { _ = store.Close() }()
	err = store.ApplySchema(context.Background(), SchemaSQL)
	if err != nil {
		t.Fatalf("schema apply failed: %v", err)
	}
	batch := model.BatchRequest{
		BatchID: "batch-storage-it",
		SentAt:  "2026-05-08T02:00:00Z",
		Events: []model.EventRecord{
			{
				SchemaVersion: 1,
				EventID:       "evt-storage-it-1",
				Timestamp:     "2026-05-08T02:00:00Z",
				Level:         "info",
				Event:         "ingest_test",
				Component:     "storage",
				InstallID:     "install-storage",
				Fields:        map[string]interface{}{"k": "v"},
			},
		},
	}
	rawBody, _ := json.Marshal(batch)
	result, err := store.PersistBatch(context.Background(), batch, rawBody)
	if err != nil {
		t.Fatalf("persist failed: %v", err)
	}
	if result.AcceptedEventCount != 1 {
		t.Fatalf("expected 1 accepted event, got %d", result.AcceptedEventCount)
	}
}

func TestDuplicateBatchConflictIntegration(t *testing.T) {
	// #R015: Conflicting duplicate batch payloads return deterministic conflict outcome.
	dsn := os.Getenv("MANIFOLD_DATABASE_URL")
	if dsn == "" {
		t.Skip("MANIFOLD_DATABASE_URL is required for integration test")
	}
	store, err := NewPostgresStore(dsn)
	if err != nil {
		t.Fatalf("store init failed: %v", err)
	}
	defer func() { _ = store.Close() }()
	err = store.ApplySchema(context.Background(), SchemaSQL)
	if err != nil {
		t.Fatalf("schema apply failed: %v", err)
	}
	base := model.BatchRequest{
		BatchID: "batch-storage-conflict-it",
		SentAt:  "2026-05-08T02:00:00Z",
		Events: []model.EventRecord{
			{
				SchemaVersion: 1,
				EventID:       "evt-storage-conflict-it-1",
				Timestamp:     "2026-05-08T02:00:00Z",
				Level:         "info",
				Event:         "conflict",
				Component:     "storage",
				InstallID:     "install-storage",
				Fields:        map[string]interface{}{"k": "v"},
			},
		},
	}
	raw, _ := json.Marshal(base)
	_, err = store.PersistBatch(context.Background(), base, raw)
	if err != nil {
		t.Fatalf("first persist failed: %v", err)
	}
	base.Events[0].Event = "conflict-changed"
	rawChanged, _ := json.Marshal(base)
	_, err = store.PersistBatch(context.Background(), base, rawChanged)
	if err == nil {
		t.Fatalf("expected duplicate batch conflict")
	}
}

func TestIsUnavailableClassifiesNetworkAndPGCodes(t *testing.T) {
	// #R025: Transient network/Postgres errors classify as storage unavailable.
	netErr := &net.OpError{Op: "dial", Err: errors.New("down")}
	if !IsUnavailable(netErr) {
		t.Fatalf("expected network op error to be unavailable")
	}
	pgErr := &pgconn.PgError{Code: "08006"}
	if !IsUnavailable(pgErr) {
		t.Fatalf("expected SQLSTATE 08xxx to be unavailable")
	}
	if IsUnavailable(errors.New("boom")) {
		t.Fatalf("plain errors should not be unavailable")
	}
}
