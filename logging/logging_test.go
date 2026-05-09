package logging

import (
	"io"
	"os"
	"strings"
	"testing"
)

func TestNewLoggerProvidesJSONStdoutLogger(t *testing.T) {
	// #R001: Logger constructor returns shared structured logger instance.
	// #R005: Logger emits JSON records to stdout output stream.
	originalStdout := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe setup failed: %v", err)
	}
	os.Stdout = writer
	t.Cleanup(func() {
		os.Stdout = originalStdout
	})

	logger := NewLogger()
	if logger == nil {
		t.Fatalf("expected non-nil logger")
	}
	logger.Info("hello")
	_ = writer.Close()
	bytes, readErr := io.ReadAll(reader)
	if readErr != nil {
		t.Fatalf("read failed: %v", readErr)
	}
	output := string(bytes)
	if !strings.Contains(output, "\"msg\":\"hello\"") {
		t.Fatalf("expected JSON output, got %q", output)
	}
}
