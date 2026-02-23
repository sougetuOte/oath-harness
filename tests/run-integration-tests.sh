#!/bin/bash
# Run all integration tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="${SCRIPT_DIR}/bats-core/bin/bats"

if [[ ! -x "${BATS}" ]]; then
    echo "Error: bats-core not found. Run: git submodule update --init" >&2
    exit 1
fi

"${BATS}" "${SCRIPT_DIR}"/integration/*.bats
