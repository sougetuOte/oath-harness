#!/bin/bash
# oath-harness PostToolUse hook
# Records tool execution results and updates trust scores
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PostToolUse errors should not block (side-effect only)
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
# shellcheck source=../lib/risk-mapper.sh
source "${HARNESS_ROOT}/lib/risk-mapper.sh"
# shellcheck source=../lib/audit.sh
source "${HARNESS_ROOT}/lib/audit.sh"

# --- Feature detection ---
# Check if PostToolUseFailure hook is registered in Claude Code settings.
# When registered, failure score decay is delegated to that hook.
# When not registered (older Claude Code or manual setup), PostToolUse handles it as fallback.
_is_failure_hook_registered() {
    local claude_settings="${OATH_CLAUDE_SETTINGS:-${HARNESS_ROOT}/.claude/settings.json}"
    if [[ -f "${claude_settings}" ]]; then
        jq -e '.hooks.PostToolUseFailure | length > 0' "${claude_settings}" >/dev/null 2>&1
        return $?
    else
        return 1
    fi
}

# --- Main flow ---

# Step 1: Read stdin (pipe - can only read once)
raw_input="$(cat)"

# Step 2: Extract fields (silent failure for invalid JSON -> exit 0 via trap)
if [[ -z "${raw_input}" ]]; then
    log_debug "post-tool-use: empty stdin, skipping"
    exit 0
fi

tool_name="$(printf '%s' "${raw_input}" | jq -r '.tool_name // empty' 2>/dev/null)"
if [[ -z "${tool_name}" ]]; then
    log_debug "post-tool-use: invalid JSON or missing tool_name, skipping"
    exit 0
fi

tool_input_json="$(printf '%s' "${raw_input}" | jq -c '.tool_input // {}' 2>/dev/null)"
# Fallback to empty object if jq extraction failed
if [[ -z "${tool_input_json}" ]]; then
    tool_input_json="{}"
fi

# Step 3: Determine outcome from is_error field
# is_error absent -> default to false -> outcome = "success"
is_error="$(printf '%s' "${raw_input}" | jq -r '.is_error // false' 2>/dev/null)"
outcome="success"
[[ "${is_error}" == "true" ]] && outcome="failure"

# Step 4: Load config
config_load

# Step 5: Initialize session (idempotent)
sb_ensure_initialized

# Step 6: Get session ID
session_id="$(sb_get_session_id)"

# Step 7: Get domain for the tool call
domain="$(rcm_get_domain "${tool_name}" "${tool_input_json}")"

# Step 8: Update trust score and append audit outcome
if [[ "${outcome}" == "success" ]]; then
    # If te_record_success fails, record null instead of a stale pre-update score
    if te_record_success "${domain}"; then
        trust_after="$(te_get_score "${domain}")"
    else
        trust_after=""
    fi
    atl_update_outcome "${session_id}" "${tool_name}" "success" "${trust_after}" || true
    log_debug "post-tool-use: tool=${tool_name} domain=${domain} outcome=success trust_after=${trust_after:-null}"
else
    # Phase 2a: PostToolUseFailure is responsible for score decay when available.
    # Fallback: if PostToolUseFailure hook is not registered, handle decay here.
    # Note: tool_input_json is intentionally not passed to atl_update_outcome
    # (asymmetric: detailed input analysis is in PreToolUse, not PostToolUse).
    if _is_failure_hook_registered; then
        atl_update_outcome "${session_id}" "${tool_name}" "failure" "" || true
        log_debug "post-tool-use: tool=${tool_name} domain=${domain} outcome=failure (score update delegated to PostToolUseFailure)"
    else
        te_record_failure "${domain}" || true
        trust_after="$(te_get_score "${domain}")"
        atl_update_outcome "${session_id}" "${tool_name}" "failure" "${trust_after}" || true
        log_debug "post-tool-use: tool=${tool_name} domain=${domain} outcome=failure trust_after=${trust_after} (fallback: PostToolUseFailure not registered)"
    fi
fi

exit 0
