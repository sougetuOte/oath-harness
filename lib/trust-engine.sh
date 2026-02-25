#!/bin/bash
# oath-harness Trust Engine core
# Trust score calculation, update, and decision logic
set -euo pipefail

# Get the trust score for a domain. Falls back to _global if domain not found.
# Args: domain (string)
# Output: score (float, stdout)
te_get_score() {
    local domain="$1"
    local initial_score
    initial_score="$(config_get "trust.initial_score")"

    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        echo "${initial_score}"
        return 0
    fi

    local score
    score="$(jq -r --arg d "${domain}" \
        '.domains[$d].score // .domains._global.score // null' \
        "${TRUST_SCORES_FILE}" 2>/dev/null)"

    if [[ -z "${score}" || "${score}" == "null" ]]; then
        echo "${initial_score}"
    else
        echo "${score}"
    fi
}

# Calculate autonomy score
# Args: trust (float), risk_value (1-4), complexity (float, default 0.5)
# Output: autonomy (float, stdout)
# Formula: autonomy = 1 - (λ1 × risk_norm + λ2 × complexity) × (1 - trust)
te_calc_autonomy() {
    local trust="$1"
    local risk_value="$2"
    local complexity="${3:-0.5}"

    local lambda1 lambda2
    lambda1="$(config_get "risk.lambda1")"
    lambda2="$(config_get "risk.lambda2")"

    # L1-I2: %.6g (6 significant digits) is intentionally different from
    # trust-update.jq's round/100000 (5 decimal places). Autonomy uses
    # significant digits for scientific-notation-safe output; trust scores
    # use fixed decimals for human readability.
    awk -v t="${trust}" -v rv="${risk_value}" -v c="${complexity}" \
        -v l1="${lambda1}" -v l2="${lambda2}" \
        'BEGIN {
            risk_norm = rv / 4.0
            autonomy = 1 - (l1 * risk_norm + l2 * c) * (1 - t)
            if (autonomy < 0) autonomy = 0
            if (autonomy > 1) autonomy = 1
            printf "%.6g\n", autonomy
        }'
}

# 4-level decision based on autonomy and risk category
# Args: autonomy (float), risk_category (low|medium|high|critical)
# Output: decision (auto_approved|logged_only|human_required|blocked)
te_decide() {
    local autonomy="$1"
    local risk_category="$2"

    # critical is always blocked regardless of autonomy
    if [[ "${risk_category}" == "critical" ]]; then
        echo "blocked"
        return 0
    fi

    local auto_th human_th
    auto_th="$(config_get "autonomy.auto_approve_threshold")"
    human_th="$(config_get "autonomy.human_required_threshold")"

    awk -v a="${autonomy}" -v auto_th="${auto_th}" -v human_th="${human_th}" \
        'BEGIN {
            if (a > auto_th) {
                print "auto_approved"
            } else if (a >= human_th) {
                print "logged_only"
            } else {
                print "human_required"
            }
        }'
}

# Ensure a domain exists in trust-scores.json. Creates it if missing.
# Args: domain (string)
_te_ensure_domain() {
    local domain="$1"
    local initial_score
    initial_score="$(config_get "trust.initial_score")"
    local now
    now="$(now_iso8601)"

    local has_domain
    has_domain="$(jq -r --arg d "${domain}" 'has("domains") and (.domains | has($d))' \
        "${TRUST_SCORES_FILE}" 2>/dev/null)"

    if [[ "${has_domain}" != "true" ]]; then
        local tmp
        tmp="$(jq --arg d "${domain}" --argjson s "${initial_score}" --arg t "${now}" \
            '.domains[$d] = {
                "score": $s,
                "successes": 0,
                "failures": 0,
                "total_operations": 0,
                "last_operated_at": $t,
                "is_warming_up": false,
                "warmup_remaining": 0,
                "consecutive_failures": 0,
                "pre_failure_score": null,
                "is_recovering": false
            }' "${TRUST_SCORES_FILE}")"
        printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
    fi
}

