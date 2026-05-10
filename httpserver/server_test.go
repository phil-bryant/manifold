package httpserver

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"manifold/ingest"
)

type fakeReadinessStore struct {
	err error
}

func (s fakeReadinessStore) Ping(_ context.Context) error {
	return s.err
}

type fakeIngestService struct{}

func (fakeIngestService) ProcessBatch(_ context.Context, _ string, _ ingest.BatchRequest, _ []byte) (int, ingest.APIResponse, []any) {
	return http.StatusOK, ingest.APIResponse{Accepted: true}, nil
}

func TestHealthzAlwaysOK(t *testing.T) {
	// #R001: Operational routes are registered and health endpoint responds.
	server := NewServer(
		":0",
		fakeReadinessStore{},
		fakeIngestService{},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		0,
	)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	server.server.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}

func TestReadyzReflectsDBState(t *testing.T) {
	// #R015: Readiness returns service unavailable when storage ping fails.
	server := NewServer(
		":0",
		fakeReadinessStore{err: context.DeadlineExceeded},
		fakeIngestService{},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		0,
	)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	server.server.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("unexpected status: %d", rec.Code)
	}
}

func TestRequestIDPropagation(t *testing.T) {
	// #R005: Middleware preserves caller-provided request ID in response.
	server := NewServer(
		":0",
		fakeReadinessStore{},
		fakeIngestService{},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		0,
	)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/events/batch", nil)
	req.Header.Set("X-Request-ID", "req-123")
	server.server.Handler.ServeHTTP(rec, req)
	if rec.Header().Get("X-Request-ID") != "req-123" {
		t.Fatalf("unexpected request id: %s", rec.Header().Get("X-Request-ID"))
	}
}

func TestRateLimitReturns429(t *testing.T) {
	// #R010: Enabled limiter rejects over-limit requests with HTTP 429.
	server := NewServer(
		":0",
		fakeReadinessStore{},
		fakeIngestService{},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		1,
	)
	first := httptest.NewRecorder()
	server.server.Handler.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	second := httptest.NewRecorder()
	server.server.Handler.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", second.Code)
	}
}

func TestServerSetsReadHeaderTimeout(t *testing.T) {
	// #R020: Configure ReadHeaderTimeout to mitigate slowloris attacks.
	server := NewServer(
		":0",
		fakeReadinessStore{},
		fakeIngestService{},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		0,
	)
	if server.server.ReadHeaderTimeout <= 0 {
		t.Fatalf("expected ReadHeaderTimeout to be configured, got %s", server.server.ReadHeaderTimeout)
	}
}
