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
	// #R001: Valid batch envelope passes required-field and timestamp checks.
	err := ValidateBatch(validBatch(), limits())
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestValidateBatchTooManyEvents(t *testing.T) {
	// #R005: Batch exceeding max events is rejected.
	batch := validBatch()
	batch.Events = append(batch.Events, batch.Events[0], batch.Events[0], batch.Events[0])
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestValidateBatchRejectsNestedField(t *testing.T) {
	// #R020: Nested/non-scalar field values are rejected with path metadata.
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
	// #R020: Denylisted sensitive field keys are rejected.
	batch := validBatch()
	batch.Events[0].Fields["auth_token"] = "bad"
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected denylist failure")
	}
}

func TestValidateBatchRejectsInvalidEventIdentifiers(t *testing.T) {
	// #R010: Event schema identifiers and enum values are validated.
	batch := validBatch()
	batch.Events[0].Component = "bad component"
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected invalid identifier failure")
	}
}

func TestValidateBatchRejectsOversizedStringField(t *testing.T) {
	// #R015: Per-field string byte limits are enforced.
	batch := validBatch()
	batch.Events[0].Fields["long"] = "this string is definitely over sixteen bytes"
	err := ValidateBatch(batch, limits())
	if err == nil {
		t.Fatalf("expected oversized string validation failure")
	}
}

func TestValidationErrorReturnsMessage(t *testing.T) {
	// #R010: ValidationError.Error returns human-readable message.
	err := ValidationError{Code: "invalid_schema", Message: "boom", Path: "events[0]"}
	if err.Error() != "boom" {
		t.Fatalf("unexpected error string: %s", err.Error())
	}
}
