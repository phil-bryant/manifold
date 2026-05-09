package ingest

import "manifold/model"

type BatchRequest = model.BatchRequest
type EventRecord = model.EventRecord
type PersistResult = model.PersistResult

type APIResponse struct {
	Accepted            bool   `json:"accepted"`
	BatchID             string `json:"batch_id,omitempty"`
	AcceptedEventCount  int    `json:"accepted_event_count,omitempty"`
	DuplicateEventCount int    `json:"duplicate_event_count,omitempty"`
	RejectedEventCount  int    `json:"rejected_event_count,omitempty"`
	ErrorCode           string `json:"error_code,omitempty"`
	Message             string `json:"message,omitempty"`
	Path                string `json:"path,omitempty"`
}

type ValidationError struct {
	Code    string
	Message string
	Path    string
}

func (e ValidationError) Error() string {
	return e.Message
}
