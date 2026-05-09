package ingest

import "manifold/model"

type BatchRequest = model.BatchRequest
type EventRecord = model.EventRecord
// #R001: Re-export persistence result contract through ingest package aliases.
type PersistResult = model.PersistResult

// #R005: Define stable API response envelope for ingest handlers.
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

// #R010: Carry validation metadata and expose message via Error().
type ValidationError struct {
	Code    string
	Message string
	Path    string
}

func (e ValidationError) Error() string {
	return e.Message
}
