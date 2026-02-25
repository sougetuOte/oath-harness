#!/usr/bin/env bats
# oath-status CLI unit tests
# Tests for: format.sh, cmd-status.sh, cmd-audit.sh, cmd-config.sh, cmd-phase.sh, bin/oath

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${PROJECT_ROOT}/tests/helpers.sh"
    setup_test_env

    # Source oath-harness lib modules
    source "${HARNESS_ROOT}/lib/common.sh"
    source "${HARNESS_ROOT}/lib/config.sh"
    source "${HARNESS_ROOT}/lib/trust-engine.sh"
    source "${HARNESS_ROOT}/lib/tool-profile.sh"
    config_load

    # Version constant (normally set by bin/oath entry point)
    OATH_VERSION="0.1.0"

    # Source oath-status modules
    source "${HARNESS_ROOT}/bin/lib/format.sh"
    source "${HARNESS_ROOT}/bin/lib/cmd-status.sh"
    source "${HARNESS_ROOT}/bin/lib/cmd-audit.sh"
    source "${HARNESS_ROOT}/bin/lib/cmd-config.sh"
    source "${HARNESS_ROOT}/bin/lib/cmd-phase.sh"
    source "${HARNESS_ROOT}/bin/lib/cmd-demo.sh"
}

teardown() {
    teardown_test_env
}

# --- Helper: create multi-domain trust-scores.json ---
_create_multi_domain_scores() {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-24T10:00:00Z",
  "global_operation_count": 47,
  "domains": {
    "_global": {
      "score": 0.30,
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-02-24T10:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "file_read": {
      "score": 0.82,
      "successes": 34,
      "failures": 1,
      "total_operations": 35,
      "last_operated_at": "2026-02-24T09:55:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": 0.51,
      "successes": 10,
      "failures": 1,
      "total_operations": 11,
      "last_operated_at": "2026-02-24T09:50:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "git_local": {
      "score": 0.38,
      "successes": 4,
      "failures": 1,
      "total_operations": 5,
      "last_operated_at": "2026-02-24T09:45:00Z",
      "is_warming_up": true,
      "warmup_remaining": 2
    }
  }
}
EOF
}

# --- Helper: create audit JSONL ---
_create_audit_entries() {
    local audit_file
    audit_file="${AUDIT_DIR}/$(date -u '+%Y-%m-%d').jsonl"
    mkdir -p "${AUDIT_DIR}"
    for i in $(seq 1 8); do
        cat >> "${audit_file}" <<EOF
{"timestamp":"2026-02-24T09:5${i}:00Z","tool_name":"Bash","tool_input":{"command":"ls -la"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"test-session"}
EOF
    done
}

# =========================================================================
# format.sh tests
# =========================================================================

@test "format: color variables are empty when TERM=dumb" {
    TERM=dumb
    # Re-source to pick up TERM change
    source "${HARNESS_ROOT}/bin/lib/format.sh"
    [[ -z "${FMT_GREEN}" ]]
    [[ -z "${FMT_YELLOW}" ]]
    [[ -z "${FMT_RED}" ]]
}

@test "format: fmt_score returns score with green for >= 0.7" {
    # Force no-color mode for testable output
    FMT_GREEN='' FMT_YELLOW='' FMT_RED='' FMT_RESET=''
    local result
    result="$(fmt_score "0.82")"
    [[ "${result}" == "0.82" ]]
}

@test "format: _fmt_relative_time converts seconds to human-readable" {
    # 90 seconds ago
    local past
    past="$(date -u -d '90 seconds ago' '+%Y-%m-%dT%H:%M:%SZ')"
    local result
    result="$(_fmt_relative_time "${past}")"
    [[ "${result}" == "1 min ago" ]]
}

# =========================================================================
# cmd-status.sh tests
# =========================================================================

# Test #1: status summary shows all domains
@test "status: summary shows all domains" {
    _create_multi_domain_scores
    run cmd_status
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"file_read"* ]]
    [[ "${output}" == *"shell_exec"* ]]
    [[ "${output}" == *"git_local"* ]]
}

# Test #2: status summary is sorted by score descending
@test "status: summary sorted by score descending" {
    _create_multi_domain_scores
    run cmd_status
    [[ "${status}" -eq 0 ]]
    # file_read (0.82) should appear before shell_exec (0.51)
    local pos_file_read pos_shell_exec
    pos_file_read=$(echo "${output}" | grep -n "file_read" | head -1 | cut -d: -f1)
    pos_shell_exec=$(echo "${output}" | grep -n "shell_exec" | head -1 | cut -d: -f1)
    [[ "${pos_file_read}" -lt "${pos_shell_exec}" ]]
}

