package storage

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	"manifold/internal/model"
)

func TestPersistBatchIntegration(t *testing.T) {
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