# Get complexity value for a risk category
# Args: risk_category (string: low|medium|high|critical)
# Output: complexity (float, stdout)
te_get_complexity() {
    local risk_category="$1"
    case "${risk_category}" in
        low)      echo "0.2" ;;
        medium)   echo "0.5" ;;
        high)     echo "0.7" ;;
        critical) echo "1.0" ;;
        *)        echo "0.5" ;;
    esac
}

# Get recovery_boost_multiplier from config, falling back to default 1.5
# Output: multiplier value (float string, stdout)
_te_recovery_boost_multiplier() {
    local rb
    rb="$(config_get "trust.recovery_boost_multiplier" 2>/dev/null)"
    if [[ -z "${rb}" || "${rb}" == "null" ]]; then
        echo "1.5"
    else
        echo "${rb}"
    fi
}

# Record a successful operation for a domain
# Args: domain (string)
te_record_success() {
    local domain="$1"
    with_flock "${TRUST_SCORES_FILE}" 5 _te_record_success_impl "${domain}"
}

_te_record_success_impl() {
    local domain="$1"

    _te_ensure_domain "${domain}"

    local boost_threshold
    boost_threshold="$(config_get "trust.boost_threshold")"
    local now
    now="$(now_iso8601)"

    local recovery_boost_multiplier
    recovery_boost_multiplier="$(_te_recovery_boost_multiplier)"

    local tmp
    # L1-I1: --argjson fd 0 is unused in the success branch of trust-update.jq,
    # but jq requires all referenced variables to be defined at parse time.
    tmp="$(jq --arg d "${domain}" --arg action "success" \
        --argjson bt "${boost_threshold}" --argjson fd 0 --arg now "${now}" \
        --argjson rb "${recovery_boost_multiplier}" \
        -f "${LIB_DIR}/jq/trust-update.jq" "${TRUST_SCORES_FILE}")"
    printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
}

# Record a failed operation for a domain
# Args: domain (string)
te_record_failure() {
    local domain="$1"
    with_flock "${TRUST_SCORES_FILE}" 5 _te_record_failure_impl "${domain}"
}

_te_record_failure_impl() {
    local domain="$1"

    _te_ensure_domain "${domain}"

    local failure_decay
    failure_decay="$(config_get "trust.failure_decay")"
    local now
    now="$(now_iso8601)"

    local recovery_boost_multiplier
    recovery_boost_multiplier="$(_te_recovery_boost_multiplier)"

    local tmp
    tmp="$(jq --arg d "${domain}" --arg action "failure" \
        --argjson bt 0 --argjson fd "${failure_decay}" --arg now "${now}" \
        --argjson rb "${recovery_boost_multiplier}" \
        -f "${LIB_DIR}/jq/trust-update.jq" "${TRUST_SCORES_FILE}")"
    printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
}

# Apply time decay to all domains based on hibernation rules
# Called once at session start by bootstrap
te_apply_time_decay() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi
    with_flock "${TRUST_SCORES_FILE}" 5 _te_apply_time_decay_impl
}

_te_apply_time_decay_impl() {
    local hibernation_days warmup_ops
    hibernation_days="$(config_get "trust.hibernation_days")"
    warmup_ops="$(config_get "trust.warmup_operations")"
    local now_epoch
    now_epoch="$(date -u '+%s')"

    # Single-pass jq: iterate all domains, apply decay where needed
    local tmp
    tmp="$(jq --argjson hd "${hibernation_days}" --argjson wo "${warmup_ops}" \
        --argjson now_epoch "${now_epoch}" \
        -f "${LIB_DIR}/jq/time-decay.jq" "${TRUST_SCORES_FILE}")" || return 0
    printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
}

# Flush trust scores to disk (write updated_at timestamp).
# NOTE: Currently unused. The canonical updated_at writer is
# _stop_update_timestamp in hooks/stop.sh (runs under flock).
# Kept as public API for potential future callers.
te_flush() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi
    local now
    now="$(now_iso8601)"
    local tmp
    tmp="$(jq --arg now "${now}" '.updated_at = $now' "${TRUST_SCORES_FILE}")"
    printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
}
