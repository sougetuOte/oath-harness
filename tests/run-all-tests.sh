#!/bin/bash
# Run all tests (unit + integration)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Unit Tests ==="
bash "${SCRIPT_DIR}/run-unit-tests.sh"

echo ""
echo "=== Integration Tests ==="
bash "${SCRIPT_DIR}/run-integration-tests.sh"

echo ""
echo "=== All tests passed ==="
