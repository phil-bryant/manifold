package config

import (
	"fmt"
	"os"
	"strconv"
)

const (
	defaultAddr              = ":8080"
	defaultMaxBodyBytes      = 1048576
	defaultMaxEventsPerBatch = 1000
	defaultMaxEventBytes     = 65536
	defaultMaxFieldsPerEvent = 128
	defaultMaxFieldStrBytes  = 2048
	defaultRequestsPerMinute = 0
)

type Config struct {
	Addr              string
	IngestKey         string
	DatabaseURL       string
	MaxBodyBytes      int
	MaxEventsPerBatch int
	MaxEventBytes     int
	MaxFieldsPerEvent int
	MaxFieldStrBytes  int
	RequestsPerMinute int
}

func LoadFromEnv() (Config, error) {
	// #R005: Seed immutable runtime config with deterministic defaults.
	cfg := Config{
		Addr:              getEnvOr("MANIFOLD_ADDR", defaultAddr),
		IngestKey:         os.Getenv("MANIFOLD_INGEST_KEY"),
		DatabaseURL:       os.Getenv("MANIFOLD_DATABASE_URL"),
		MaxBodyBytes:      defaultMaxBodyBytes,
		MaxEventsPerBatch: defaultMaxEventsPerBatch,
		MaxEventBytes:     defaultMaxEventBytes,
		MaxFieldsPerEvent: defaultMaxFieldsPerEvent,
		MaxFieldStrBytes:  defaultMaxFieldStrBytes,
		RequestsPerMinute: defaultRequestsPerMinute,
	}
	var err error
	// #R001: Fail when required ingest key or database URL are unset.
	if cfg.IngestKey == "" {
		err = fmt.Errorf("missing MANIFOLD_INGEST_KEY")
	}
	if err == nil && cfg.DatabaseURL == "" {
		err = fmt.Errorf("missing MANIFOLD_DATABASE_URL")
	}
	if err == nil {
		// #R010: Enforce positive numeric limits for ingest payload controls.
		cfg.MaxBodyBytes, err = parsePositiveIntFromEnv("MANIFOLD_MAX_BODY_BYTES", cfg.MaxBodyBytes)
	}
	if err == nil {
		cfg.MaxEventsPerBatch, err = parsePositiveIntFromEnv("MANIFOLD_MAX_EVENTS_PER_BATCH", cfg.MaxEventsPerBatch)
	}
	if err == nil {
		cfg.MaxEventBytes, err = parsePositiveIntFromEnv("MANIFOLD_MAX_EVENT_BYTES", cfg.MaxEventBytes)
	}
	if err == nil {
		cfg.MaxFieldsPerEvent, err = parsePositiveIntFromEnv("MANIFOLD_MAX_FIELDS_PER_EVENT", cfg.MaxFieldsPerEvent)
	}
	if err == nil {
		cfg.MaxFieldStrBytes, err = parsePositiveIntFromEnv("MANIFOLD_MAX_FIELD_STRING_BYTES", cfg.MaxFieldStrBytes)
	}
	if err == nil {
		// #R015: Allow disabled rate limiting as zero, reject negative values.
		cfg.RequestsPerMinute, err = parseNonNegativeIntFromEnv("MANIFOLD_REQUESTS_PER_MINUTE", cfg.RequestsPerMinute)
	}
	return cfg, err
}

func getEnvOr(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		value = fallback
	}
	return value
}

func parsePositiveIntFromEnv(key string, fallback int) (int, error) {
	value := fallback
	raw := os.Getenv(key)
	var err error
	if raw != "" {
		parsed, parseErr := strconv.Atoi(raw)
		if parseErr != nil || parsed <= 0 {
			err = fmt.Errorf("invalid %s: %q", key, raw)
		}
		if err == nil {
			value = parsed
		}
	}
	return value, err
}

func parseNonNegativeIntFromEnv(key string, fallback int) (int, error) {
	value := fallback
	raw := os.Getenv(key)
	var err error
	if raw != "" {
		parsed, parseErr := strconv.Atoi(raw)
		if parseErr != nil || parsed < 0 {
			err = fmt.Errorf("invalid %s: %q", key, raw)
		}
		if err == nil {
			value = parsed
		}
	}
	return value, err
}
