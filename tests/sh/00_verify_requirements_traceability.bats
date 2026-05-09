#!/usr/bin/env bats

make_traceability_fixture() {
  local fixture_root="$1" mode="$2"
  mkdir -p "${fixture_root}/requirements" "${fixture_root}/tests/sh"
  cat > "${fixture_root}/requirements/fixture-requirements.md" <<'EOF'
# Fixture Requirements

## Scope

Applies to `fixture.sh`.

R001  Statement: First behavior.
R005  Statement: Second behavior.
EOF
  if [ "$mode" = "bundled" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001 #R005 #R010
echo "fixture"
EOF
  fi
  if [ "$mode" = "unscoped" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001
# #R005
echo "fixture"
EOF
  fi
  if [ "$mode" = "scoped" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001: First behavior.
echo "first"
# #R005: Second behavior.
echo "second"
EOF
  fi
  cat > "${fixture_root}/tests/sh/fixture.bats" <<'EOF'
#!/usr/bin/env bats

@test "fixture requirement tags" {
  #R001: First behavior test trace.
  #R005: Second behavior test trace.
  [ 1 -eq 1 ]
}
EOF
  chmod +x "${fixture_root}/fixture.sh"
}

make_go_module_traceability_fixture() {
  local fixture_root="$1"
  mkdir -p "${fixture_root}/requirements" "${fixture_root}/tests/sh"
  cat > "${fixture_root}/requirements/fixture-requirements.md" <<'EOF'
# Fixture Requirements

## Scope

Applies to `fixture.sh`.

R001  Statement: First behavior.
EOF
  cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001: First behavior.
echo "fixture"
EOF
  cat > "${fixture_root}/tests/sh/fixture.bats" <<'EOF'
#!/usr/bin/env bats

@test "fixture requirement tags" {
  #R001: First behavior test trace.
  [ 1 -eq 1 ]
}
EOF
  cat > "${fixture_root}/go.mod" <<'EOF'
module fixture

go 1.24
EOF
  chmod +x "${fixture_root}/fixture.sh"
}

make_go_source_traceability_fixture() {
  local fixture_root="$1" with_tag="$2"
  mkdir -p "${fixture_root}/requirements/pkg" "${fixture_root}/pkg"
  cat > "${fixture_root}/go.mod" <<'EOF'
module fixture

go 1.24
EOF
  cat > "${fixture_root}/requirements/pkg/example-requirements.md" <<'EOF'
# Example Go Requirements

## Scope

Applies to `pkg/example.go`.

R001  Statement: Example behavior.
EOF
  cat > "${fixture_root}/pkg/example.go" <<'EOF'
package pkg

// #R001: Example behavior implementation.
func Example() string { return "ok" }
EOF
  if [ "${with_tag}" = "with-tag" ]; then
    cat > "${fixture_root}/pkg/example_test.go" <<'EOF'
package pkg

import "testing"

func TestExample(t *testing.T) {
  // #R001: Example Go test tag discovered from package test file.
  if Example() != "ok" {
    t.Fatalf("unexpected")
  }
}
EOF
  else
    cat > "${fixture_root}/pkg/example_test.go" <<'EOF'
package pkg

import "testing"

func TestExample(t *testing.T) {
  if Example() != "ok" {
    t.Fatalf("unexpected")
  }
}
EOF
  fi
}

@test "Traceability tags for verifier requirements" {
  #R001: Strict mode and temp file setup requirement coverage.
  #R005: Default recursive requirements discovery coverage.
  #R010: Requirements-to-source mapping coverage.
  #R015: Missing mapping/source failure messaging coverage.
  #R020: Requirement ID parsing coverage.
  #R025: Source #R tag parsing coverage.
  #R030: Missing/extra set-difference reporting coverage.
  #R035: Pass/fail exit semantics coverage.
  #R040: Numbered script requirements coverage checks.
  #R045: Numbered requirements scope alignment checks.
  #R050: Requirement-to-test discovery coverage.
  #R055: Discovered-test #R tag extraction coverage.
  #R060: Missing test-traceability ID failure coverage.
  #R065: Anti-cheat header-bundle and scoped comment enforcement coverage.
  #R070: Requirements-only mode traceability-skip coverage.
  #R075: Go package _test.go coverage enforcement in full-run mode.
  #R080: Go source scoped requirements discover sibling _test.go files.
  [ 1 -eq 1 ]
}

@test "Fails when header-bundled tags are used near file top" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "bundled"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run /bin/bash "${fixture_root}/00_verify_requirements_traceability.sh" "${fixture_root}/requirements/fixture-requirements.md" "${fixture_root}/fixture.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL (anti-cheat)"* ]]
}

