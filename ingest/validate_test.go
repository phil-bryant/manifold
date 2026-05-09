package ingest

import "testing"

func validBatch() BatchRequest {
	return BatchRequest{
		BatchID: "batch-1",
		SentAt:  "2026-05-08T02:00:00Z",
		Events: []EventRecord{
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

func limits() Limits {
	return Limits{MaxEventsPerBatch: 3, MaxEventBytes: 1024, MaxFieldsPerEvent: 4, MaxFieldStrBytes: 16}
}

func TestValidateBatchSuccess(t *testing.T) {
	err := ValidateBatch(validBatch(), limits())
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestValidateBatchTooManyEvents(t *testing.T) {
	batch := validBatch()
	batch.Events = append(batch.Events, batch.Events[0], batch.Events[0], batch.Events[0])
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestValidateBatchRejectsNestedField(t *testing.T) {
	batch := validBatch()
	batch.Events[0].Fields["nested"] = map[string]interface{}{"a": "b"}
	err := ValidateBatch(batch, limits())
	validationErr, ok := err.(ValidationError)
	if !ok {
		t.Fatalf("expected ValidationError")
	}
	if validationErr.Path == "" {
		t.Fatalf("expected error path")
	}
}

func TestValidateBatchRejectsDenylistedKey(t *testing.T) {
	batch := validBatch()
	batch.Events[0].Fields["auth_token"] = "bad"
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected denylist failure")
	}
}
