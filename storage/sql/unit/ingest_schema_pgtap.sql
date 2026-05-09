SELECT plan(8);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'ingest_batches'
      AND table_type = 'BASE TABLE'
  ),
  'ingest_batches table exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'ingest_events'
      AND table_type = 'BASE TABLE'
  ),
  'ingest_events table exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'ingest_events'
      AND indexname = 'idx_ingest_events_timestamp'
  ),
  'timestamp index exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'ingest_events'
      AND indexname = 'idx_ingest_events_event_name'
  ),
  'event_name index exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'ingest_events'
      AND indexname = 'idx_ingest_events_component'
  ),
  'component index exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'ingest_events'
      AND indexname = 'idx_ingest_events_install_id'
  ),
  'install_id index exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class child_rel
      ON child_rel.oid = con.conrelid
    JOIN pg_namespace child_ns
      ON child_ns.oid = child_rel.relnamespace
    JOIN pg_class parent_rel
      ON parent_rel.oid = con.confrelid
    JOIN pg_namespace parent_ns
      ON parent_ns.oid = parent_rel.relnamespace
    WHERE con.contype = 'f'
      AND child_ns.nspname = 'public'
      AND child_rel.relname = 'ingest_events'
      AND parent_ns.nspname = 'public'
      AND parent_rel.relname = 'ingest_batches'
  ),
  'ingest_events references ingest_batches'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ingest_batches'
      AND column_name = 'raw_json'
      AND data_type = 'jsonb'
  ),
  'raw_json column uses jsonb'
);

SELECT * FROM finish();
