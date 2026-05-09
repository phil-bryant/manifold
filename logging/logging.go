package logging

import (
	"log/slog"
	"os"
)

func NewLogger() *slog.Logger {
	// #R001: Provide centralized structured logger constructor.
	// #R005: Emit JSON logs to stdout for machine-readable ingestion.
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{})
	return slog.New(handler)
}
