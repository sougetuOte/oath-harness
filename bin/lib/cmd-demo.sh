#!/bin/bash
# oath-status: demo data generator (sourced by bin/oath, not executed directly)
# Generates sample trust-scores.json and audit JSONL in a temp directory,
# then runs all subcommands to showcase oath-harness output.

# Generate demo data and run all subcommands for demonstration.
cmd_demo() {
    local demo_dir
    demo_dir="$(mktemp -d)"
    # Use trap with variable expanded at definition time (safe: mktemp output has no special chars)
    trap "rm -rf ${demo_dir}" EXIT

    _demo_generate_trust_scores "${demo_dir}"
    _demo_generate_audit_entries "${demo_dir}"
    _demo_generate_phase "${demo_dir}"

    # Override environment to use demo data
    local orig_trust_scores="${TRUST_SCORES_FILE}"
    local orig_audit_dir="${AUDIT_DIR}"
    local orig_phase_file="${OATH_PHASE_FILE}"

    TRUST_SCORES_FILE="${demo_dir}/trust-scores.json"
    AUDIT_DIR="${demo_dir}/audit"
    OATH_PHASE_FILE="${demo_dir}/current-phase.md"

    printf -- "${FMT_BOLD}=== oath demo ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}(using generated sample data)${FMT_RESET}\n\n"

    printf -- "${FMT_BOLD}--- oath status ---${FMT_RESET}\n"
    cmd_status
    echo ""

    printf -- "${FMT_BOLD}--- oath status file_read ---${FMT_RESET}\n"
    cmd_status file_read
    echo ""

    printf -- "${FMT_BOLD}--- oath audit ---${FMT_RESET}\n"
    cmd_audit
    echo ""

    printf -- "${FMT_BOLD}--- oath config ---${FMT_RESET}\n"
    cmd_config
    echo ""

    printf -- "${FMT_BOLD}--- oath phase ---${FMT_RESET}\n"
    cmd_phase
    echo ""

    # Restore original environment before running scenarios
    TRUST_SCORES_FILE="${orig_trust_scores}"
    AUDIT_DIR="${orig_audit_dir}"
    OATH_PHASE_FILE="${orig_phase_file}"

    # Phase 2a scenarios
    printf -- "${FMT_BOLD}=== Phase 2a Scenarios ===${FMT_RESET}\n\n"
    demo_scenario_normal_growth
    echo ""
    demo_scenario_failure_recovery
    echo ""
    demo_scenario_complexity_compare
    echo ""
    demo_scenario_consecutive_fail
    echo ""

    printf -- "${FMT_BOLD}=== demo complete ===${FMT_RESET}\n"
}

# =========================================================================
# Phase 2a Scenario helper utilities
# =========================================================================

# Simulate one step of score update on success.
# Args: score (float), total_ops (int), is_warming_up (0|1), is_recovering (0|1), boost_threshold (int)
# Output: new_score (float)
_demo_sim_success() {
    local score="$1"
    local total_ops="$2"
    local is_warming_up="${3:-0}"
    local is_recovering="${4:-0}"
    local boost_threshold="${5:-20}"
    local recovery_boost_multiplier="${6:-1.5}"

    awk -v s="${score}" -v ops="${total_ops}" \
        -v wu="${is_warming_up}" -v rec="${is_recovering}" \
        -v bt="${boost_threshold}" -v rb="${recovery_boost_multiplier}" \
        'BEGIN {
            if (ops < bt) {
                base = (wu ? 0.10 : 0.05)
            } else {
                base = (wu ? 0.04 : 0.02)
            }
            rate = (rec ? base * rb : base)
            new_score = s + (1 - s) * rate
            if (new_score > 1) new_score = 1
            printf "%.5g\n", new_score
        }'
}

# Simulate one step of score update on failure.
# Args: score (float), failure_decay (float, default 0.85)
# Output: new_score (float)
_demo_sim_failure() {
    local score="$1"
    local failure_decay="${2:-0.85}"

    awk -v s="${score}" -v fd="${failure_decay}" \
        'BEGIN {
            new_score = s * fd
            if (new_score < 0) new_score = 0
            printf "%.5g\n", new_score
        }'
}

