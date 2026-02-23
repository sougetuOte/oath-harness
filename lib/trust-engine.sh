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
                "warmup_remaining": 0
            }' "${TRUST_SCORES_FILE}")"
        echo "${tmp}" > "${TRUST_SCORES_FILE}"
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

    local tmp
    tmp="$(jq --arg d "${domain}" --arg action "success" \
        --argjson bt "${boost_threshold}" --argjson fd 0 --arg now "${now}" \
        -f "${LIB_DIR}/jq/trust-update.jq" "${TRUST_SCORES_FILE}")"
    echo "${tmp}" > "${TRUST_SCORES_FILE}"
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

    local tmp
    tmp="$(jq --arg d "${domain}" --arg action "failure" \
        --argjson bt 0 --argjson fd "${failure_decay}" --arg now "${now}" \
        -f "${LIB_DIR}/jq/trust-update.jq" "${TRUST_SCORES_FILE}")"
    echo "${tmp}" > "${TRUST_SCORES_FILE}"
}

# Apply time decay to all domains based on hibernation rules
# Called once at session start by bootstrap
te_apply_time_decay() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi

    local hibernation_days warmup_ops
    hibernation_days="$(config_get "trust.hibernation_days")"
    warmup_ops="$(config_get "trust.warmup_operations")"
    local now_epoch
    now_epoch="$(date -u '+%s')"

    # Get list of domains
    local domains
    domains="$(jq -r '.domains | keys[]' "${TRUST_SCORES_FILE}" 2>/dev/null)" || return 0

    local domain last_op last_epoch days_elapsed
    while IFS= read -r domain; do
        [[ -z "${domain}" ]] && continue
        last_op="$(jq -r --arg d "${domain}" '.domains[$d].last_operated_at' "${TRUST_SCORES_FILE}")"
        # Convert ISO 8601 to epoch using date command
        last_epoch="$(date -u -d "${last_op}" '+%s' 2>/dev/null)" || continue
        days_elapsed=$(( (now_epoch - last_epoch) / 86400 ))

        if [[ ${days_elapsed} -gt ${hibernation_days} ]]; then
            local decay_days=$(( days_elapsed - hibernation_days ))
            # Apply decay and set warmup using jq
            local tmp
            tmp="$(jq --arg d "${domain}" --argjson dd "${decay_days}" --argjson wo "${warmup_ops}" '
                (.domains[$d].score * pow(0.999; $dd) * 10000 | round / 10000) as $new_score |
                .domains[$d].score = $new_score |
                .domains[$d].is_warming_up = true |
                .domains[$d].warmup_remaining = $wo
            ' "${TRUST_SCORES_FILE}")"
            echo "${tmp}" > "${TRUST_SCORES_FILE}"
        fi
    done <<< "${domains}"
}

# Flush trust scores to disk (final write at session end)
te_flush() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi
    local now
    now="$(now_iso8601)"
    local tmp
    tmp="$(jq --arg now "${now}" '.updated_at = $now' "${TRUST_SCORES_FILE}")"
    echo "${tmp}" > "${TRUST_SCORES_FILE}"
}
