package storage

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	_ "github.com/jackc/pgx/v5/stdlib"
	"manifold/model"
)

var ErrDuplicateBatchConflict = errors.New("duplicate_batch_conflict")

type PostgresStore struct {
	db *sql.DB
}

func NewPostgresStore(databaseURL string) (*PostgresStore, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err == nil {
		err = db.Ping()
	}
	store := &PostgresStore{db: db}
	return store, err
}

func (s *PostgresStore) Close() error {
	return s.db.Close()
}

func (s *PostgresStore) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

func (s *PostgresStore) ApplySchema(ctx context.Context, schema string) error {
	_, err := s.db.ExecContext(ctx, schema)
	return err
}

func (s *PostgresStore) PersistBatch(ctx context.Context, batch model.BatchRequest, rawBody []byte) (model.PersistResult, error) {
	result := model.PersistResult{BatchID: batch.BatchID}
	hashBytes := sha256.Sum256(rawBody)
	payloadHash := hex.EncodeToString(hashBytes[:])
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{})
	if err == nil {
		err = s.persistBatchTransaction(ctx, tx, batch, rawBody, payloadHash, &result)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil && tx != nil {
		rollbackErr := tx.Rollback()
		if rollbackErr != nil && !errors.Is(rollbackErr, sql.ErrTxDone) {
			err = errors.Join(err, rollbackErr)
		}
	}
	return result, err
}

func (s *PostgresStore) persistBatchTransaction(
	ctx context.Context, tx *sql.Tx, batch model.BatchRequest, rawBody []byte, payloadHash string, result *model.PersistResult,
) error {
	var err error
	var existingHash string
	var existingCount int
	row := tx.QueryRowContext(
		ctx, "SELECT payload_hash, event_count FROM ingest_batches WHERE batch_id = $1", batch.BatchID,
	)
	scanErr := row.Scan(&existingHash, &existingCount)
	if scanErr == nil && existingHash != payloadHash {
		err = ErrDuplicateBatchConflict
	}
	if scanErr == nil && existingHash == payloadHash {
		result.AcceptedEventCount = existingCount
		result.DuplicateCount = existingCount
	}
	if scanErr != nil && !errors.Is(scanErr, sql.ErrNoRows) {
		err = scanErr
	}
	if err == nil && errors.Is(scanErr, sql.ErrNoRows) {
		sentAt, parseErr := time.Parse(time.RFC3339, batch.SentAt)
		if parseErr != nil {
			err = parseErr
		}
		rawJSON := json.RawMessage(rawBody)
		if err == nil {
			_, err = tx.ExecContext(
				ctx,
				"INSERT INTO ingest_batches(batch_id, payload_hash, raw_json, sent_at, received_at, event_count) "+
					"VALUES($1,$2,$3,$4,$5,$6)",
				batch.BatchID, payloadHash, rawJSON, sentAt, time.Now().UTC(), len(batch.Events),
			)
		}
		eventIndex := 0
		inserted := 0
		duplicates := 0
		for err == nil && eventIndex < len(batch.Events) {
			event := batch.Events[eventIndex]
			eventJSON, eventErr := json.Marshal(event)
			fieldsJSON, fieldsErr := json.Marshal(event.Fields)
			timestamp, tsErr := time.Parse(time.RFC3339, event.Timestamp)
			if eventErr != nil {
				err = eventErr
			}
			if err == nil && fieldsErr != nil {
				err = fieldsErr
			}
			if err == nil && tsErr != nil {
				err = tsErr
			}
			var rows sql.Result
			if err == nil {
				rows, err = tx.ExecContext(
					ctx,
					"INSERT INTO ingest_events(batch_id, event_id, schema_version, event_name, component, level, timestamp, "+
						"install_id, fields, raw_event, received_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) "+
						"ON CONFLICT(event_id) DO NOTHING",
					batch.BatchID, event.EventID, event.SchemaVersion, event.Event, event.Component, event.Level,
					timestamp, event.InstallID, json.RawMessage(fieldsJSON), json.RawMessage(eventJSON), time.Now().UTC(),
				)
			}
			if err == nil {
				affected, affectedErr := rows.RowsAffected()
				if affectedErr != nil {
					err = affectedErr
				}
				if err == nil && affected == 0 {
					duplicates++
				}
				if err == nil && affected > 0 {
					inserted++
				}
			}
			eventIndex++
		}
		if err == nil {
			result.AcceptedEventCount = inserted + duplicates
			result.DuplicateCount = duplicates
		}
	}
	return err
}

func IsUnavailable(err error) bool {
	unavailable := false
	var netErr net.Error
	var opErr *net.OpError
	var pgErr *pgconn.PgError
	if errors.As(err, &netErr) {
		unavailable = true
	}
	if errors.As(err, &opErr) {
		unavailable = true
	}
	if errors.As(err, &pgErr) {
		code := pgErr.Code
		unavailable = strings.HasPrefix(code, "08") || strings.HasPrefix(code, "53") || code == "57P01"
	}
	return unavailable
}