# Print a scenario step row.
# Args: step action score consec recovering target autonomy decision
_demo_print_row() {
    local step="$1"
    local action="$2"
    local score="$3"
    local consec="$4"
    local recovering="$5"
    local target="$6"
    local autonomy="$7"
    local decision="$8"

    printf "  %3s  %-9s %-7s %-6s %-10s %-7s %-9s %s\n" \
        "${step}" "${action}" "${score}" "${consec}" "${recovering}" "${target}" "${autonomy}" "${decision}"
}

# =========================================================================
# Scenario 1: Normal trust growth
# =========================================================================

# Simulate 10 consecutive successes for file_read domain (low complexity).
# Shows score progression and autonomy at each step.
demo_scenario_normal_growth() {
    printf -- "${FMT_BOLD}=== Scenario 1: Normal Trust Growth ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}10 consecutive successes, file_read domain, complexity=0.2 (low)${FMT_RESET}\n\n"

    local lambda1 lambda2
    lambda1="$(config_get "risk.lambda1")"
    lambda2="$(config_get "risk.lambda2")"
    local boost_threshold
    boost_threshold="$(config_get "trust.boost_threshold")"

    # Header
    printf "  %3s  %-9s %-7s %-9s %s\n" \
        "Step" "Action" "Score" "Autonomy" "Decision"
    printf "  %3s  %-9s %-7s %-9s %s\n" \
        "----" "------" "-----" "--------" "--------"

    local score="0.3"
    local risk_value=1
    local complexity="0.2"
    local total_ops=0
    local step

    for step in $(seq 1 10); do
        score="$(_demo_sim_success "${score}" "${total_ops}" 0 0 "${boost_threshold}")"
        total_ops=$((total_ops + 1))

        local autonomy
        autonomy="$(te_calc_autonomy "${score}" "${risk_value}" "${complexity}")"
        local decision
        decision="$(te_decide "${autonomy}" "low")"

        local score_disp autonomy_disp
        score_disp="$(printf "%.3f" "${score}")"
        autonomy_disp="$(printf "%.3f" "${autonomy}")"

        printf "  %3d  %-9s %-7s %-9s %s\n" \
            "${step}" "success" "${score_disp}" "${autonomy_disp}" "${decision}"
    done

    echo ""
    printf -- "${FMT_DIM}  Note: complexity=0.2 (low risk) keeps autonomy high even at low trust scores${FMT_RESET}\n"
}

# =========================================================================
# Scenario 2: Failure and Recovery Boost
# =========================================================================

