package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"manifold/config"
	"manifold/httpserver"
	"manifold/ingest"
	"manifold/logging"
	"manifold/security"
	"manifold/storage"
)

func main() {
	exitCode := run()
	os.Exit(exitCode)
}

func run() int {
	logger := logging.NewLogger()
	cfg, err := config.LoadFromEnv()
	if err != nil {
		logger.Error("configuration error", "error", err)
		return 1
	}
	store, err := storage.NewPostgresStore(cfg.DatabaseURL)
	if err != nil {
		logger.Error("database initialization failed", "error", err)
		return 1
	}
	defer func() {
		closeErr := store.Close()
		if closeErr != nil {
			log.Printf("close error: %v", closeErr)
		}
	}()
	err = store.ApplySchema(context.Background(), storage.SchemaSQL)
	if err != nil {
		logger.Error("schema apply failed", "error", err)
		return 1
	}
	limits := ingest.Limits{
		MaxEventsPerBatch: cfg.MaxEventsPerBatch,
		MaxEventBytes:     cfg.MaxEventBytes,
		MaxFieldsPerEvent: cfg.MaxFieldsPerEvent,
		MaxFieldStrBytes:  cfg.MaxFieldStrBytes,
	}
	validator := security.NewIngestKeyValidator(cfg.IngestKey)
	ingestHandler := ingest.NewHandler(cfg.MaxBodyBytes, limits, validator, store, logger)
	server := httpserver.NewServer(cfg.Addr, store, ingestHandler, logger, cfg.RequestsPerMinute)
	serverErrors := make(chan error, 1)
	go func() {
		serverErrors <- server.ListenAndServe()
	}()
	stopSignals := make(chan os.Signal, 1)
	signal.Notify(stopSignals, syscall.SIGTERM, syscall.SIGINT)
	exitCode := 0
	select {
	case listenErr := <-serverErrors:
		if !errors.Is(listenErr, http.ErrServerClosed) {
			logger.Error("server terminated unexpectedly", "error", listenErr)
			exitCode = 1
		}
	case <-stopSignals:
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		shutdownErr := server.Shutdown(ctx)
		if shutdownErr != nil {
			logger.Error("server shutdown failed", "error", shutdownErr)
			exitCode = 1
		}
	}
	return exitCode
}
