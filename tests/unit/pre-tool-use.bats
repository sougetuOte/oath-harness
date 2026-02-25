#!/usr/bin/env bats
# Unit tests for hooks/pre-tool-use.sh
# AC-011, AC-014, AC-032

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${TEST_TMP}/config"
    export SETTINGS_FILE="${TEST_TMP}/config/settings.json"
    mkdir -p "${TEST_TMP}/config"
    cat > "${SETTINGS_FILE}" <<'TESTCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TESTCFG
    export STATE_DIR="${TEST_TMP}"
    export TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json"
    export AUDIT_DIR="${TEST_TMP}/audit"
    export OATH_PHASE_FILE="${TEST_TMP}/current-phase.md"

    # Default: BUILDING phase
    echo "BUILDING" > "${OATH_PHASE_FILE}"

    # Reset session state for each test (pre-tool-use runs as independent process)
    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# Helper: run pre-tool-use.sh with given JSON input
run_hook() {
    local json="$1"
    run bash "${PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< "${json}"
}

# Helper: create trust-scores.json with given global score
create_trust_scores_with_score() {
    local score="$1"
    mkdir -p "${TEST_TMP}"
    cat > "${TRUST_SCORES_FILE}" <<EOF
{
  "version": "2",
  "updated_at": "2026-01-01T00:00:00Z",
  "global_operation_count": 0,
  "domains": {
    "_global": {
      "score": ${score},
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-01-01T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": ${score},
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-01-01T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
EOF
}

# ============================================================
# AC-011: Allow List tool -> exit 0
# ============================================================

@test "Allow List tool (ls) in Bash -> exit 0" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    assert_success
}

@test "Allow List tool (cat) in Bash -> exit 0" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"cat /etc/hostname"}}'
    assert_success
}

@test "Read tool -> exit 0" {
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'
    assert_success
}

# ============================================================
# AC-032: critical tool -> exit 1 (blocked by trust engine: critical always blocked)
# ============================================================

@test "Critical tool (curl with https) -> exit 1" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
    assert_failure
    assert_equal "${status}" "1"
}

@test "Critical tool (curl with https) stderr contains BLOCKED" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
    assert_output --partial "[BLOCKED]"
}

@test "Critical tool (wget with https) -> exit 1" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"wget https://example.com/file.tar.gz"}}'
    assert_failure
    assert_equal "${status}" "1"
}

# ============================================================
# Phase-based access control (TPE)
# ============================================================

@test "PLANNING phase blocks file_write -> exit 1" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}'
    assert_failure
    assert_equal "${status}" "1"
}

@test "PLANNING phase blocks file_write stderr contains BLOCKED" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}'
    assert_output --partial "[BLOCKED]"
}

@test "BUILDING phase with low-risk Read tool -> exit 0" {
    echo "BUILDING" > "${OATH_PHASE_FILE}"
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'
    assert_success
}

@test "AUDITING phase blocks file_write -> exit 1" {
    echo "AUDITING" > "${OATH_PHASE_FILE}"
    run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}'
    assert_failure
    assert_equal "${status}" "1"
}

@test "AUDITING phase with file_read -> exit 0" {
    echo "AUDITING" > "${OATH_PHASE_FILE}"
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'
    assert_success
}

# ============================================================
# AC-014: Deny List tool with very low trust -> human_required (exit 2)
# risk_category=high, trust=0.05, complexity=0.7 (T5: dynamic from rcm_classify):
# autonomy = 1 - (0.6*0.75 + 0.4*0.7)*(1-0.05) = 1 - (0.45+0.28)*0.95 = 1 - 0.6935 = 0.3065 < 0.4
# -> human_required
# ============================================================

@test "High-risk tool (rm) with very low trust -> exit 2 (human_required)" {
    create_trust_scores_with_score "0.05"
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_equal "${status}" "2"
}

@test "High-risk tool (rm) with very low trust stderr contains CONFIRM" {
    create_trust_scores_with_score "0.05"
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_output --partial "[CONFIRM]"
}

@test "High-risk tool (rm) with normal trust -> exit 0 (logged_only)" {
    # trust=0.3, risk=high(3=0.75), complexity=0.7 (T5: dynamic)
    # autonomy = 1 - (0.6*0.75 + 0.4*0.7)*(1-0.3) = 1 - (0.45+0.28)*0.7 = 1 - 0.511 = 0.489
    # 0.4 <= 0.489 <= 0.8 -> logged_only
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_success
}