# Simulate 5 successes -> 2 consecutive failures -> recovery boost -> completion.
# Shows pre_failure_score tracking, is_recovering state, and 1.5x boost effect.
demo_scenario_failure_recovery() {
    printf -- "${FMT_BOLD}=== Scenario 2: Failure & Recovery Boost ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}5 successes -> 2 failures -> recovery boost -> completion${FMT_RESET}\n\n"

    local boost_threshold
    boost_threshold="$(config_get "trust.boost_threshold")"
    local failure_decay
    failure_decay="$(config_get "trust.failure_decay")"
    local recovery_boost_multiplier
    recovery_boost_multiplier="$(config_get "trust.recovery_boost_multiplier")"
    local risk_value=2
    local complexity="0.5"

    # Header
    printf "  %3s  %-9s %-7s %-6s %-10s %-7s %-9s %s\n" \
        "Step" "Action" "Score" "Consec" "Recovering" "Target" "Autonomy" "Decision"
    printf "  %3s  %-9s %-7s %-6s %-10s %-7s %-9s %s\n" \
        "----" "------" "-----" "------" "----------" "------" "--------" "--------"

    local score="0.3"
    local total_ops=0
    local consec_failures=0
    local is_recovering=0
    local pre_failure_score="-"
    local step

    # Phase 1: 5 successes
    for step in $(seq 1 5); do
        score="$(_demo_sim_success "${score}" "${total_ops}" 0 "${is_recovering}" "${boost_threshold}" "${recovery_boost_multiplier}")"
        total_ops=$((total_ops + 1))
        consec_failures=0

        # Check recovery completion
        if [[ "${is_recovering}" -eq 1 ]]; then
            if awk -v s="${score}" -v t="${pre_failure_score}" 'BEGIN { exit !(s >= t) }'; then
                is_recovering=0
                pre_failure_score="-"
            fi
        fi

        local autonomy decision score_disp autonomy_disp target_disp rec_disp
        autonomy="$(te_calc_autonomy "${score}" "${risk_value}" "${complexity}")"
        decision="$(te_decide "${autonomy}" "medium")"
        score_disp="$(printf "%.3f" "${score}")"
        autonomy_disp="$(printf "%.3f" "${autonomy}")"
        target_disp="${pre_failure_score}"
        rec_disp="$([ "${is_recovering}" -eq 1 ] && echo "yes" || echo "no")"

        _demo_print_row "${step}" "success" "${score_disp}" "${consec_failures}" "${rec_disp}" "${target_disp}" "${autonomy_disp}" "${decision}"
    done

    # Phase 2: 2 failures
    for step in 6 7; do
        # On first failure: record pre_failure_score
        if [[ "${consec_failures}" -eq 0 && "${is_recovering}" -eq 0 ]]; then
            pre_failure_score="$(printf "%.3f" "${score}")"
            is_recovering=1
        fi

        score="$(_demo_sim_failure "${score}" "${failure_decay}")"
        total_ops=$((total_ops + 1))
        consec_failures=$((consec_failures + 1))

        local autonomy decision score_disp autonomy_disp
        autonomy="$(te_calc_autonomy "${score}" "${risk_value}" "${complexity}")"
        decision="$(te_decide "${autonomy}" "medium")"
        score_disp="$(printf "%.3f" "${score}")"
        autonomy_disp="$(printf "%.3f" "${autonomy}")"

        _demo_print_row "${step}" "FAILURE" "${score_disp}" "${consec_failures}" "yes" "${pre_failure_score}" "${autonomy_disp}" "${decision}"
    done

    # Phase 3: Recovery steps until score recovers to pre_failure_score
    local max_recovery_steps=10
    local recovery_step=0
    local pre_failure_num
    pre_failure_num="${pre_failure_score}"

    while [[ "${recovery_step}" -lt "${max_recovery_steps}" ]]; do
        recovery_step=$((recovery_step + 1))
        step=$((7 + recovery_step))
        score="$(_demo_sim_success "${score}" "${total_ops}" 0 1 "${boost_threshold}" "${recovery_boost_multiplier}")"
        total_ops=$((total_ops + 1))
        consec_failures=0

        # Check recovery completion
        local still_recovering="yes"
        if awk -v s="${score}" -v t="${pre_failure_num}" 'BEGIN { exit !(s >= t) }'; then
            is_recovering=0
            still_recovering="no"
            pre_failure_score="-"
        fi

        local autonomy decision score_disp autonomy_disp
        autonomy="$(te_calc_autonomy "${score}" "${risk_value}" "${complexity}")"
        decision="$(te_decide "${autonomy}" "medium")"
        score_disp="$(printf "%.3f" "${score}")"
        autonomy_disp="$(printf "%.3f" "${autonomy}")"

        local target_disp
        if [[ "${still_recovering}" == "yes" ]]; then
            target_disp="${pre_failure_num}"
        else
            target_disp="-"
        fi

        _demo_print_row "${step}" "success" "${score_disp}" "0" "${still_recovering}" "${target_disp}" "${autonomy_disp}" "${decision}"

        if [[ "${still_recovering}" == "no" ]]; then
            break
        fi
    done

    echo ""
    printf -- "${FMT_DIM}  Note: Recovery boost multiplier=%.1f accelerates score restoration after failures${FMT_RESET}\n" "${recovery_boost_multiplier}"
}

# =========================================================================
# Scenario 3: Complexity Dynamic Comparison
# =========================================================================