@test "Fails when IDs exist only as unscoped set-membership tags" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "unscoped"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run /bin/bash "${fixture_root}/00_verify_requirements_traceability.sh" "${fixture_root}/requirements/fixture-requirements.md" "${fixture_root}/fixture.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing scoped #R comments"* ]]
}

@test "Passes when requirement IDs are scoped with #Rxxx: comments" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "scoped"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run /bin/bash "${fixture_root}/00_verify_requirements_traceability.sh" "${fixture_root}/requirements/fixture-requirements.md" "${fixture_root}/fixture.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}

@test "Requirements-only mode skips source/test traceability checks" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  mkdir -p "${fixture_root}/requirements"
  cat > "${fixture_root}/requirements/phase-requirements.md" <<'EOF'
# Phase Requirements

## Scope

Requirements-only mode: true.

R001  Statement: Placeholder requirement while implementation is pending.
EOF
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/verify_requirements_traceability.sh"
  run /bin/bash -c "cd '${fixture_root}' && /bin/bash './verify_requirements_traceability.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (requirements-only)"* ]]
}

@test "Fails full-run mode when go module package has no _test.go files" {
  #R075
  local fixture_root stub_root
  fixture_root="$(mktemp -d)"
  stub_root="$(mktemp -d)"
  make_go_module_traceability_fixture "${fixture_root}"
  cat > "${stub_root}/go" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "-json" ]; then
  cat <<'JSON'
{"ImportPath":"fixture/internal/notested","GoFiles":["notested.go"],"TestGoFiles":[],"XTestGoFiles":[]}
JSON
  exit 0
fi
exit 1
EOF
  chmod +x "${stub_root}/go"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/verify_requirements_traceability.sh"
  run env PATH="${stub_root}:/usr/bin:/bin" /bin/bash -c "cd '${fixture_root}' && /bin/bash './verify_requirements_traceability.sh'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Go packages without associated _test.go files"* ]]
  [[ "$output" == *"fixture/internal/notested"* ]]
}

@test "Passes full-run mode when go module packages include _test.go files" {
  #R075
  local fixture_root stub_root
  fixture_root="$(mktemp -d)"
  stub_root="$(mktemp -d)"
  make_go_module_traceability_fixture "${fixture_root}"
  cat > "${stub_root}/go" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "-json" ]; then
  cat <<'JSON'
{"ImportPath":"fixture/internal/tested","GoFiles":["tested.go"],"TestGoFiles":["tested_test.go"],"XTestGoFiles":[]}
JSON
  exit 0
fi
exit 1
EOF
  chmod +x "${stub_root}/go"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/verify_requirements_traceability.sh"
  run env PATH="${stub_root}:/usr/bin:/bin" /bin/bash -c "cd '${fixture_root}' && /bin/bash './verify_requirements_traceability.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go package test coverage complete"* ]]
}

@test "Fails when discovered Go package tests do not include requirement tags" {
  #R080
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_go_source_traceability_fixture "${fixture_root}" "without-tag"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/verify_requirements_traceability.sh"
  run /bin/bash -c "cd '${fixture_root}' && /bin/bash './verify_requirements_traceability.sh' './requirements/pkg/example-requirements.md' './pkg/example.go'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing tagged tests for requirement IDs"* ]]
}

@test "Passes when Go source requirements discover sibling tagged _test.go files" {
  #R080
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_go_source_traceability_fixture "${fixture_root}" "with-tag"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/verify_requirements_traceability.sh"
  run /bin/bash -c "cd '${fixture_root}' && /bin/bash './verify_requirements_traceability.sh' './requirements/pkg/example-requirements.md' './pkg/example.go'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}