# Test #3: status detail shows all fields
@test "status: domain detail shows all fields" {
    _create_multi_domain_scores
    run cmd_status "file_read"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"0.82"* ]]
    [[ "${output}" == *"34"* ]]
    [[ "${output}" == *"1"* ]]
    [[ "${output}" == *"35"* ]]
}

# Test #4: status detail shows 4-level autonomy estimates
@test "status: domain detail shows autonomy estimates for all risk levels" {
    _create_multi_domain_scores
    run cmd_status "file_read"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"low"* ]]
    [[ "${output}" == *"medium"* ]]
    [[ "${output}" == *"high"* ]]
    [[ "${output}" == *"critical"* ]]
    [[ "${output}" == *"blocked"* ]]
}

# Test #5: status with nonexistent domain shows error
@test "status: nonexistent domain shows error message" {
    _create_multi_domain_scores
    run cmd_status "nonexistent"
    [[ "${output}" == *"not found"* ]]
}

# Test #6: status with no trust-scores.json shows initial message
@test "status: no trust-scores.json shows initial message" {
    rm -f "${TRUST_SCORES_FILE}"
    run cmd_status
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"No trust data yet"* ]]
}

# =========================================================================
# cmd-audit.sh tests
# =========================================================================

# Test #7: audit summary shows entries
@test "audit: summary shows entries" {
    _create_audit_entries
    run cmd_audit
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Bash"* ]]
    [[ "${output}" == *"file_read"* ]]
}

# Test #8: audit --tail 5 shows at most 5 entries
@test "audit: --tail 5 limits output" {
    _create_audit_entries
    run cmd_audit --tail 5
    [[ "${status}" -eq 0 ]]
    # Count data lines (exclude header lines)
    local data_lines
    data_lines=$(echo "${output}" | grep -c "Bash" || true)
    [[ "${data_lines}" -le 5 ]]
}

# Test #9: audit with no file shows message
@test "audit: no audit file shows message" {
    run cmd_audit
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"No audit entries"* ]]
}

# Test #9b: audit --tail=N (equals form) works
@test "audit: --tail=3 limits output" {
    _create_audit_entries
    run cmd_audit --tail=3
    [[ "${status}" -eq 0 ]]
    local data_lines
    data_lines=$(echo "${output}" | grep -c "Bash" || true)
    [[ "${data_lines}" -le 3 ]]
}

# Test #9c: audit with unknown option returns error
@test "audit: unknown option returns error" {
    _create_audit_entries
    run cmd_audit --invalid
    [[ "${status}" -eq 1 ]]
    [[ "${output}" == *"Unknown option"* ]]
}

# Test #9d: audit --tail with non-numeric returns error
@test "audit: --tail with non-numeric returns error" {
    _create_audit_entries
    run cmd_audit --tail abc
    [[ "${status}" -eq 1 ]]
    [[ "${output}" == *"positive integer"* ]]
}

# Test: corrupted trust-scores.json shows error
@test "status: corrupted trust-scores.json shows error" {
    echo "NOT VALID JSON" > "${TRUST_SCORES_FILE}"
    run cmd_status
    [[ "${status}" -ne 0 ]]
    [[ "${output}" == *"Corrupted trust data"* ]]
}

# =========================================================================
# cmd-config.sh tests
# =========================================================================

# Test #10: config shows all settings
@test "config: shows all setting values" {
    run cmd_config
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"initial_score"* ]]
    [[ "${output}" == *"lambda1"* ]]
    [[ "${output}" == *"auto_approve"* ]]
    [[ "${output}" == *"failure_decay"* ]]
}

# =========================================================================
# cmd-phase.sh tests
# =========================================================================

# Test #11: phase shows current phase
@test "phase: shows current phase" {
    echo "BUILDING" > "${OATH_PHASE_FILE}"
    run cmd_phase
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"BUILDING"* ]]
}

# =========================================================================
# bin/oath entry point tests
# =========================================================================

# Test #12: help shows usage
@test "oath: help shows usage information" {
    run bash "${HARNESS_ROOT}/bin/oath" help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Usage"* ]] || [[ "${output}" == *"usage"* ]]
}

