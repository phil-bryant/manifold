#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "99_restore_database.sh"
  mkdir -p "${FIXTURE_ROOT}/backups"
}

teardown() {
  teardown_shell_test
}

@test "fails when pg_restore is missing" {
  #R001 #R010 #R015
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  echo "localhost"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  echo "5432"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  echo "manifold"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "schema" ]; then
  echo "manifold"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  stub_cmd psql "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_restore is required"* ]]
}

@test "defaults to latest dump and reports completion path" {
  #R005 #R020 #R030 #R035
  old="${FIXTURE_ROOT}/backups/manifold_20250101_000000.dump"
  new="${FIXTURE_ROOT}/backups/manifold_20250102_000000.dump"
  touch "$old" "$new" "${FIXTURE_ROOT}/backups/manifold_20250102_000000_globals.sql"
  touch -t 202501010000 "$old"
  touch -t 202501020000 "$new"

  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  echo "db.internal"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  echo "6543"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  echo "manifold"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "schema" ]; then
  echo "manifold"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo ""
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  cat > "${STUB_BIN}/pg_restore" <<EOF
#!/usr/bin/env bash
echo pg_restore "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_restore"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete from: ${new}"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"psql -w -h db.internal -p 6543"* ]]
  [[ "$calls" == *"pg_restore -w -h db.internal -p 6543"* ]]
}

@test "fails when matching globals file is missing" {
  #R020
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  touch "$dump_path"
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  echo "localhost"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  echo "5432"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  echo "manifold"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "schema" ]; then
  echo "manifold"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Matching globals backup is missing"* ]]
}

@test "refuses restore when ingest schema objects already exist" {
  #R025
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  touch "$dump_path" "$globals_path"
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  echo "localhost"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  echo "5432"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  echo "manifold"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "schema" ]; then
  echo "manifold"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo "1"
elif [[ "$*" == *"c.relname = 'ingest_batches'"* ]] && [[ "$*" == *"n.nspname = 'manifold'"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already contains ingest schema objects"* ]]
}

@test "full restore replays globals then database content" {
  #R030 #R035
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  touch "$dump_path" "$globals_path"
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-p" ]; then
  echo "postgres-pass"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "host" ]; then
  echo "db.internal"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "port" ]; then
  echo "6543"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "database" ]; then
  echo "manifold"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "localhost_postgres_manifold" ] && [ "$3" = "schema" ]; then
  echo "manifold"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo ""
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  cat > "${STUB_BIN}/pg_restore" <<EOF
#!/usr/bin/env bash
echo pg_restore "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_restore"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"psql -w -h db.internal -p 6543 -v ON_ERROR_STOP=1 -U postgres -d postgres -f $globals_path"* ]]
  [[ "$calls" == *"pg_restore -w -h db.internal -p 6543 -U postgres -d postgres --clean --if-exists --create $dump_path"* ]]
}
