package httpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"manifold/ingest"
	"manifold/internal/apiv1gen"
)

type ReadinessStore interface {
	Ping(ctx context.Context) error
}

type Server struct {
	server      *http.Server
	readinessDB ReadinessStore
	ingest      IngestService
	logger      *slog.Logger
	limiter     *minuteLimiter
}

type IngestService interface {
	ProcessBatch(ctx context.Context, providedKey string, batch ingest.BatchRequest, rawBody []byte) (int, ingest.APIResponse, []any)
}

func NewServer(addr string, db ReadinessStore, ingestService IngestService, logger *slog.Logger, requestsPerMinute int) *Server {
	server := &Server{
		readinessDB: db,
		ingest:      ingestService,
		logger:      logger,
		limiter:     newMinuteLimiter(requestsPerMinute),
	}
	strictImpl := &strictAPI{server: server}
	// #R001: Register ingest, health, and readiness API routes before serving traffic.
	strictHandler := apiv1gen.NewStrictHandlerWithOptions(strictImpl, nil, apiv1gen.StrictHTTPServerOptions{
		RequestErrorHandlerFunc: server.handleStrictRequestError,
		ResponseErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, _ error) {
			payload := ingest.APIResponse{Accepted: false, ErrorCode: "internal_error", Message: "internal server error"}
			_ = writeJSONResponse(w, http.StatusInternalServerError, payload)
		},
	})
	rootHandler := apiv1gen.HandlerWithOptions(strictHandler, apiv1gen.StdHTTPServerOptions{
		BaseRouter:  http.NewServeMux(),
		Middlewares: []apiv1gen.MiddlewareFunc{server.withMiddleware},
	})
	server.server = &http.Server{
		Addr:              addr,
		Handler:           rootHandler,
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

func writeJSONResponse(w http.ResponseWriter, status int, payload ingest.APIResponse) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, err := w.Write([]byte(fmt.Sprintf(
		`{"accepted":%s,"error_code":"%s","message":"%s"}`,
		strconv.FormatBool(payload.Accepted), payload.ErrorCode, payload.Message,
	)))
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

type strictAPI struct {
	server *Server
}

func (a *strictAPI) GetHealthz(_ context.Context, _ apiv1gen.GetHealthzRequestObject) (apiv1gen.GetHealthzResponseObject, error) {
	return apiv1gen.GetHealthz200JSONResponse{Ok: true}, nil
}

func (a *strictAPI) GetReadyz(ctx context.Context, _ apiv1gen.GetReadyzRequestObject) (apiv1gen.GetReadyzResponseObject, error) {
	// #R015: Report readiness based on storage ping availability.
	err := a.server.readinessDB.Ping(ctx)
	if err != nil {
		return apiv1gen.GetReadyz503JSONResponse{Ok: false, ErrorCode: strPtr("storage_unavailable")}, nil
	}
	return apiv1gen.GetReadyz200JSONResponse{Ok: true}, nil
}

func (a *strictAPI) PostEventsBatch(
	ctx context.Context, request apiv1gen.PostEventsBatchRequestObject,
) (apiv1gen.PostEventsBatchResponseObject, error) {
	if request.Body == nil {
		return mapPostEventsResponse(http.StatusBadRequest, ingest.APIResponse{
			Accepted: false, ErrorCode: "invalid_json", Message: "invalid JSON body",
		}), nil
	}
	rawBody, err := json.Marshal(request.Body)
	if err != nil {
		return mapPostEventsResponse(http.StatusInternalServerError, ingest.APIResponse{
			Accepted: false, ErrorCode: "internal_error", Message: "internal server error",
		}), nil
	}
	providedKey := ""
	if request.Params.XManifoldIngestKey != nil {
		providedKey = strings.TrimSpace(string(*request.Params.XManifoldIngestKey))
	}
	status, response, _ := a.server.ingest.ProcessBatch(ctx, providedKey, mapBatchRequest(*request.Body), rawBody)
	return mapPostEventsResponse(status, response), nil
}

func (s *Server) handleStrictRequestError(w http.ResponseWriter, r *http.Request, _ error) {
	payload := ingest.APIResponse{Accepted: false, ErrorCode: "invalid_json", Message: "invalid JSON body"}
	if r.URL.Path != "/v1/events/batch" {
		payload.ErrorCode = "invalid_request"
		payload.Message = "invalid request"
	}
	_ = writeJSONResponse(w, http.StatusBadRequest, payload)
}

func mapBatchRequest(in apiv1gen.BatchRequest) ingest.BatchRequest {
	events := make([]ingest.EventRecord, 0, len(in.Events))
	for _, event := range in.Events {
		events = append(events, ingest.EventRecord{
			SchemaVersion: event.SchemaVersion,
			EventID:       event.EventId,
			Timestamp:     event.Timestamp,
			Level:         string(event.Level),
			Event:         event.Event,
			Component:     event.Component,
			InstallID:     event.InstallId,
			Fields:        event.Fields,
		})
	}
	return ingest.BatchRequest{
		BatchID: in.BatchId,
		SentAt:  in.SentAt,
		Events:  events,
	}
}

func mapPostEventsResponse(status int, in ingest.APIResponse) apiv1gen.PostEventsBatchResponseObject {
	out := apiv1gen.APIResponse{Accepted: in.Accepted}
	if in.BatchID != "" {
		out.BatchId = strPtr(in.BatchID)
	}
	if in.AcceptedEventCount != 0 {
		out.AcceptedEventCount = intPtr(in.AcceptedEventCount)
	}
	if in.DuplicateEventCount != 0 {
		out.DuplicateEventCount = intPtr(in.DuplicateEventCount)
	}
	if in.RejectedEventCount != 0 {
		out.RejectedEventCount = intPtr(in.RejectedEventCount)
	}
	if in.ErrorCode != "" {
		out.ErrorCode = strPtr(in.ErrorCode)
	}
	if in.Message != "" {
		out.Message = strPtr(in.Message)
	}
	if in.Path != "" {
		out.Path = strPtr(in.Path)
	}
	switch status {
	case http.StatusOK:
		return apiv1gen.PostEventsBatch200JSONResponse(out)
	case http.StatusBadRequest:
		return apiv1gen.PostEventsBatch400JSONResponse(out)
	case http.StatusUnauthorized:
		return apiv1gen.PostEventsBatch401JSONResponse(out)
	case http.StatusConflict:
		return apiv1gen.PostEventsBatch409JSONResponse(out)
	case http.StatusRequestEntityTooLarge:
		return apiv1gen.PostEventsBatch413JSONResponse(out)
	case http.StatusUnsupportedMediaType:
		return apiv1gen.PostEventsBatch415JSONResponse(out)
	case http.StatusUnprocessableEntity:
		return apiv1gen.PostEventsBatch422JSONResponse(out)
	case http.StatusTooManyRequests:
		return apiv1gen.PostEventsBatch429JSONResponse(out)
	case http.StatusServiceUnavailable:
		return apiv1gen.PostEventsBatch503JSONResponse(out)
	default:
		return apiv1gen.PostEventsBatch500JSONResponse(out)
	}
}

func strPtr(v string) *string { return &v }
func intPtr(v int) *int       { return &v }