# Test #13: unknown command exits with error
@test "oath: unknown command exits 1" {
    run bash "${HARNESS_ROOT}/bin/oath" unknown_cmd
    [[ "${status}" -eq 1 ]]
}

# Test #14: no arguments runs status
@test "oath: no arguments defaults to status" {
    _create_multi_domain_scores
    # Run with env vars pointing to test tmp
    run env STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TRUST_SCORES_FILE}" \
        AUDIT_DIR="${AUDIT_DIR}" \
        OATH_PHASE_FILE="${OATH_PHASE_FILE}" \
        CONFIG_DIR="${CONFIG_DIR}" \
        SETTINGS_FILE="${SETTINGS_FILE}" \
        bash "${HARNESS_ROOT}/bin/oath"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"file_read"* ]]
}

# Test #15: version shows version string
@test "oath: version shows version string" {
    run bash "${HARNESS_ROOT}/bin/oath" version
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"oath-harness v"* ]]
}

# Test #16: --version flag works
@test "oath: --version flag works" {
    run bash "${HARNESS_ROOT}/bin/oath" --version
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"oath-harness v"* ]]
}

# Test #17: _global domain is excluded from summary
@test "status: _global domain excluded from summary" {
    _create_multi_domain_scores
    run cmd_status
    [[ "${status}" -eq 0 ]]
    # _global should NOT appear in domain rows (only in header area as version/phase)
    local domain_lines
    domain_lines="$(echo "${output}" | grep -c "_global" || true)"
    [[ "${domain_lines}" -eq 0 ]]
}

# Test #18: config shows (custom) marker for non-default values
@test "config: shows (custom) marker for non-default values" {
    # Write a settings.json with a non-default initial_score
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": {
    "initial_score": 0.1
  }
}
EOF
    config_load
    run cmd_config
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"0.1"* ]]
    [[ "${output}" == *"(custom)"* ]]
}

# Test #19: audit --tail 0 returns error
@test "audit: --tail 0 returns error" {
    _create_audit_entries
    run cmd_audit --tail 0
    [[ "${status}" -eq 1 ]]
    [[ "${output}" == *"positive integer"* ]]
}

# Test #20: audit header shows 'decisions' label
@test "audit: header shows decisions label" {
    _create_audit_entries
    run cmd_audit
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"decisions"* ]]
}

# =========================================================================
# cmd-demo.sh tests
# =========================================================================

@test "demo: exits successfully" {
    run cmd_demo
    [[ "${status}" -eq 0 ]]
}

@test "demo: output contains all domain names" {
    run cmd_demo
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"file_read"* ]]
    [[ "${output}" == *"shell_exec"* ]]
    [[ "${output}" == *"file_write"* ]]
    [[ "${output}" == *"git_local"* ]]
}

@test "demo: output contains audit entries" {
    run cmd_demo
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"auto_approved"* ]]
    [[ "${output}" == *"logged_only"* ]]
    [[ "${output}" == *"human_required"* ]]
    [[ "${output}" == *"blocked"* ]]
}

@test "demo: does not modify real state files" {
    local orig_trust="${TRUST_SCORES_FILE}"
    local orig_audit="${AUDIT_DIR}"
    run cmd_demo
    [[ "${status}" -eq 0 ]]
    # Real trust-scores.json should not exist (never created)
    [[ ! -f "${orig_trust}" ]]
    # Real audit dir should be empty or nonexistent
    [[ ! -d "${orig_audit}" ]] || [[ -z "$(ls -A "${orig_audit}" 2>/dev/null)" ]]
}

@test "oath: demo subcommand via entry point" {
    run env STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TRUST_SCORES_FILE}" \
        AUDIT_DIR="${AUDIT_DIR}" \
        OATH_PHASE_FILE="${OATH_PHASE_FILE}" \
        CONFIG_DIR="${CONFIG_DIR}" \
        SETTINGS_FILE="${SETTINGS_FILE}" \
        bash "${HARNESS_ROOT}/bin/oath" demo
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"demo complete"* ]]
}

# =========================================================================
# T11: cmd-demo.sh Phase 2a シナリオ テスト
# =========================================================================

@test "demo: Phase 2a scenarios header is shown" {
    run cmd_demo
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Phase 2a"* ]]
}

@test "demo: scenario 1 normal growth runs without error" {
    run demo_scenario_normal_growth
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Scenario 1"* ]]
}

