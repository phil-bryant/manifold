---
name: manifold-requirements-first
overview: Define Manifold’s full v1 requirements set before implementing service code, while only reswizzling the copied 00/01 traceability and prerequisites trio for this repository.
todos:
  - id: req-layout-baseline
    content: Reswizzle 00/01 requirements docs to Manifold context and preserve strict traceability conventions
    status: completed
  - id: author-manifold-domain-reqs
    content: Author the new Manifold domain requirements docs covering API, validation, storage, dedupe, security, config, ops, and README expectations
    status: completed
  - id: reswizzle-00-trio
    content: Adjust 00 verifier script and BATS only where required for Manifold requirements conventions
    status: completed
  - id: reswizzle-01-trio
    content: Adjust 01 prerequisites script and BATS for strict Go backend tooling prerequisites and idempotent setup
    status: completed
  - id: validate-traceability-tests
    content: Run traceability script and BATS tests to verify requirements-script-test alignment without implementing service code
    status: completed
isProject: false
---

# Manifold Requirements-First Plan

## Scope
- Write requirements documentation for Manifold v1 ingest service behavior, storage semantics, validation, security, ops, and test expectations.
- Do not implement ingest server/runtime code yet.
- Limit non-doc code changes to the copied `00_` and `01_` trio only (requirements + script + BATS), per your constraint.

## Requirements Document Layout
- Keep a hybrid layout matching the sibling style: numbered workflow docs plus domain docs in the flat `requirements/` directory.
- Preserve and reswizzle numbered workflow docs:
  - [requirements/00_verify_requirements_traceability-requirements.md](requirements/00_verify_requirements_traceability-requirements.md)
  - [requirements/01_install_prerequisites-requirements.md](requirements/01_install_prerequisites-requirements.md)
- Add Manifold domain requirement docs (flat files, non-numbered) for service behavior:
  - [requirements/manifold_ingest_api-requirements.md](requirements/manifold_ingest_api-requirements.md)
  - [requirements/manifold_validation_limits-requirements.md](requirements/manifold_validation_limits-requirements.md)
  - [requirements/manifold_storage_postgres-requirements.md](requirements/manifold_storage_postgres-requirements.md)
  - [requirements/manifold_dedup_idempotency-requirements.md](requirements/manifold_dedup_idempotency-requirements.md)
  - [requirements/manifold_security_ingest_key-requirements.md](requirements/manifold_security_ingest_key-requirements.md)
  - [requirements/manifold_ops_observability-requirements.md](requirements/manifold_ops_observability-requirements.md)
  - [requirements/manifold_config_runtime-requirements.md](requirements/manifold_config_runtime-requirements.md)
  - [requirements/manifold_readme_operability-requirements.md](requirements/manifold_readme_operability-requirements.md)

## Content Standards For Each New Requirements Doc
- Use the existing pattern: `## Scope`, then `R###` entries with `Statement`, `Design`, and `Tests` bullets.
- Encode your provided HTTP contract exactly (endpoint, status codes, response shape, batch-level acceptance).
- Encode explicit validation/limits and error-code taxonomy so later implementation/tests are deterministic.
- Include dedupe and conflict semantics (`event_id` idempotency, same `batch_id` same payload success, differing payload conflict).
- Include minimal-v1 architecture boundaries (Postgres required, object storage optional interface only).

## Reswizzle 00/01 Trio (Only Code Work In This Phase)
- Update [00_verify_requirements_traceability.sh](00_verify_requirements_traceability.sh) and [tests/sh/00_verify_requirements_traceability.bats](tests/sh/00_verify_requirements_traceability.bats) only as needed to validate Manifold’s requirements/test conventions rather than Fountain-specific assumptions.
- Update [01_install_prerequisites.sh](01_install_prerequisites.sh) and [tests/sh/01_install_prerequisites.bats](tests/sh/01_install_prerequisites.bats) to strict Go-backend prerequisites/tooling policy (Go + DB tooling + selected lint/security/dev utilities), idempotent behavior, and clear readiness output.
- Keep traceability complete by matching `R###` IDs between requirements, scripts, and BATS.

## Verification Pass
- Run the traceability verifier across all requirements docs.
- Run BATS coverage for the updated 00/01 tests.
- Confirm no Manifold runtime/server files are introduced yet; this phase remains requirements-first.
