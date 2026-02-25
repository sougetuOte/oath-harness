#!/usr/bin/env bats
# Unit tests for hooks/post-tool-use-failure.sh
# AC-PTF: PostToolUseFailure フック動作検証

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
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85,"recovery_boost_multiplier":1.5},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
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

# Helper: run post-tool-use-failure.sh with given JSON piped via stdin (no state persistence)
run_failure_hook() {
    local json="$1"
    run bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh" <<< "${json}"
}

# Helper: run post-tool-use-failure.sh passing env vars explicitly (subprocess isolation)
run_failure_hook_env() {
    local json="$1"
    echo "${json}" | \
        HARNESS_ROOT="${PROJECT_ROOT}" \
        STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json" \
        AUDIT_DIR="${TEST_TMP}/audit" \
        CONFIG_DIR="${TEST_TMP}/config" \
        SETTINGS_FILE="${TEST_TMP}/config/settings.json" \
        OATH_PHASE_FILE="${TEST_TMP}/current-phase.md" \
        bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh"
}

# Helper: get trust score for a domain from trust-scores.json
get_domain_score() {
    local domain="$1"
    jq -r --arg d "${domain}" '.domains[$d].score // .domains._global.score // 0.3' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# Helper: get domain field value from trust-scores.json
get_domain_field() {
    local domain="$1"
    local field="$2"
    jq -r --arg d "${domain}" --arg f "${field}" '.domains[$d][$f]' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# Helper: get today's audit file path
audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${TEST_TMP}/audit/${today}.jsonl"
}

# ============================================================
# AC-PTF-1: 空の stdin -> exit 0 (エラーでもブロックしない)
# ============================================================

@test "empty stdin -> exit 0" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh" <<< ""
    assert_success
}

# ============================================================
# AC-PTF-2: tool_name が空 -> exit 0 (エラーでもブロックしない)
# ============================================================

@test "missing tool_name -> exit 0" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh" <<< '{"tool_input":{"command":"ls"}}'
    assert_success
}

@test "invalid JSON -> exit 0" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh" <<< "not valid json"
    assert_success
}

# ============================================================
# AC-PTF-3: 失敗時に te_record_failure が呼ばれ、スコアが減衰する
# ============================================================

@test "failure -> exit 0" {
    run_failure_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_success
}

@test "failure -> trust score decreases" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    # failure_decay=0.85, new_score = 0.3 * 0.85 = 0.255
    local score
    score="$(get_domain_score "file_read")"
    # score should be less than 0.3
    awk -v s="${score}" 'BEGIN { exit !(s < 0.3) }'
}

@test "failure -> score approximately 0.255" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local score
    score="$(get_domain_score "file_read")"
    # 0.3 * 0.85 = 0.255 (allow small float tolerance)
    awk -v s="${score}" 'BEGIN {
        diff = s - 0.255
        if (diff < 0) diff = -diff
        exit !(diff < 0.001)
    }'
}

# ============================================================
# AC-PTF-4: 失敗時に consecutive_failures がインクリメントされる
# ============================================================

@test "failure -> consecutive_failures becomes 1" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local cf
    cf="$(get_domain_field "file_read" "consecutive_failures")"
    [ "${cf}" = "1" ]
}

# ============================================================
# AC-PTF-5: 連続2回失敗で consecutive_failures が 2 になる
# ============================================================

@test "two consecutive failures -> consecutive_failures becomes 2" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local cf
    cf="$(get_domain_field "file_read" "consecutive_failures")"
    [ "${cf}" = "2" ]
}

# ============================================================
# AC-PTF-6: 失敗後に is_recovering が true になる
# ============================================================

@test "failure -> is_recovering becomes true" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local recovering
    recovering="$(get_domain_field "file_read" "is_recovering")"
    [ "${recovering}" = "true" ]
}

# ============================================================
# AC-PTF-7: 失敗後に pre_failure_score が記録される
# ============================================================

@test "failure -> pre_failure_score is recorded" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local pfs
    pfs="$(get_domain_field "file_read" "pre_failure_score")"
    # pre_failure_score should be the initial score (0.3)
    [ "${pfs}" != "null" ]
    awk -v s="${pfs}" 'BEGIN {
        diff = s - 0.3
        if (diff < 0) diff = -diff
        exit !(diff < 0.001)
    }'
}

# ============================================================
# AC-PTF-8: audit trail が更新される
# ============================================================

@test "failure -> audit log entry is written" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
}

@test "failure -> audit log contains outcome=failure" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local outcome
    outcome="$(jq -r '.outcome' "${log}")"
    [ "${outcome}" = "failure" ]
}

@test "failure -> audit log contains tool_name field" {
    run_failure_hook_env '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo","content":"test"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local tool_name
    tool_name="$(jq -r '.tool_name' "${log}")"
    [ "${tool_name}" = "Write" ]
}

@test "failure -> audit log contains trust_score_after field (numeric)" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local trust_score_after
    trust_score_after="$(jq -r '.trust_score_after' "${log}")"
    [ "${trust_score_after}" != "null" ]
    awk -v v="${trust_score_after}" 'BEGIN { exit !(v+0 == v) }'
}

@test "failure -> audit log contains session_id field" {
    run_failure_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local session_id
    session_id="$(jq -r '.session_id' "${log}")"
    [ "${session_id}" != "null" ]
    [ -n "${session_id}" ]
}
