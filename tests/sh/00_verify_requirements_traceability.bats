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
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run /bin/bash "${fixture_root}/00_verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (requirements-only)"* ]]
}
