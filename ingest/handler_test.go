package ingest

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"manifold/security"
	"manifold/storage"
)

type fakeStore struct {
	result PersistResult
	err    error
}

func (s fakeStore) PersistBatch(_ context.Context, _ BatchRequest, _ []byte) (PersistResult, error) {
	return s.result, s.err
}

func TestHandlerRejectsContentType(t *testing.T) {
	handler := NewHandler(2048, limits(), security.NewIngestKeyValidator("k"), fakeStore{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBufferString("hello"))
	req.Header.Set("X-Manifold-Ingest-Key", "k")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}

func TestHandlerRejectsUnauthorized(t *testing.T) {
	handler := NewHandler(2048, limits(), security.NewIngestKeyValidator("k"), fakeStore{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBufferString("{}"))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Manifold-Ingest-Key", "wrong")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}

func TestHandlerReturnsSuccessEnvelope(t *testing.T) {
	store := fakeStore{result: PersistResult{BatchID: "batch-1", AcceptedEventCount: 1, DuplicateCount: 0}}
	handler := NewHandler(2048, limits(), security.NewIngestKeyValidator("k"), store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	payload, _ := json.Marshal(validBatch())
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Manifold-Ingest-Key", "k")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
	var response APIResponse
	err := json.Unmarshal(rec.Body.Bytes(), &response)
	if err != nil || !response.Accepted {
		t.Fatalf("expected accepted response")
	}
}

func TestHandlerReturnsConflictForDuplicateBatch(t *testing.T) {
	store := fakeStore{err: storage.ErrDuplicateBatchConflict}
	handler := NewHandler(2048, limits(), security.NewIngestKeyValidator("k"), store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	payload, _ := json.Marshal(validBatch())
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Manifold-Ingest-Key", "k")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}

func TestHandlerReturnsInternalError(t *testing.T) {
	store := fakeStore{err: errors.New("boom")}
	handler := NewHandler(2048, limits(), security.NewIngestKeyValidator("k"), store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	payload, _ := json.Marshal(validBatch())
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", bytes.NewBuffer(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Manifold-Ingest-Key", "k")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}
