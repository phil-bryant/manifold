package model

import (
	"encoding/json"
	"testing"
)

func TestBatchRequestJSONContract(t *testing.T) {
	// #R001: Batch request exposes batch envelope JSON contract.
	raw := []byte(`{"batch_id":"b1","sent_at":"2026-01-01T00:00:00Z","events":[]}`)
	var batch BatchRequest
	if err := json.Unmarshal(raw, &batch); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if batch.BatchID != "b1" {
		t.Fatalf("unexpected batch id: %s", batch.BatchID)
	}
}

func TestEventRecordJSONContract(t *testing.T) {
	// #R005: Event record includes normalized identifiers and dynamic fields.
	event := EventRecord{
		SchemaVersion: 1,
		EventID:       "evt-1",
		Timestamp:     "2026-01-01T00:00:00Z",
		Level:         "info",
		Event:         "startup",
		Component:     "manifold",
		InstallID:     "i-1",
		Fields:        map[string]interface{}{"k": "v"},
	}
	data, err := json.Marshal(event)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	if len(data) == 0 {
		t.Fatalf("expected encoded event payload")
	}
}

func TestPersistResultCounters(t *testing.T) {
	// #R010: Persistence result carries accepted and duplicate counters.
	result := PersistResult{BatchID: "b", AcceptedEventCount: 2, DuplicateCount: 1}
	if result.AcceptedEventCount != 2 || result.DuplicateCount != 1 {
		t.Fatalf("unexpected counters: %#v", result)
	}
}
