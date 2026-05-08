package ingest

import (
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
)

var (
	identifierPattern = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)
	allowedLevels     = []string{"debug", "info", "warn", "error"}
	denylistedKeys    = []string{"auth_token", "password", "secret", "access_token", "refresh_token", "bearer", "authorization"}
)

type Limits struct {
	MaxEventsPerBatch int
	MaxEventBytes     int
	MaxFieldsPerEvent int
	MaxFieldStrBytes  int
}

func ValidateBatch(batch BatchRequest, limits Limits) error {
	var err error
	if strings.TrimSpace(batch.BatchID) == "" {
		err = ValidationError{Code: "invalid_schema", Message: "batch_id is required", Path: "batch_id"}
	}
	if err == nil {
		_, parseErr := time.Parse(time.RFC3339, batch.SentAt)
		if parseErr != nil {
			err = ValidationError{Code: "invalid_schema", Message: "sent_at must be RFC3339", Path: "sent_at"}
		}
	}
	if err == nil && len(batch.Events) == 0 {
		err = ValidationError{Code: "invalid_schema", Message: "events must not be empty", Path: "events"}
	}
	if err == nil && len(batch.Events) > limits.MaxEventsPerBatch {
		err = ValidationError{Code: "too_many_events", Message: "too many events in batch", Path: "events"}
	}
	index := 0
	for err == nil && index < len(batch.Events) {
		err = validateEvent(batch.Events[index], index, limits)
		index++
	}
	return err
}

func validateEvent(event EventRecord, index int, limits Limits) error {
	pathPrefix := fmt.Sprintf("events[%d]", index)
	var err error
	if event.SchemaVersion != 1 {
		err = ValidationError{Code: "invalid_schema", Message: "schema_version must be 1", Path: pathPrefix + ".schema_version"}
	}
	if err == nil && strings.TrimSpace(event.EventID) == "" {
		err = ValidationError{Code: "invalid_schema", Message: "event_id is required", Path: pathPrefix + ".event_id"}
	}
	if err == nil {
		_, parseErr := time.Parse(time.RFC3339, event.Timestamp)
		if parseErr != nil {
			err = ValidationError{Code: "invalid_schema", Message: "timestamp must be RFC3339", Path: pathPrefix + ".timestamp"}
		}
	}
	if err == nil && !slices.Contains(allowedLevels, event.Level) {
		err = ValidationError{Code: "invalid_schema", Message: "invalid level", Path: pathPrefix + ".level"}
	}
	if err == nil && !identifierPattern.MatchString(event.Event) {
		err = ValidationError{Code: "invalid_schema", Message: "invalid event identifier", Path: pathPrefix + ".event"}
	}
	if err == nil && !identifierPattern.MatchString(event.Component) {
		err = ValidationError{Code: "invalid_schema", Message: "invalid component identifier", Path: pathPrefix + ".component"}
	}
	if err == nil && len(event.Fields) > limits.MaxFieldsPerEvent {
		err = ValidationError{
			Code: "invalid_schema", Message: "fields key count exceeds max", Path: pathPrefix + ".fields",
		}
	}
	if err == nil {
		raw, marshalErr := json.Marshal(event)
		if marshalErr != nil {
			err = ValidationError{Code: "invalid_schema", Message: "event cannot be encoded", Path: pathPrefix}
		}
		if err == nil && len(raw) > limits.MaxEventBytes {
			err = ValidationError{Code: "invalid_schema", Message: "event payload too large", Path: pathPrefix}
		}
	}
	for key, value := range event.Fields {
		if err == nil {
			lower := strings.ToLower(strings.TrimSpace(key))
			if slices.Contains(denylistedKeys, lower) {
				err = ValidationError{
					Code: "invalid_schema", Message: "field key is not allowed", Path: pathPrefix + ".fields." + key,
				}
			}
		}
		if err == nil {
			err = validateFieldValue(value, limits.MaxFieldStrBytes, pathPrefix+".fields."+key)
		}
	}
	return err
}

func validateFieldValue(value interface{}, maxStringBytes int, path string) error {
	var err error
	switch typed := value.(type) {
	case nil, bool, float64:
	case string:
		if len([]byte(typed)) > maxStringBytes {
			err = ValidationError{Code: "invalid_schema", Message: "string field exceeds size limit", Path: path}
		}
	default:
		err = ValidationError{Code: "invalid_schema", Message: "field value must be scalar", Path: path}
	}
	return err
}
