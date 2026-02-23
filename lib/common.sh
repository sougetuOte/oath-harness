#!/bin/bash
# oath-harness common utilities
# Path constants, logging, jq wrappers, flock utilities
set -euo pipefail

# --- Path constants ---
# Resolve HARNESS_ROOT from this file's location (lib/common.sh -> project root)
if [[ -z "${HARNESS_ROOT:-}" ]]; then
    HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

CONFIG_DIR="${CONFIG_DIR:-${HARNESS_ROOT}/config}"
STATE_DIR="${STATE_DIR:-${HARNESS_ROOT}/state}"
AUDIT_DIR="${AUDIT_DIR:-${HARNESS_ROOT}/audit}"
LIB_DIR="${LIB_DIR:-${HARNESS_ROOT}/lib}"
SETTINGS_FILE="${SETTINGS_FILE:-${CONFIG_DIR}/settings.json}"
TRUST_SCORES_FILE="${TRUST_SCORES_FILE:-${STATE_DIR}/trust-scores.json}"

# --- Logging ---

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    if [[ "${OATH_DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# --- Float comparison ---
# Returns 0 (true) if the awk numeric expression is true.
# Usage: _float_cmp "0.3 > 0.5"
_float_cmp() {
    awk "BEGIN { exit !($1) }"
}

# --- flock wrapper ---
# Executes a command under an exclusive file lock.
# Args: lockfile, command..., [timeout_seconds]
with_flock() {
    local lockfile="$1"
    local timeout="$2"
    shift 2

    (
        if ! flock -w "${timeout}" 200; then
            log_error "flock timeout after ${timeout}s on: ${lockfile}"
            return 1
        fi
        "$@"
    ) 200>"${lockfile}.lock"
}

# --- Atomic file write ---
# Write content to a file atomically using tmp + mv pattern (ADR-0003)
# Args: target_file (string), content (string, stdin or $2)
atomic_write() {
    local target="$1"
    local tmp="${target}.tmp.$$"
    if cat > "${tmp}" && mv "${tmp}" "${target}"; then
        return 0
    else
        rm -f "${tmp}"
        log_error "atomic_write: failed to write ${target}"
        return 1
    fi
}

# --- ISO 8601 datetime ---
now_iso8601() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# --- Session ID ---
generate_session_id() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # Fallback: generate UUID-like string from /dev/urandom
        local hex
        hex="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
        printf '%s-%s-%s-%s-%s\n' \
            "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
    fi
}
