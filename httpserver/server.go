package httpserver

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"sync"
	"time"

	"manifold/ingest"
)

type ReadinessStore interface {
	Ping(ctx context.Context) error
}

type Server struct {
	server      *http.Server
	readinessDB ReadinessStore
	logger      *slog.Logger
	limiter     *minuteLimiter
}

func NewServer(addr string, db ReadinessStore, ingestHandler http.Handler, logger *slog.Logger, requestsPerMinute int) *Server {
	mux := http.NewServeMux()
	server := &Server{
		readinessDB: db,
		logger:      logger,
		limiter:     newMinuteLimiter(requestsPerMinute),
	}
	// #R001: Register ingest and operational routes during server construction.
	mux.Handle("/v1/events/batch", server.withMiddleware(ingestHandler))
	mux.Handle("/healthz", server.withMiddleware(http.HandlerFunc(server.handleHealth)))
	mux.Handle("/readyz", server.withMiddleware(http.HandlerFunc(server.handleReady)))
	server.server = &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	return server
}

func (s *Server) ListenAndServe() error {
	return s.server.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	return s.server.Shutdown(ctx)
}

func (s *Server) Handler() http.Handler {
	return s.server.Handler
}

func (s *Server) withMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startedAt := time.Now().UTC()
		// #R005: Preserve a sanitized request ID across request/response lifecycle.
		requestID := sanitizeOrGenerateRequestID(r.Header.Get("X-Request-ID"))
		w.Header().Set("X-Request-ID", requestID)
		r.Header.Set("X-Request-ID", requestID)
		wrapped := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		// #R010: Enforce per-minute request quotas when limiter is enabled.
		if s.limiter.Enabled() && !s.limiter.Allow() {
			response := ingest.APIResponse{Accepted: false, ErrorCode: "rate_limited", Message: "rate limited"}
			err := writeJSONResponse(wrapped, http.StatusTooManyRequests, response)
			if err != nil {
				s.logger.Error("rate limited response write failed", "request_id", requestID, "error", err)
			}
		}
		if !(s.limiter.Enabled() && wrapped.status == http.StatusTooManyRequests) {
			next.ServeHTTP(wrapped, r)
		}
		durationMS := time.Since(startedAt).Milliseconds()
		s.logger.Info(
			"request",
			"request_id", requestID,
			"path", r.URL.Path,
			"status", wrapped.status,
			"duration_ms", durationMS,
		)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	payload := map[string]interface{}{"ok": true}
	err := writeJSONMap(w, http.StatusOK, payload)
	if err != nil {
		s.logger.Error("health response write failed", "error", err)
	}
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	status := http.StatusOK
	payload := map[string]interface{}{"ok": true}
	// #R015: Report readiness based on storage ping availability.
	err := s.readinessDB.Ping(r.Context())
	if err != nil {
		status = http.StatusServiceUnavailable
		payload["ok"] = false
		payload["error_code"] = "storage_unavailable"
	}
	writeErr := writeJSONMap(w, status, payload)
	if writeErr != nil {
		s.logger.Error("ready response write failed", "error", writeErr)
	}
}

func writeJSONResponse(w http.ResponseWriter, status int, payload ingest.APIResponse) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, err := w.Write([]byte(fmt.Sprintf(
		`{"accepted":%s,"error_code":"%s","message":"%s"}`,
		strconv.FormatBool(payload.Accepted), payload.ErrorCode, payload.Message,
	)))
	return err
}

func writeJSONMap(w http.ResponseWriter, status int, payload map[string]interface{}) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	ok, _ := payload["ok"].(bool)
	errorCode, _ := payload["error_code"].(string)
	body := `{"ok":` + strconv.FormatBool(ok)
	if errorCode != "" {
		body += `,"error_code":"` + errorCode + `"`
	}
	body += "}"
	_, err := w.Write([]byte(body))
	return err
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

var requestIDPattern = regexp.MustCompile(`^[a-zA-Z0-9._:-]{1,128}$`)

func sanitizeOrGenerateRequestID(incoming string) string {
	requestID := incoming
	if !requestIDPattern.MatchString(requestID) {
		requestID = fmt.Sprintf("req-%d", time.Now().UnixNano())
	}
	return requestID
}

type minuteLimiter struct {
	limit      int
	window     int64
	count      int
	windowLock sync.Mutex
}

func newMinuteLimiter(limit int) *minuteLimiter {
	return &minuteLimiter{limit: limit, window: time.Now().Unix() / 60}
}

func (l *minuteLimiter) Enabled() bool {
	return l.limit > 0
}

func (l *minuteLimiter) Allow() bool {
	allowed := true
	l.windowLock.Lock()
	currentWindow := time.Now().Unix() / 60
	if currentWindow != l.window {
		l.window = currentWindow
		l.count = 0
	}
	if l.count >= l.limit {
		allowed = false
	}
	if allowed {
		l.count++
	}
	l.windowLock.Unlock()
	return allowed
}
