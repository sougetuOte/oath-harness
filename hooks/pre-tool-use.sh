#!/bin/bash
# oath-harness PreToolUse hook
# Intercepts tool calls before execution for trust-based access control
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Fail-safe: block on any error (FR-HK-004)
trap 'echo "oath-harness: internal error - blocking for safety" >&2; exit 1' ERR

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
# shellcheck source=../lib/tool-profile.sh
source "${HARNESS_ROOT}/lib/tool-profile.sh"
# shellcheck source=../lib/audit.sh
source "${HARNESS_ROOT}/lib/audit.sh"
# shellcheck source=../lib/model-router.sh
source "${HARNESS_ROOT}/lib/model-router.sh"

# --- Main flow ---

# Step 1: Read stdin (pipe - can only read once)
raw_input="$(cat)"

# Step 2: Validate and extract tool_name and tool_input
if [[ -z "${raw_input}" ]]; then
    log_error "pre-tool-use: empty stdin"
    exit 1
fi

tool_name="$(printf '%s' "${raw_input}" | jq -r '.tool_name // empty' 2>/dev/null)"
if [[ -z "${tool_name}" ]]; then
    log_error "pre-tool-use: invalid JSON or missing tool_name"
    exit 1
fi

tool_input_json="$(printf '%s' "${raw_input}" | jq -c '.tool_input // {}' 2>/dev/null)"
if [[ -z "${tool_input_json}" ]]; then
    log_error "pre-tool-use: failed to extract tool_input"
    exit 1
fi

# Step 3-4: Initialize session and load config
config_load
sb_ensure_initialized

# Step 5: Get session ID
session_id="$(sb_get_session_id)"

# Step 6: Get domain
domain="$(rcm_get_domain "${tool_name}" "${tool_input_json}")"

# Step 7: Classify risk
risk_result="$(rcm_classify "${tool_name}" "${tool_input_json}")"

# Step 8-9: Parse risk_category and risk_value
risk_category="$(echo "${risk_result}" | awk '{print $1}')"
risk_value="$(echo "${risk_result}" | awk '{print $2}')"

# Step 10: Get current phase
phase="$(tpe_get_current_phase)"

# Step 11: Check tool profile (phase-based access control)
profile_result="$(tpe_check "${tool_name}" "${domain}" "${phase}")"

# Step 12: Handle profile blocked
if [[ "${profile_result}" == "blocked" ]]; then
    # Record in audit trail before blocking
    # || true: audit failure must not prevent the blocking decision
    atl_append_pre \
        "${session_id}" \
        "${tool_name}" \
        "${tool_input_json}" \
        "${domain}" \
        "${risk_category}" \
        "0" \
        "0" \
        "blocked" || true
    echo "oath-harness: [BLOCKED] tool=${tool_name} domain=${domain} phase=${phase} reason=phase_policy - ${phase} phase does not allow ${domain} operations" >&2
    exit 1
fi

# Step 13: Get trust score
trust="$(te_get_score "${domain}")"

# Step 14: Calculate autonomy
autonomy="$(te_calc_autonomy "${trust}" "${risk_value}")"

# Step 15: Make decision
decision="$(te_decide "${autonomy}" "${risk_category}")"

# Step 16: Recommend model (recorded in audit trail)
recommended_model="$(mr_recommend "${autonomy}" "${risk_category}" "${trust}" "${decision}")"

# Step 17: Append audit log
# || true: audit failure is non-fatal; the access decision takes priority
atl_append_pre \
    "${session_id}" \
    "${tool_name}" \
    "${tool_input_json}" \
    "${domain}" \
    "${risk_category}" \
    "${trust}" \
    "${autonomy}" \
    "${decision}" || true

log_debug "pre-tool-use: tool=${tool_name} domain=${domain} risk=${risk_category} trust=${trust} autonomy=${autonomy} decision=${decision} model=${recommended_model}"

# Step 18: Act on decision
case "${decision}" in
    auto_approved|logged_only)
        exit 0
        ;;
    human_required)
        echo "oath-harness: [CONFIRM] tool=${tool_name} domain=${domain} risk=${risk_category} autonomy=${autonomy} trust=${trust} - human approval required" >&2
        exit 2
        ;;
    blocked)
        echo "oath-harness: [BLOCKED] tool=${tool_name} domain=${domain} risk=${risk_category} reason=critical_risk - critical risk tools are always blocked for safety" >&2
        exit 1
        ;;
    *)
        log_error "pre-tool-use: unknown decision=${decision}"
        exit 1
        ;;
esac
