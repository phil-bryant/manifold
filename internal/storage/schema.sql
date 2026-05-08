CREATE TABLE IF NOT EXISTS ingest_batches (
  id BIGSERIAL PRIMARY KEY,
  batch_id TEXT NOT NULL UNIQUE,
  payload_hash TEXT NOT NULL,
  raw_json JSONB NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  event_count INTEGER NOT NULL CHECK (event_count >= 0)
);

CREATE TABLE IF NOT EXISTS ingest_events (
  id BIGSERIAL PRIMARY KEY,
  batch_id TEXT NOT NULL REFERENCES ingest_batches(batch_id),
  event_id TEXT NOT NULL UNIQUE,
  schema_version INTEGER NOT NULL,
  event_name TEXT NOT NULL,
  component TEXT NOT NULL,
  level TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  install_id TEXT NOT NULL DEFAULT '',
  fields JSONB NOT NULL,
  raw_event JSONB NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ingest_events_timestamp ON ingest_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_ingest_events_event_name ON ingest_events(event_name);
CREATE INDEX IF NOT EXISTS idx_ingest_events_component ON ingest_events(component);
CREATE INDEX IF NOT EXISTS idx_ingest_events_install_id ON ingest_events(install_id);
