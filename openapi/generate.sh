#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_PATH="${SCRIPT_DIR}/manifold.v1.yaml"
CONFIG_PATH="${SCRIPT_DIR}/oapi-codegen.yaml"
cd "${SCRIPT_DIR}"

go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.5.0 \
  --config "${CONFIG_PATH}" \
  "${SPEC_PATH}"
