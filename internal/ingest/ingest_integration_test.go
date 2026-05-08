package ingest_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"manifold/internal/ingest"
	"manifold/internal/model"
	"manifold/internal/security"
	"manifold/internal/storage"
)

func TestIngestEndToEndIntegration(t *testing.T) {
	dsn := os.Getenv("MANIFOLD_DATABASE_URL")
	if dsn == "" {
		t.Skip("MANIFOLD_DATABASE_URL is required for integration test")
	}
	store, err := storage.NewPostgresStore(dsn)
	if err != nil {
		t.Fatalf("store init failed: %v", err)
	}
	defer func() { _ = store.Close() }()
	err = store.ApplySchema(context.Background(), storage.SchemaSQL)
	if err != nil {
		t.Fatalf("schema apply failed: %v", err)
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := ingest.NewHandler(1024*1024, testLimits(), security.NewIngestKeyValidator("key"), store, logger)
	batch := testBatch()
	batch.BatchID = "batch-integration-ok"
	batch.Events[0].EventID = "evt-integration-ok-1"
	payload, _ := json.Marshal(batch)
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Manifold-Ingest-Key", "key")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d, body: %s", rec.Code, rec.Body.String())
	}
}

func TestIngestBatchConflictIntegration(t *testing.T) {
	dsn := os.Getenv("MANIFOLD_DATABASE_URL")
	if dsn == "" {
		t.Skip("MANIFOLD_DATABASE_URL is required for integration test")
	}
	store, err := storage.NewPostgresStore(dsn)
	if err != nil {
		t.Fatalf("store init failed: %v", err)
	}
	defer func() { _ = store.Close() }()
	err = store.ApplySchema(context.Background(), storage.SchemaSQL)
	if err != nil {
		t.Fatalf("schema apply failed: %v", err)
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := ingest.NewHandler(1024*1024, testLimits(), security.NewIngestKeyValidator("key"), store, logger)
	batch := testBatch()
	batch.BatchID = "batch-integration-conflict"
	batch.Events[0].EventID = "evt-integration-conflict-1"
	firstPayload, _ := json.Marshal(batch)
	firstReq := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(firstPayload))
	firstReq.Header.Set("Content-Type", "application/json")
	firstReq.Header.Set("X-Manifold-Ingest-Key", "key")
	firstRec := httptest.NewRecorder()
	handler.ServeHTTP(firstRec, firstReq)
	if firstRec.Code != http.StatusOK {
		t.Fatalf("unexpected first status: %d", firstRec.Code)
	}
	batch.Events[0].Event = "changed-event"
	secondPayload, _ := json.Marshal(batch)
	secondReq := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(secondPayload))
	secondReq.Header.Set("Content-Type", "application/json")
	secondReq.Header.Set("X-Manifold-Ingest-Key", "key")
	secondRec := httptest.NewRecorder()
	handler.ServeHTTP(secondRec, secondReq)
	if secondRec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", secondRec.Code)
	}
}

func testBatch() model.BatchRequest {
	return model.BatchRequest{
		BatchID: "batch-1",
		SentAt:  "2026-05-08T02:00:00Z",
		Events: []model.EventRecord{
			{
				SchemaVersion: 1,
				EventID:       "evt-1",
				Timestamp:     "2026-05-08T02:00:00Z",
				Level:         "info",
				Event:         "startup",
				Component:     "manifold",
				InstallID:     "install-1",
				Fields:        map[string]interface{}{"duration_ms": 12.0},
			},
		},
	}
}

func testLimits() ingest.Limits {
	return ingest.Limits{MaxEventsPerBatch: 3, MaxEventBytes: 1024, MaxFieldsPerEvent: 4, MaxFieldStrBytes: 16}
}