# Compare autonomy for the same trust score across low/medium/high risk levels.
# Shows Phase 1 (complexity=0.5 fixed) vs Phase 2a (complexity=dynamic) difference.
demo_scenario_complexity_compare() {
    printf -- "${FMT_BOLD}=== Scenario 3: Complexity Dynamic Impact ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}Same trust score, different risk levels: Phase 1 vs Phase 2a${FMT_RESET}\n\n"

    local lambda1 lambda2
    lambda1="$(config_get "risk.lambda1")"
    lambda2="$(config_get "risk.lambda2")"

    local trust="0.5"

    printf "  Trust score: %s (fixed for comparison)\n\n" "${trust}"

    # Phase 1 table (complexity fixed at 0.5)
    printf -- "${FMT_BOLD}  Phase 1 (complexity=0.5 fixed):${FMT_RESET}\n"
    printf "  %-10s %-6s %-12s %-9s %s\n" \
        "Risk" "Value" "Complexity" "Autonomy" "Decision"
    printf "  %-10s %-6s %-12s %-9s %s\n" \
        "----" "-----" "----------" "--------" "--------"

    local risk
    for risk in low medium high critical; do
        local risk_value complexity_v1
        case "${risk}" in
            low)      risk_value=1 ;;
            medium)   risk_value=2 ;;
            high)     risk_value=3 ;;
            critical) risk_value=4 ;;
        esac
        complexity_v1="0.5"

        local autonomy decision autonomy_disp
        if [[ "${risk}" == "critical" ]]; then
            autonomy="0.0"
            decision="blocked"
            autonomy_disp="n/a"
        else
            autonomy="$(te_calc_autonomy "${trust}" "${risk_value}" "${complexity_v1}")"
            decision="$(te_decide "${autonomy}" "${risk}")"
            autonomy_disp="$(printf "%.3f" "${autonomy}")"
        fi

        printf "  %-10s %-6s %-12s %-9s %s\n" \
            "${risk}" "${risk_value}" "${complexity_v1}" "${autonomy_disp}" "${decision}"
    done

    echo ""

    # Phase 2a table (complexity dynamic from risk category)
    printf -- "${FMT_BOLD}  Phase 2a (complexity=dynamic):${FMT_RESET}\n"
    printf "  %-10s %-6s %-12s %-9s %s\n" \
        "Risk" "Value" "Complexity" "Autonomy" "Decision"
    printf "  %-10s %-6s %-12s %-9s %s\n" \
        "----" "-----" "----------" "--------" "--------"

    for risk in low medium high critical; do
        local risk_value complexity_v2
        case "${risk}" in
            low)      risk_value=1 ;;
            medium)   risk_value=2 ;;
            high)     risk_value=3 ;;
            critical) risk_value=4 ;;
        esac
        complexity_v2="$(te_get_complexity "${risk}")"

        local autonomy decision autonomy_disp
        if [[ "${risk}" == "critical" ]]; then
            autonomy="0.0"
            decision="blocked"
            autonomy_disp="n/a"
        else
            autonomy="$(te_calc_autonomy "${trust}" "${risk_value}" "${complexity_v2}")"
            decision="$(te_decide "${autonomy}" "${risk}")"
            autonomy_disp="$(printf "%.3f" "${autonomy}")"
        fi

        printf "  %-10s %-6s %-12s %-9s %s\n" \
            "${risk}" "${risk_value}" "${complexity_v2}" "${autonomy_disp}" "${decision}"
    done

    echo ""
    printf -- "${FMT_DIM}  Note: Phase 2a uses risk-derived complexity (low=0.2, medium=0.5, high=0.7, critical=1.0)${FMT_RESET}\n"
    printf -- "${FMT_DIM}  Low-risk tools get higher autonomy; high-risk tools get lower autonomy vs Phase 1${FMT_RESET}\n"
}

# =========================================================================
# Scenario 4: Consecutive Failures Accumulation
# =========================================================================

# Simulate 5 consecutive failures, showing score decay and consecutive_failures count.
# Notes that Phase 2b Self-Escalation would trigger here.
demo_scenario_consecutive_fail() {
    printf -- "${FMT_BOLD}=== Scenario 4: Consecutive Failures ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}5 consecutive failures, git_local domain (high risk)${FMT_RESET}\n\n"

    local failure_decay
    failure_decay="$(config_get "trust.failure_decay")"
    local risk_value=3
    local complexity
    complexity="$(te_get_complexity "high")"

    # Header (same format as scenario 2 for consistency)
    printf "  %3s  %-9s %-7s %-6s %-10s %-7s %-9s %s\n" \
        "Step" "Action" "Score" "Consec" "Recovering" "Target" "Autonomy" "Decision"
    printf "  %3s  %-9s %-7s %-6s %-10s %-7s %-9s %s\n" \
        "----" "------" "-----" "------" "----------" "------" "--------" "--------"

    local score="0.5"
    local consec_failures=0
    local is_recovering=0
    local pre_failure_score="-"
    local step

    for step in $(seq 1 5); do
        # On first failure in fresh sequence: record pre_failure_score
        if [[ "${consec_failures}" -eq 0 && "${is_recovering}" -eq 0 ]]; then
            pre_failure_score="$(printf "%.3f" "${score}")"
            is_recovering=1
        fi

        score="$(_demo_sim_failure "${score}" "${failure_decay}")"
        consec_failures=$((consec_failures + 1))

        local autonomy decision score_disp autonomy_disp rec_disp
        autonomy="$(te_calc_autonomy "${score}" "${risk_value}" "${complexity}")"
        decision="$(te_decide "${autonomy}" "high")"
        score_disp="$(printf "%.3f" "${score}")"
        autonomy_disp="$(printf "%.3f" "${autonomy}")"
        rec_disp="yes"

        _demo_print_row "${step}" "FAILURE" "${score_disp}" "${consec_failures}" "${rec_disp}" "${pre_failure_score}" "${autonomy_disp}" "${decision}"
    done

    echo ""
    printf -- "${FMT_DIM}  Note: consecutive_failures=%d, score dropped from 0.500 to %.3f (%.0f%% decay)${FMT_RESET}\n" \
        "${consec_failures}" "${score}" "$(awk -v s="${score}" 'BEGIN { printf "%.0f", (1 - s / 0.5) * 100 }')"
    printf -- "${FMT_DIM}  Phase 2b: Self-Escalation would trigger here to alert the user about repeated failures${FMT_RESET}\n"
}

