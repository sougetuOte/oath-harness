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

if [[ "${is_error}" == "true" ]]; then
    outcome="failure"
else
    outcome="success"
fi

# Step 4: Load config
config_load

# Step 5: Initialize session (idempotent)
sb_ensure_initialized

# Step 6: Get session ID
session_id="$(sb_get_session_id)"

# Step 7: Get domain for the tool call
domain="$(rcm_get_domain "${tool_name}" "${tool_input_json}")"

# Step 8: Update trust score based on outcome
if [[ "${outcome}" == "success" ]]; then
    te_record_success "${domain}" || true
else
    te_record_failure "${domain}" || true
fi

# Step 9: Get updated trust score
trust_after="$(te_get_score "${domain}")"

# Step 10: Append outcome to audit trail
atl_update_outcome "${session_id}" "${tool_name}" "${outcome}" "${trust_after}" || true

log_debug "post-tool-use: tool=${tool_name} domain=${domain} outcome=${outcome} trust_after=${trust_after}"

exit 0