# ============================================================
# Audit trail
# ============================================================

@test "Audit log file is created after Allow List tool" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    local today
    today="$(date -u '+%Y-%m-%d')"
    [ -f "${AUDIT_DIR}/${today}.jsonl" ]
}

@test "Audit log contains required fields for allowed tool" {
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'
    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]
    run jq -r '.tool_name' "${audit_file}"
    assert_output "Read"
}

@test "Audit log decision=blocked for curl (critical tool)" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]
    run jq -r '.decision' "${audit_file}"
    assert_output "blocked"
}

@test "Audit log decision=auto_approved or logged_only for ls" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]
    local decision
    decision="$(jq -r '.decision' "${audit_file}")"
    [[ "${decision}" == "auto_approved" || "${decision}" == "logged_only" ]]
}

# ============================================================
# Error handling
# ============================================================

@test "Invalid JSON input -> exit 1 (fail-safe)" {
    run bash "${PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< "not valid json"
    assert_failure
    assert_equal "${status}" "1"
}

@test "Empty stdin -> exit 1 (fail-safe)" {
    run bash "${PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< ""
    assert_failure
    assert_equal "${status}" "1"
}

# ============================================================
# human_required: exit 2 with CONFIRM message
# ============================================================

@test "human_required decision yields exit 2" {
    # trust=0.05 for shell_exec domain, rm: risk=high(3=0.75), complexity=0.7 (T5: dynamic)
    # autonomy = 1 - (0.6*0.75 + 0.4*0.7)*(1-0.05) = 1 - 0.73*0.95 = 1 - 0.6935 = 0.3065 < 0.4
    # -> human_required
    create_trust_scores_with_score "0.05"
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_equal "${status}" "2"
}

@test "human_required decision stderr contains CONFIRM" {
    create_trust_scores_with_score "0.05"
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_output --partial "[CONFIRM]"
}

# ============================================================
# T5: complexity 動的化 (FR-CX-002)
# ============================================================

@test "T5: low-risk tool uses complexity=0.2 - audit log records correct autonomy" {
    # Read is low risk: risk_value=1, complexity=0.2
    # trust=0.3 (default initial), autonomy = 1 - (0.6*0.25 + 0.4*0.2)*(1-0.3)
    #   = 1 - (0.15 + 0.08)*0.7 = 1 - 0.23*0.7 = 1 - 0.161 = 0.839 > 0.8 -> auto_approved
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'
    assert_success

    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]

    local decision
    decision="$(jq -r '.decision' "${audit_file}")"
    [ "${decision}" = "auto_approved" ]
}

@test "T5: high-risk tool uses complexity=0.7 - audit log contains complexity field" {
    # rm is high risk: risk_value=3, complexity=0.7
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'

    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]

    local complexity
    complexity="$(jq -r '.complexity' "${audit_file}")"
    [ "${complexity}" = "0.7" ]
}

@test "T5: low-risk tool audit log contains complexity=0.2" {
    run_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.txt"}}'

    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]

    local complexity
    complexity="$(jq -r '.complexity' "${audit_file}")"
    [ "${complexity}" = "0.2" ]
}

@test "T5: critical tool audit log contains complexity=1.0" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'

    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"
    [ -f "${audit_file}" ]

    local complexity
    complexity="$(jq -r '.complexity' "${audit_file}")"
    [ "${complexity}" = "1.0" ]
}

@test "T5: high-risk tool with very low trust uses dynamic complexity - human_required" {
    # rm: risk=high(3, 0.7), complexity=0.7
    # trust=0.05: autonomy = 1 - (0.6*0.75 + 0.4*0.7)*(1-0.05)
    #           = 1 - (0.45+0.28)*0.95 = 1 - 0.73*0.95 = 1 - 0.6935 = 0.3065 < 0.4
    # -> human_required
    create_trust_scores_with_score "0.05"
    run_hook '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/test"}}'
    assert_equal "${status}" "2"
}

@test "T5: Task tool triggers model recommendation log (no updatedInput in output)" {
    # Task tool: medium risk (gray area), no updatedInput should appear
    run_hook '{"tool_name":"Task","tool_input":{"description":"run tests"}}'
    # Should succeed (exit 0) - Task is not blocked
    # stdout must not contain updatedInput key
    [[ "${output}" != *"updatedInput"* ]]
}
