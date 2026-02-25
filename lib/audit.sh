#!/bin/bash
# oath-harness Audit Trail Logger
# JSONL logging for all tool calls
set -euo pipefail

# Sensitive key name pattern (case-insensitive match)
readonly _ATL_SENSITIVE_PATTERN='API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY|ACCESS_KEY'

# ---------------------------------------------------------------------------
# _atl_mask_sensitive
# Mask sensitive values in tool_input JSON (internal function)
# Args: tool_input (JSON string)
# Output: masked JSON (stdout)
# Targets: keys matching API_KEY, SECRET, TOKEN, PASSWORD, PRIVATE_KEY, ACCESS_KEY
# ---------------------------------------------------------------------------
_atl_mask_sensitive() {
    local tool_input="$1"

    # Replace values whose key name matches the sensitive pattern with "*****"
    # Pass _ATL_SENSITIVE_PATTERN as jq $pattern variable for consistency
    printf '%s' "${tool_input}" | jq \
        --arg pattern "${_ATL_SENSITIVE_PATTERN}" \
        'walk(
            if type == "object" then
                with_entries(
                    if (.key | test($pattern; "i"))
                    then .value = "*****"
                    else .
                    end
                )
            else .
            end
        )' 2>/dev/null
}

# ---------------------------------------------------------------------------
# _atl_audit_file
# Return today's audit file path
# ---------------------------------------------------------------------------
_atl_audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${AUDIT_DIR}/${today}.jsonl"
}

# ---------------------------------------------------------------------------
# _atl_ensure_dir
# Create audit directory if it does not exist
# ---------------------------------------------------------------------------
_atl_ensure_dir() {
    if [[ ! -d "${AUDIT_DIR}" ]]; then
        mkdir -p "${AUDIT_DIR}" || {
            log_error "audit: Failed to create AUDIT_DIR: ${AUDIT_DIR}"
            return 1
        }
    fi
}

# ---------------------------------------------------------------------------
# _atl_flock_append
# Append a line to a file under flock protection (CRIT-002)
# Args: file (string), line (string)
# ---------------------------------------------------------------------------
_atl_flock_append() {
    local file="$1"
    local line="$2"
    (
        flock -w 5 200 || {
            log_error "audit: flock timeout on ${file}"
            return 1
        }
        echo "${line}" >> "${file}"
    ) 200>"${file}.lock"
}

# ---------------------------------------------------------------------------
# atl_append_pre
# Append initial audit entry at PreToolUse time
# Args: session_id, tool_name, tool_input(JSON), domain, risk_category,
#        trust_score_before, autonomy_score, decision,
#        recommended_model, phase, complexity
# Side effect: appends 1 line to audit/YYYY-MM-DD.jsonl
# ---------------------------------------------------------------------------
atl_append_pre() {
    local session_id="$1"
    local tool_name="$2"
    local tool_input_raw="$3"
    local domain="$4"
    local risk_category="$5"
    local trust_score_before="$6"
    local autonomy_score="$7"
    local decision="$8"
    local recommended_model="${9:-unknown}"
    local phase="${10:-unknown}"
    local complexity="${11:-0.5}"

    local timestamp
    timestamp="$(now_iso8601)"

    # Ensure audit directory exists
    _atl_ensure_dir || return 1

    local log_file
    log_file="$(_atl_audit_file)"

    # Mask sensitive values in tool_input
    local tool_input_masked
    tool_input_masked="$(_atl_mask_sensitive "${tool_input_raw}")"

    # Fallback when tool_input_masked is empty (jq failure = invalid JSON)
    if [[ -z "${tool_input_masked}" ]]; then
        local fallback_line
        fallback_line="$(jq -cn \
            --arg timestamp "${timestamp}" \
            --arg session_id "${session_id}" \
            --arg tool_name "${tool_name}" \
            --arg error "invalid tool_input JSON" \
            '{timestamp: $timestamp, session_id: $session_id, tool_name: $tool_name, error: $error}'
        )"
        _atl_flock_append "${log_file}" "${fallback_line}" || {
            log_error "audit: Failed to write fallback entry to ${log_file}"
        }
        return 0
    fi

    # Build one compact JSON line using shared jq filter and append
    local entry
    entry="$(jq -cn -f "${LIB_DIR}/jq/audit-entry.jq" \
        --arg timestamp "${timestamp}" \
        --arg session_id "${session_id}" \
        --arg tool_name "${tool_name}" \
        --argjson tool_input "${tool_input_masked}" \
        --arg domain "${domain}" \
        --arg risk_category "${risk_category}" \
        --argjson trust_score_before "${trust_score_before}" \
        --argjson autonomy_score "${autonomy_score}" \
        --arg decision "${decision}" \
        --arg outcome "pending" \
        --argjson trust_score_after "null" \
        --arg recommended_model "${recommended_model}" \
        --arg phase "${phase}" \
        --argjson complexity "${complexity}" \
    )" 2>/dev/null

    if [[ -z "${entry}" ]]; then
        log_error "audit: Failed to build JSON entry for session=${session_id}"
        return 1
    fi

    _atl_flock_append "${log_file}" "${entry}" || {
        log_error "audit: Failed to write entry to ${log_file}"
        # Write failure does not block execution
    }

    return 0
}

# ---------------------------------------------------------------------------
# atl_update_outcome
# Append outcome entry at PostToolUse time (new line with outcome + trust_score_after)
# Args: session_id, tool_name, outcome(success|failure), trust_score_after (optional)
# Note: trust_score_after defaults to empty string which is recorded as JSON null.
#       PostToolUse(failure) passes "" to delegate score update to PostToolUseFailure.
# ---------------------------------------------------------------------------
atl_update_outcome() {
    local session_id="$1"
    local tool_name="$2"
    local outcome="$3"
    local trust_score_after="${4:-}"

    local timestamp
    timestamp="$(now_iso8601)"

    # Ensure audit directory exists
    _atl_ensure_dir || return 1

    local log_file
    log_file="$(_atl_audit_file)"

    # Normalize trust_score_after: empty string becomes JSON null
    local trust_score_json
    if [[ -z "${trust_score_after}" ]]; then
        trust_score_json="null"
    else
        trust_score_json="${trust_score_after}"
    fi

    # Build one compact outcome entry and append
    local entry
    entry="$(jq -cn \
        --arg timestamp "${timestamp}" \
        --arg session_id "${session_id}" \
        --arg tool_name "${tool_name}" \
        --arg outcome "${outcome}" \
        --argjson trust_score_after "${trust_score_json}" \
        '{
            timestamp:         $timestamp,
            session_id:        $session_id,
            tool_name:         $tool_name,
            outcome:           $outcome,
            trust_score_after: $trust_score_after
        }'
    )" 2>/dev/null

    if [[ -z "${entry}" ]]; then
        log_error "audit: Failed to build outcome JSON entry for session=${session_id}"
        return 1
    fi

    _atl_flock_append "${log_file}" "${entry}" || {
        log_error "audit: Failed to write outcome entry to ${log_file}"
    }

    return 0
}

# ---------------------------------------------------------------------------
# atl_flush
# Flush at session end (currently no-op; reserved for future buffered writes)
# Args: none
# ---------------------------------------------------------------------------
atl_flush() {
    # Synchronous writes, so no-op for now
    return 0
}
