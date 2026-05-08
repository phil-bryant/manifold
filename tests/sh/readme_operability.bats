#!/usr/bin/env bats

@test "README documents startup and env requirements" {
  run rg "MANIFOLD_INGEST_KEY" README.md
  [ "$status" -eq 0 ]
  run rg "MANIFOLD_DATABASE_URL" README.md
  [ "$status" -eq 0 ]
  run rg "go run ./cmd/manifold" README.md
  [ "$status" -eq 0 ]
}

@test "README documents ingest curl and health endpoints" {
  run rg "POST /v1/events/batch" README.md
  [ "$status" -eq 0 ]
  run rg "curl -i" README.md
  [ "$status" -eq 0 ]
  run rg "/healthz" README.md
  [ "$status" -eq 0 ]
  run rg "/readyz" README.md
  [ "$status" -eq 0 ]
}
