# Verify Requirements Traceability Requirements

## Scope

Applies to `00_verify_requirements_traceability.sh` and requirement/test traceability policy in this repository.

R001  Statement: Run in strict shell mode with temporary working files.
Design: Use `umask 007`, `set -euo pipefail`, and `mktemp` files for set operations.
Tests:
- Verify script exits when required variables are unset.

R005  Statement: Discover and verify all `requirements/**/*-requirements.md` files by default.
Design: Enumerate requirement docs from the `requirements/` directory recursively and verify each discovered `*-requirements.md` doc in one run.
Tests:
- Run with no args and verify all discovered requirements documents are visited.

R010  Statement: Resolve source files referenced by each requirements document.
Design: Parse backticked source file paths from requirements scope/design text and verify each matching source file for that document.
Tests:
- Add a second source file reference to one requirements doc and verify both are checked.

R015  Statement: Fail clearly when discovered files or mappings are missing.
Design: For each requirements file, fail when no source files are discoverable or when a referenced source file does not exist unless requirements-only mode is explicitly declared.
Tests:
- Remove a referenced source file and verify explicit non-zero failure output.
- Provide a requirements file with no discoverable source mapping and verify explicit non-zero failure output.

R020  Statement: Parse requirement IDs from requirement-file start-of-line entries.
Design: Extract IDs matching `R###` with optional `-###` suffix and deduplicate.
Tests:
- Include duplicate IDs in requirements and verify deduped set behavior.

R025  Statement: Parse all `#R` tags from source content.
Design: Scan each line for one or many `#R###` tags with optional `-###` suffix.
Tests:
- Add multiple tags in one source line and verify each is extracted.

R030  Statement: Report missing and extra traceability IDs as set differences.
Design: Use `comm` comparisons against sorted unique ID sets.
Tests:
- Remove one source tag and verify it appears in missing list.
- Add unknown source tag and verify it appears in extra list.

R035  Statement: Exit success only when every enforceable traceability comparison matches.
Design: Return `0` only when all discovered requirements files and their source/test checks have no missing or extra IDs; otherwise return `1`.
Tests:
- Verify all discovered pairs matching returns pass.
- Verify any discovered mismatch returns non-zero.

R040  Statement: Enforce numbered script coverage by numbered requirements docs.
Design: During full-run mode, compare repository `NN_*.sh`/`NN_*.py` scripts against `requirements/NN_*-requirements.md` and fail when any numbered script lacks a matching numbered requirements document.
Tests:
- Add a numbered script without a matching numbered requirements doc and verify explicit failure output.
- Add matching numbered requirements doc and verify coverage pass output.

R045  Statement: Enforce numbered requirements scope alignment with numbered scripts.
Design: For each `requirements/NN_*-requirements.md`, require at least one numbered source reference in Scope that starts with the same `NN_` prefix.
Tests:
- Point a numbered requirements file to a differently numbered script and verify explicit mismatch failure.
- Point it back to matching `NN_` source and verify alignment pass output.

R050  Statement: Discover candidate test files for each requirements document.
Design: Infer test files from requirements path and scoped source conventions, including `tests/sh`, `tests/py`, and top-level `Makefile` mapping to `tests/sh/Makefile.bats`, while canonicalizing symlinked test paths.
Tests:
- Verify shell-script requirements discover matching `tests/sh/*.bats` candidates.
- Verify top-level `Makefile` requirements discover `tests/sh/Makefile.bats`.
- Verify python requirements discover `tests/py/test_*.py` candidates.

R055  Statement: Parse `#R` tags from discovered test files.
Design: Reuse `#R###(-###)*` extraction to build deduplicated requirement-coverage ID sets from discovered tests.
Tests:
- Include multiple tags per test file line and verify extraction still captures all IDs.

R060  Statement: Enforce at least one tagged test per requirement ID for enforceable docs.
Design: For requirements docs with source mappings, fail when any requirement ID lacks tagged coverage from discovered tests.
Tests:
- Remove all tagged tests for one ID and verify explicit missing-ID failure output.
- Restore coverage and verify pass output.

R065  Statement: Reject anti-cheat header bundles and require scoped source comments.
Design: Fail when files use top-of-file bundled tags and require scoped traceability comments (`#R###:`) over implementation blocks.
Tests:
- Provide only bundled header tags and verify explicit anti-cheat failure.
- Provide unscoped tags and verify scoped-comment failure.
- Provide scoped comments and verify pass.

R070  Statement: Support explicit requirements-only mode for pre-implementation documents.
Design: If a requirements file declares `Requirements-only mode: true` in `## Scope`, skip source and test traceability checks for that file and report a pass-with-skip status.
Tests:
- Create a requirements-only doc with no source mappings and verify the verifier skips it successfully.
- Remove the requirements-only declaration and verify missing-source failure resumes.

R075  Statement: Enforce repository Go package `_test.go` coverage in full-run mode.
Design: During no-argument full-run mode, if `go.mod` exists, enumerate `go list -json ./...` and fail when any package has Go source files but no `TestGoFiles`/`XTestGoFiles`.
Tests:
- Run verifier in a Go-module fixture containing a package with `.go` files but no `_test.go` and verify explicit failure output.
- Add matching `_test.go` coverage and verify pass output.

R080  Statement: Discover Go package `_test.go` files for per-file requirements traceability.
Design: When requirements scope includes `.go` source files, discover all sibling package `*_test.go` files and include them in requirement-ID tagged test coverage checks.
Tests:
- Use a fixture requirements doc scoped to a Go source and verify sibling `*_test.go` files are discovered.
- Omit required `#R` tags from discovered Go tests and verify explicit missing tagged-test failure.

## Changelog

- 2026-05-09: Added Go package test discovery requirement for per-file Go traceability docs.
- 2026-05-08: Reswizzled for Manifold requirements-first workflow, added requirements-only mode, and removed stale UI-lane assumptions.
- 2026-05-07: Reswizzled discovery conventions for Piston (`Tests/sh` + SwiftPM `Tests/`) and removed email app-specific paths.
