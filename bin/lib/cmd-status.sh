#!/bin/bash
# oath-status: trust score display (sourced by bin/oath, not executed directly)
# Displays trust score summary or domain detail from trust-scores.json.

# Display trust score information.
# Args: [domain] — if given, show detail for that domain; otherwise show summary
cmd_status() {
    local domain="${1:-}"

    if [[ -n "${domain}" ]]; then
        _cmd_status_detail "${domain}"
    else
        _cmd_status_summary
    fi
}

# Display a summary table of all domains sorted by score descending.
_cmd_status_summary() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        echo "No trust data yet. Start a Claude Code session to begin building trust."
        return 0
    fi

    local version global_op_count phase
    version="$(jq -r '.version // "?"' "${TRUST_SCORES_FILE}" 2>/dev/null)" || {
        echo "Corrupted trust data: failed to read ${TRUST_SCORES_FILE}" >&2
        return 1
    }
    global_op_count="$(jq -r '.global_operation_count // 0' "${TRUST_SCORES_FILE}")"
    phase="$(tpe_get_current_phase | tr '[:lower:]' '[:upper:]')"

    printf "${FMT_BOLD}oath-harness v%s  |  Phase: %s  |  Session: %s ops${FMT_RESET}\n" \
        "${OATH_VERSION}" \
        "${phase}" "${global_op_count}"
    echo ""

    fmt_table_row "Domain" "Score" "Ops" "Status"
    printf '%s\n' "----------------+--------+------+------------------"

    # Extract domains sorted by score descending, excluding _global
    local tsv_data
    tsv_data="$(jq -r \
        '.domains | to_entries | map(select(.key != "_global")) | sort_by(-.value.score) | .[] | [.key, .value.score, .value.total_operations] | @tsv' \
        "${TRUST_SCORES_FILE}")"

    local domain_name score total_ops autonomy decision colored_score
    while IFS=$'\t' read -r domain_name score total_ops; do
        [[ -z "${domain_name}" ]] && continue
        autonomy="$(te_calc_autonomy "${score}" 2)"
        decision="$(te_decide "${autonomy}" "medium")"
        colored_score="$(fmt_score "${score}")"
        fmt_table_row "${domain_name}" "${colored_score}" "${total_ops}" "${decision}"
    done <<< "${tsv_data}"
}

# Display detailed information for a single domain.
# Args: domain (string)
_cmd_status_detail() {
    local domain="$1"

    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        echo "No trust data yet. Start a Claude Code session to begin building trust."
        return 0
    fi

    # Check if domain exists
    local exists
    exists="$(jq -r --arg d "${domain}" 'has("domains") and (.domains | has($d))' "${TRUST_SCORES_FILE}" 2>/dev/null)"
    if [[ "${exists}" != "true" ]]; then
        echo "Domain '${domain}' not found."
        return 0
    fi

    # Extract all fields in a single jq call
    local score successes failures total_ops last_operated is_warming_up warmup_remaining
    local consecutive_failures is_recovering pre_failure_score
    local domain_data
    domain_data="$(jq -r --arg d "${domain}" \
        '.domains[$d] | [.score, .successes, .failures, .total_operations, .last_operated_at, .is_warming_up, .warmup_remaining, (.consecutive_failures // 0), (.is_recovering // false), (.pre_failure_score // "null")] | @tsv' \
        "${TRUST_SCORES_FILE}" 2>/dev/null)" || {
        echo "Corrupted trust data: failed to read ${TRUST_SCORES_FILE}" >&2
        return 1
    }
    IFS=$'\t' read -r score successes failures total_ops last_operated is_warming_up warmup_remaining consecutive_failures is_recovering pre_failure_score <<< "${domain_data}"

    local warmup_label
    if [[ "${is_warming_up}" == "true" ]]; then
        warmup_label="Yes"
    else
        warmup_label="No"
    fi

    local relative_time
    relative_time="$(_fmt_relative_time "${last_operated}")"

    local colored_score
    colored_score="$(fmt_score "${score}")"

    local recovering_label
    if [[ "${is_recovering}" == "true" ]]; then
        recovering_label="yes -> ${pre_failure_score}"
    else
        recovering_label="no"
    fi

    printf "${FMT_BOLD}Domain:${FMT_RESET}            %s\n" "${domain}"
    printf "Score:             %s\n" "${colored_score}"
    printf "Successes:         %s\n" "${successes}"
    printf "Failures:          %s\n" "${failures}"
    printf "Consecutive:       %s\n" "${consecutive_failures}"
    printf "Recovering:        %s\n" "${recovering_label}"
    printf "Total operations:  %s\n" "${total_ops}"
    printf "Last operated:     %s (%s)\n" "${last_operated}" "${relative_time}"
    printf "Warming up:        %s\n" "${warmup_label}"
    printf "Warmup remaining:  %s\n" "${warmup_remaining}"
    echo ""

    printf "${FMT_BOLD}Autonomy estimates:${FMT_RESET}\n"

    local risk_levels=("low:1" "medium:2" "high:3" "critical:4")
    local risk_name risk_value autonomy decision
    for risk_entry in "${risk_levels[@]}"; do
        risk_name="${risk_entry%%:*}"
        risk_value="${risk_entry##*:}"

        if [[ "${risk_name}" == "critical" ]]; then
            printf "  %-10s blocked (always)\n" "${risk_name}"
        else
            autonomy="$(te_calc_autonomy "${score}" "${risk_value}")"
            decision="$(te_decide "${autonomy}" "${risk_name}")"
            printf "  %-10s autonomy=%.4f  ->  %s\n" "${risk_name}" "${autonomy}" "${decision}"
        fi
    done
}
