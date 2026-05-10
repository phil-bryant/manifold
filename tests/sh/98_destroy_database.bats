#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "98_destroy_database.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails clearly when 1psa is missing" {
  #R001 #R005
  run bash "${FIXTURE_ROOT}/98_destroy_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "wrong confirmation cancels before teardown commands" {
  #R010
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
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'nope\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Destruction cancelled"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"psql "* ]]
}

@test "successful confirmation runs cleanup and prints completion" {
  #R015 #R020 #R025
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
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleanup complete!"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"-h db.internal -p 6543"* ]]
  [[ "$calls" == *"DROP DATABASE IF EXISTS manifold;"* ]]
  [[ "$calls" == *"DROP ROLE IF EXISTS manifold;"* ]]
}
