#!/bin/bash
# oath-harness Stop hook
# Persists trust scores and finalizes session on exit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Stop errors must never block the session from ending
trap 'exit 0' ERR

# Source lib modules in dependency order
# shellcheck source=../lib/common.sh
source "${HARNESS_ROOT}/lib/common.sh"
# shellcheck source=../lib/config.sh
source "${HARNESS_ROOT}/lib/config.sh"
# shellcheck source=../lib/trust-engine.sh
source "${HARNESS_ROOT}/lib/trust-engine.sh"
# shellcheck source=../lib/bootstrap.sh
source "${HARNESS_ROOT}/lib/bootstrap.sh"
# shellcheck source=../lib/audit.sh
source "${HARNESS_ROOT}/lib/audit.sh"

# --- Main flow ---

config_load

# Update trust-scores.json with the current timestamp.
# Skipped when the file does not exist (no tool calls were made this session).
# Errors are absorbed so the stop hook always returns cleanly.
_stop_update_timestamp() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi

    local tmp_file="${TRUST_SCORES_FILE}.tmp"
    if jq --arg ts "$(now_iso8601)" '.updated_at = $ts' "${TRUST_SCORES_FILE}" > "${tmp_file}" 2>/dev/null; then
        mv "${tmp_file}" "${TRUST_SCORES_FILE}" || rm -f "${tmp_file}"
    else
        rm -f "${tmp_file}"
        log_debug "stop: skipping updated_at update (corrupted trust-scores.json)"
    fi
}

with_flock "${TRUST_SCORES_FILE}" 5 _stop_update_timestamp || true

atl_flush

exit 0
