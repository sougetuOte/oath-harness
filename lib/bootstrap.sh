#!/bin/bash
# oath-harness Session Trust Bootstrap
# Initializes trust scores at session start
set -euo pipefail

# Ensure the session is initialized. Idempotent — only runs once.
sb_ensure_initialized() {
    if [[ "${OATH_HARNESS_INITIALIZED:-}" == "1" ]]; then
        return 0
    fi

    # Generate session ID
    OATH_HARNESS_SESSION_ID="$(generate_session_id)"
    export OATH_HARNESS_SESSION_ID
    export OATH_HARNESS_INITIALIZED="1"

    # Handle missing file
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        _sb_create_default
        return 0
    fi

    # Validate JSON
    if ! jq '.' "${TRUST_SCORES_FILE}" > /dev/null 2>&1; then
        log_error "Corrupted trust-scores.json, resetting to defaults"
        _sb_create_default
        return 0
    fi

    # Check version for migration
    local version
    version="$(jq -r '.version // "1"' "${TRUST_SCORES_FILE}" 2>/dev/null)"

    if [[ "${version}" != "2" ]]; then
        _sb_migrate_v1_to_v2
    fi

    # Apply time decay to all domains
    te_apply_time_decay

    return 0
}

# Get the current session ID
sb_get_session_id() {
    if [[ -z "${OATH_HARNESS_SESSION_ID:-}" ]]; then
        sb_ensure_initialized
    fi
    echo "${OATH_HARNESS_SESSION_ID}"
}

# Create default trust-scores.json with initial state
_sb_create_default() {
    local initial_score
    initial_score="$(config_get "trust.initial_score")"
    local now
    now="$(now_iso8601)"

    mkdir -p "$(dirname "${TRUST_SCORES_FILE}")"

    jq -n --argjson s "${initial_score}" --arg t "${now}" '{
        version: "2",
        updated_at: $t,
        global_operation_count: 0,
        domains: {
            _global: {
                score: $s,
                successes: 0,
                failures: 0,
                total_operations: 0,
                last_operated_at: $t,
                is_warming_up: false,
                warmup_remaining: 0
            }
        }
    }' > "${TRUST_SCORES_FILE}"
}

# Migrate v1 format to v2
_sb_migrate_v1_to_v2() {
    local now
    now="$(now_iso8601)"

    local v1_score v1_successes v1_failures
    v1_score="$(jq -r '.score // 0.3' "${TRUST_SCORES_FILE}")"
    v1_successes="$(jq -r '.successes // 0' "${TRUST_SCORES_FILE}")"
    v1_failures="$(jq -r '.failures // 0' "${TRUST_SCORES_FILE}")"
    local total_ops=$(( v1_successes + v1_failures ))

    jq -n --argjson score "${v1_score}" \
          --argjson successes "${v1_successes}" \
          --argjson failures "${v1_failures}" \
          --argjson total_ops "${total_ops}" \
          --arg t "${now}" '{
        version: "2",
        updated_at: $t,
        global_operation_count: $total_ops,
        domains: {
            _global: {
                score: $score,
                successes: $successes,
                failures: $failures,
                total_operations: $total_ops,
                last_operated_at: $t,
                is_warming_up: false,
                warmup_remaining: 0
            }
        }
    }' > "${TRUST_SCORES_FILE}"
    log_info "Migrated trust-scores.json from v1 to v2"
}