# =========================================================================
# Internal data generators
# =========================================================================

# Generate sample trust-scores.json with 5 domains at various trust levels.
# Includes Phase 2a fields: consecutive_failures, pre_failure_score, is_recovering.
# Args: demo_dir (path)
_demo_generate_trust_scores() {
    local dir="$1"
    local now
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    cat > "${dir}/trust-scores.json" <<EOF
{
  "version": "2",
  "updated_at": "${now}",
  "global_operation_count": 59,
  "domains": {
    "_global": {
      "score": 0.30,
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "${now}",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "file_read": {
      "score": 0.82,
      "successes": 34,
      "failures": 1,
      "total_operations": 35,
      "last_operated_at": "${now}",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "shell_exec": {
      "score": 0.51,
      "successes": 10,
      "failures": 1,
      "total_operations": 11,
      "last_operated_at": "${now}",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "file_write": {
      "score": 0.45,
      "successes": 7,
      "failures": 1,
      "total_operations": 8,
      "last_operated_at": "${now}",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "git_local": {
      "score": 0.38,
      "successes": 4,
      "failures": 1,
      "total_operations": 5,
      "last_operated_at": "${now}",
      "is_warming_up": true,
      "warmup_remaining": 2,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    }
  }
}
EOF
}

# Generate sample audit JSONL with 8 entries covering all decision types.
# Timestamps are generated relative to current time.
# Args: demo_dir (path)
_demo_generate_audit_entries() {
    local dir="$1"
    local audit_dir="${dir}/audit"
    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${audit_dir}/${today}.jsonl"
    mkdir -p "${audit_dir}"

    # Generate timestamps relative to now (offset in minutes)
    local ts_base
    ts_base="$(date -u '+%Y-%m-%dT')"
    local hour minute
    hour="$(date -u '+%H')"
    minute="$(date -u '+%M')"

    # Helper: generate timestamp offset by N minutes from current time
    _demo_ts() {
        local offset_min="$1"
        date -u -d "${offset_min} minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
            || date -u -v-"${offset_min}"M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
            || echo "${ts_base}${hour}:${minute}:00Z"
    }

    cat > "${audit_file}" <<EOF
{"timestamp":"$(_demo_ts 16)","tool_name":"Read","tool_input":{"file_path":"src/main.sh"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 14)","tool_name":"Read","tool_input":{"file_path":"lib/config.sh"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 12)","tool_name":"Bash","tool_input":{"command":"npm test"},"domain":"shell_exec","risk_category":"medium","decision":"logged_only","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 10)","tool_name":"Write","tool_input":{"file_path":"src/new-feature.sh"},"domain":"file_write","risk_category":"medium","decision":"logged_only","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 8)","tool_name":"Bash","tool_input":{"command":"git commit -m fix"},"domain":"git_local","risk_category":"high","decision":"human_required","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 6)","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/old"},"domain":"shell_exec","risk_category":"critical","decision":"blocked","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 4)","tool_name":"Read","tool_input":{"file_path":"tests/unit.bats"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"$(_demo_ts 2)","tool_name":"Bash","tool_input":{"command":"ls -la"},"domain":"shell_exec","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
EOF
}

# Generate sample phase file.
# Args: demo_dir (path)
_demo_generate_phase() {
    local dir="$1"
    echo "BUILDING" > "${dir}/current-phase.md"
}
