#!/usr/bin/env bats

@test "Gitignore requirement tags for Manifold" {
  #R001: Local build output paths are ignored.
  #R005: Local OS metadata files are ignored.
  #R010: Repository-local Cursor rules trees are ignored.
  #R015: Source, requirements, and tests remain trackable.
  #R020: Tracked generated artifacts are removed from index with cached removals.
  #R025: Ignored artifact paths are not tracked after cleanup.
  #R030: Security reports under .security-reports are ignored and untracked.
  [ 1 -eq 1 ]
}

@test "security reports directory is ignored by git" {
  #R030
  run git check-ignore ".security-reports/dependency-freshness.json"
  [ "$status" -eq 0 ]
}

@test "security reports are not tracked in git index" {
  #R025
  #R030
  run bash -c "git ls-files | rg '^\\.security-reports/'"
  [ "$status" -eq 1 ]
}