@test "demo: scenario 1 shows step table with score and autonomy columns" {
    run demo_scenario_normal_growth
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Score"* ]]
    [[ "${output}" == *"Autonomy"* ]]
    [[ "${output}" == *"Decision"* ]]
}

@test "demo: scenario 2 failure recovery runs without error" {
    run demo_scenario_failure_recovery
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Scenario 2"* ]]
}

@test "demo: scenario 2 shows Recovering column" {
    run demo_scenario_failure_recovery
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Recovering"* ]]
}

@test "demo: scenario 3 complexity compare runs without error" {
    run demo_scenario_complexity_compare
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Scenario 3"* ]]
}

@test "demo: scenario 3 shows Phase 1 vs Phase 2a comparison" {
    run demo_scenario_complexity_compare
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Phase 1"* ]]
    [[ "${output}" == *"Phase 2a"* ]]
}

@test "demo: scenario 4 consecutive fail runs without error" {
    run demo_scenario_consecutive_fail
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Scenario 4"* ]]
}

@test "demo: scenario 4 shows Consec column" {
    run demo_scenario_consecutive_fail
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Consec"* ]]
}

@test "demo: scenario 4 mentions Phase 2b Self-Escalation" {
    run demo_scenario_consecutive_fail
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Phase 2b"* ]]
}

@test "demo: scenarios do not modify real trust-scores.json" {
    local orig_trust="${TRUST_SCORES_FILE}"
    run demo_scenario_normal_growth
    [[ "${status}" -eq 0 ]]
    [[ ! -f "${orig_trust}" ]]
}

@test "demo: Phase 2a scenario output included in full demo" {
    run cmd_demo
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Scenario 1"* ]]
    [[ "${output}" == *"Scenario 2"* ]]
    [[ "${output}" == *"Scenario 3"* ]]
    [[ "${output}" == *"Scenario 4"* ]]
}

# =========================================================================
# T9: cmd-status.sh Phase 2a new fields (consecutive_failures, is_recovering)
# =========================================================================

# Helper: create trust-scores.json with Phase 2a fields (recovering domain)
_create_phase2a_scores_recovering() {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-25T10:00:00Z",
  "global_operation_count": 20,
  "domains": {
    "_global": {
      "score": 0.30,
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-02-25T10:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "shell_exec": {
      "score": 0.45,
      "successes": 8,
      "failures": 3,
      "total_operations": 11,
      "last_operated_at": "2026-02-25T09:50:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 2,
      "pre_failure_score": 0.52,
      "is_recovering": true
    }
  }
}
EOF
}

# Helper: create trust-scores.json with Phase 2a fields (not recovering domain)
_create_phase2a_scores_not_recovering() {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-25T10:00:00Z",
  "global_operation_count": 10,
  "domains": {
    "_global": {
      "score": 0.30,
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-02-25T10:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    },
    "file_read": {
      "score": 0.72,
      "successes": 20,
      "failures": 0,
      "total_operations": 20,
      "last_operated_at": "2026-02-25T09:55:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    }
  }
}
EOF
}

# Test T9-1: consecutive_failures > 0 の場合に "Consecutive:" が表示される
@test "status: domain detail shows Consecutive field when consecutive_failures > 0" {
    _create_phase2a_scores_recovering
    run cmd_status "shell_exec"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Consecutive:"* ]]
    [[ "${output}" == *"2"* ]]
}

# Test T9-2: is_recovering == true の場合に "Recovering: yes → {target}" が表示される
@test "status: domain detail shows Recovering yes with target when is_recovering=true" {
    _create_phase2a_scores_recovering
    run cmd_status "shell_exec"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Recovering:"* ]]
    [[ "${output}" == *"yes"* ]]
    [[ "${output}" == *"0.52"* ]]
}

# Test T9-3: is_recovering == false の場合に "Recovering: no" が表示される
@test "status: domain detail shows Recovering no when is_recovering=false" {
    _create_phase2a_scores_not_recovering
    run cmd_status "file_read"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"Recovering:"* ]]
    [[ "${output}" == *"no"* ]]
}

# Test T9-4: Phase 1 形式（新フィールドなし）でもエラーにならない
@test "status: domain detail works without Phase 2a fields (Phase 1 data)" {
    _create_multi_domain_scores
    run cmd_status "shell_exec"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" == *"shell_exec"* ]]
    [[ "${output}" == *"0.51"* ]]
}
