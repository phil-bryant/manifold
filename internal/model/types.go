package model

type BatchRequest struct {
	BatchID string        `json:"batch_id"`
	SentAt  string        `json:"sent_at"`
	Events  []EventRecord `json:"events"`
}

type EventRecord struct {
	SchemaVersion int                    `json:"schema_version"`
	EventID       string                 `json:"event_id"`
	Timestamp     string                 `json:"timestamp"`
	Level         string                 `json:"level"`
	Event         string                 `json:"event"`
	Component     string                 `json:"component"`
	InstallID     string                 `json:"install_id"`
	Fields        map[string]interface{} `json:"fields"`
}

type PersistResult struct {
	BatchID            string
	AcceptedEventCount int
	DuplicateCount     int
}
