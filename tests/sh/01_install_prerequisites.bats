#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_PATH="${REPO_ROOT}/01_install_prerequisites.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  mkdir -p "${STUB_BIN}"
}

teardown() {
  if [ -d "${TMP_ROOT}" ]; then
    mv "${TMP_ROOT}" "${TMP_ROOT}.trash.$$" || true
  fi
}

create_brew_stub() {
  cat > "${STUB_BIN}/brew" <<'EOF'
#!/bin/bash
if [ "$1" = "--prefix" ] && [ "$2" = "libpq" ]; then
  echo "${STUB_BIN}/opt/libpq"
  exit 0
fi
if [ "$1" = "install" ]; then
  FORMULA="$2"
  printf "install %s\n" "${FORMULA}" >> "${BREW_LOG}"
  if [ "${FORMULA}" = "libpq" ]; then
    mkdir -p "${STUB_BIN}/opt/libpq/bin"
    cat > "${STUB_BIN}/opt/libpq/bin/psql" <<'INNER'
#!/bin/bash
exit 0
INNER
    chmod +x "${STUB_BIN}/opt/libpq/bin/psql"
    exit 0
  fi
  cat > "${STUB_BIN}/${FORMULA}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${FORMULA}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"
}

@test "R001: script uses strict fail-fast mode" {
  #R001
  run rg "set -euo pipefail" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R005: fails with guidance when Homebrew is missing" {
  #R005
  run env PATH="/usr/bin:/bin" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"[Homebrew] Not installed."* ]]
  [[ "${output}" == *"install.sh"* ]]
}

@test "R010,R025,R030: installs Go and tooling formulas when missing" {
  #R010 #R025 #R030
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.1 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  run rg "^install libpq$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install golangci-lint$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install gosec$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install govulncheck$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
}

@test "R015: fails when Go version is below minimum" {
  #R015
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.20.4 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"below required"* ]]
}

@test "R020,R035,R045,R050: accepts libpq prefix fallback and prints Go guidance" {
  #R020 #R035 #R045 #R050
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.7 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Go Version"* ]]
  [[ "${output}" == *"go test ./..."* ]]
  [[ "${output}" == *"go test -race ./..."* ]]
  [[ "${output}" == *"golangci-lint run"* ]]
  [[ "${output}" == *"MANIFOLD_DATABASE_URL"* ]]
  run rg "^install libpq$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
}

@test "R020: fails when psql remains unavailable after libpq install" {
  #R020
  mkdir -p "${STUB_BIN}/opt/libpq/bin"
  cat > "${STUB_BIN}/brew" <<'EOF'
#!/bin/bash
if [ "$1" = "--prefix" ] && [ "$2" = "libpq" ]; then
  echo "${STUB_BIN}/opt/libpq"
  exit 0
fi
if [ "$1" = "install" ] && [ "$2" = "libpq" ]; then
  exit 0
fi
if [ "$1" = "install" ]; then
  cat > "${STUB_BIN}/$2" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/$2"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.3 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" STUB_BIN="${STUB_BIN}" BREW_LOG="${TMP_ROOT}/brew.log" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"psql still unavailable"* ]]
}

@test "R040: reruns are idempotent and skip redundant installs" {
  #R040
  create_brew_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
if [ "$1" = "version" ]; then
  echo "go version go1.22.8 darwin/arm64"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/go"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run rg "^install libpq$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install golangci-lint$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install gosec$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install govulncheck$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
}
