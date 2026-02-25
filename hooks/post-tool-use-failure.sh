#!/bin/bash
# oath-harness PostToolUseFailure hook
# Handles tool execution failures: score decay + consecutive failure tracking
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PostToolUseFailure errors should not block (side-effect only)
trap 'exit 0' ERR

# shellcheck source=../lib/common.sh
source "${HARNESS_ROOT}/lib/common.sh"
# shellcheck source=../lib/config.sh
source "${HARNESS_ROOT}/lib/config.sh"
# shellcheck source=../lib/trust-engine.sh
source "${HARNESS_ROOT}/lib/trust-engine.sh"
# shellcheck source=../lib/bootstrap.sh
source "${HARNESS_ROOT}/lib/bootstrap.sh"
# shellcheck source=../lib/risk-mapper.sh
# risk-mapper.sh is sourced for rcm_get_domain (tool_name -> domain mapping)
source "${HARNESS_ROOT}/lib/risk-mapper.sh"
# shellcheck source=../lib/audit.sh
source "${HARNESS_ROOT}/lib/audit.sh"

# --- Main flow ---

# Step 1: Read stdin (pipe - can only read once)
raw_input="$(cat)"

# Step 2: Extract fields (silent failure for invalid JSON -> exit 0 via trap)
if [[ -z "${raw_input}" ]]; then
    log_debug "post-tool-use-failure: empty stdin, skipping"
    exit 0
fi

tool_name="$(printf '%s' "${raw_input}" | jq -r '.tool_name // empty' 2>/dev/null)"
if [[ -z "${tool_name}" ]]; then
    log_debug "post-tool-use-failure: invalid JSON or missing tool_name, skipping"
    exit 0
fi

tool_input_json="$(printf '%s' "${raw_input}" | jq -c '.tool_input // {}' 2>/dev/null)"
# Fallback to empty object if jq extraction failed
if [[ -z "${tool_input_json}" ]]; then
    tool_input_json="{}"
fi

# Step 3: Validate is_error field
# Default to true (fail-safe: if field is missing, assume failure since we're in the failure hook).
# If is_error is explicitly false, skip processing — this shouldn't happen, but guard against it.
is_error="$(printf '%s' "${raw_input}" | jq -r 'if has("is_error") then .is_error else true end' 2>/dev/null)"
if [[ "${is_error}" != "true" ]]; then
    log_debug "post-tool-use-failure: is_error is not true (${is_error}), skipping"
    exit 0
fi

# Step 4: Load config
config_load

# Step 5: Initialize session (idempotent)
sb_ensure_initialized

# Step 6: Get session ID
session_id="$(sb_get_session_id)"

# Step 7: Get domain for the tool call
domain="$(rcm_get_domain "${tool_name}" "${tool_input_json}")"

# Step 8: Record failure (includes consecutive_failures increment and is_recovering start)
te_record_failure "${domain}" || true

# Step 9: Get updated trust score
trust_after="$(te_get_score "${domain}")"

# Step 10: Append outcome to audit trail
atl_update_outcome "${session_id}" "${tool_name}" "failure" "${trust_after}" || true

log_debug "post-tool-use-failure: tool=${tool_name} domain=${domain} trust_after=${trust_after}"

exit 0
