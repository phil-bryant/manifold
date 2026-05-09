package ingest

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"strings"

	"manifold/security"
	"manifold/storage"
)

type BatchStore interface {
	PersistBatch(ctx context.Context, batch BatchRequest, rawBody []byte) (PersistResult, error)
}

type Handler struct {
	maxBodyBytes int
	limits       Limits
	validator    security.IngestKeyValidator
	store        BatchStore
	logger       *slog.Logger
}

func NewHandler(
	maxBodyBytes int, limits Limits, validator security.IngestKeyValidator, store BatchStore, logger *slog.Logger,
) Handler {
	return Handler{maxBodyBytes: maxBodyBytes, limits: limits, validator: validator, store: store, logger: logger}
}

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var status int
	response := APIResponse{}
	var logAttrs []any
	// #R001: Reject unsupported methods and content types before processing.
	if r.Method != http.MethodPost {
		status = http.StatusMethodNotAllowed
		response = APIResponse{Accepted: false, ErrorCode: "method_not_allowed", Message: "method not allowed"}
	}
	contentType, _, contentErr := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if status == 0 && (contentErr != nil || contentType != "application/json") {
		status = http.StatusUnsupportedMediaType
		response = APIResponse{
			Accepted: false, ErrorCode: "invalid_content_type", Message: "Content-Type must be application/json",
		}
	}
	// #R005: Enforce shared ingest-key authorization.
	providedKey := strings.TrimSpace(r.Header.Get("X-Manifold-Ingest-Key"))
	if status == 0 && !h.validator.IsAuthorized(providedKey) {
		status = http.StatusUnauthorized
		response = APIResponse{Accepted: false, ErrorCode: "unauthorized", Message: "invalid ingest key"}
	}
	// #R010: Enforce body-size bounds and readable JSON payloads.
	var rawBody []byte
	if status == 0 {
		r.Body = http.MaxBytesReader(w, r.Body, int64(h.maxBodyBytes))
		readBody, readErr := io.ReadAll(r.Body)
		rawBody = readBody
		if readErr != nil {
			var maxErr *http.MaxBytesError
			if errors.As(readErr, &maxErr) {
				status = http.StatusRequestEntityTooLarge
				response = APIResponse{Accepted: false, ErrorCode: "payload_too_large", Message: "request body too large"}
			}
			if status == 0 {
				status = http.StatusBadRequest
				response = APIResponse{Accepted: false, ErrorCode: "invalid_json", Message: "unable to read request body"}
			}
		}
	}
	// #R015: Validate decoded payload against ingest schema/limits before persistence.
	var batch BatchRequest
	// #R020: Map storage-layer outcomes to deterministic API status/error contracts.
	if status == 0 {
		decodeErr := json.Unmarshal(rawBody, &batch)
		if decodeErr != nil {
			status = http.StatusBadRequest
			response = APIResponse{Accepted: false, ErrorCode: "invalid_json", Message: "invalid JSON body"}
		}
	}
	if status == 0 {
		validateErr := ValidateBatch(batch, h.limits)
		if validateErr != nil {
			status = http.StatusUnprocessableEntity
			response = APIResponse{Accepted: false, BatchID: batch.BatchID, ErrorCode: "invalid_schema", Message: validateErr.Error()}
			var structuredErr ValidationError
			if errors.As(validateErr, &structuredErr) {
				response.ErrorCode = structuredErr.Code
				response.Path = structuredErr.Path
			}
		}
	}
	if status == 0 {
		persistResult, persistErr := h.store.PersistBatch(r.Context(), batch, rawBody)
		if persistErr != nil && errors.Is(persistErr, storage.ErrDuplicateBatchConflict) {
			status = http.StatusConflict
			response = APIResponse{
				Accepted: false, BatchID: batch.BatchID, ErrorCode: "duplicate_batch_conflict",
				Message: "batch_id already exists with different payload",
			}
		}
		if persistErr != nil && storage.IsUnavailable(persistErr) {
			status = http.StatusServiceUnavailable
			response = APIResponse{
				Accepted: false, BatchID: batch.BatchID, ErrorCode: "storage_unavailable", Message: "storage unavailable",
			}
		}
		if persistErr != nil && status == 0 {
			status = http.StatusInternalServerError
			response = APIResponse{
				Accepted: false, BatchID: batch.BatchID, ErrorCode: "internal_error", Message: "internal server error",
			}
		}
		if persistErr == nil {
			// #R025: Return successful acceptance envelope with persisted counters.
			status = http.StatusOK
			response = APIResponse{
				Accepted:            true,
				BatchID:             persistResult.BatchID,
				AcceptedEventCount:  persistResult.AcceptedEventCount,
				DuplicateEventCount: persistResult.DuplicateCount,
				RejectedEventCount:  0,
			}
			logAttrs = []any{"batch_id", persistResult.BatchID, "accepted_event_count", persistResult.AcceptedEventCount}
		}
	}
	writeErr := writeJSON(w, status, response)
	if writeErr != nil {
		h.logger.Error("write response failed", "error", writeErr)
	}
	h.logger.Info("ingest request completed", logAttrs...)
}

func writeJSON(w http.ResponseWriter, status int, payload APIResponse) error {
	data, err := json.Marshal(payload)
	if err == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, err = w.Write(data)
	}
	return err
}
