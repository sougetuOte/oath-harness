#!/usr/bin/env bats
# Unit tests for hooks/post-tool-use.sh
# AC-012: PostToolUse フック動作検証

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

# Helper: run post-tool-use.sh with given JSON piped via stdin
run_post_hook() {
    local json="$1"
    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< "${json}"
}

# Helper: run post-tool-use.sh passing env vars explicitly (subprocess isolation)
run_post_hook_env() {
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

# Helper: get trust score for a domain from trust-scores.json
get_domain_score() {
    local domain="$1"
    jq -r --arg d "${domain}" '.domains[$d].score // .domains._global.score // 0.3' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# Helper: get today's audit file path
audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${TEST_TMP}/audit/${today}.jsonl"
}

# ============================================================
# AC-012-1: ツール実行成功 (is_error=false) -> exit 0 + スコア増加
# ============================================================

@test "success result (is_error=false) -> exit 0" {
    run_post_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    assert_success
}

@test "success result (is_error=false) -> trust score increases" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    # initial_score=0.3, boost_threshold=20, total_ops=0 (<20), is_warming_up=false
    # rate=0.05, new_score = 0.3 + (1-0.3)*0.05 = 0.3 + 0.035 = 0.335
    local score
    score="$(get_domain_score "file_read")"
    # score should be greater than 0.3
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}

# ============================================================
# AC-012-2: ツール実行失敗 (is_error=true) -> exit 0 + スコア減衰
# ============================================================

@test "failure result (is_error=true) -> exit 0" {
    run_post_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'
    assert_success
}

@test "failure result (is_error=true) -> trust score decreases" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

    # failure_decay=0.85, new_score = 0.3 * 0.85 = 0.255
    local score
    score="$(get_domain_score "file_read")"
    # score should be less than 0.3
    awk -v s="${score}" 'BEGIN { exit !(s < 0.3) }'
}

@test "failure result (is_error=true) -> score approximately 0.255" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

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
# AC-012-3: is_error フィールドなし -> exit 0 + outcome=success として処理
# ============================================================

@test "missing is_error field -> exit 0" {
    run_post_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_success
}

@test "missing is_error field -> treated as success (score increases)" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local score
    score="$(get_domain_score "file_read")"
    # Score should increase (default outcome=success)
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}

# ============================================================
# AC-012-4: audit ログに outcome エントリが記録される
# ============================================================

@test "audit log entry is written after success" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
}

@test "audit log contains outcome=success for is_error=false" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local outcome
    outcome="$(jq -r '.outcome' "${log}")"
    [ "${outcome}" = "success" ]
}

@test "audit log contains outcome=failure for is_error=true" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local outcome
    outcome="$(jq -r '.outcome' "${log}")"
    [ "${outcome}" = "failure" ]
}

@test "audit log entry contains tool_name field" {
    run_post_hook_env '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local tool_name
    tool_name="$(jq -r '.tool_name' "${log}")"
    [ "${tool_name}" = "Read" ]
}

@test "audit log entry contains trust_score_after field (numeric)" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local trust_score_after
    trust_score_after="$(jq -r '.trust_score_after' "${log}")"
    # Must be a number (not null)
    [ "${trust_score_after}" != "null" ]
    awk -v v="${trust_score_after}" 'BEGIN { exit !(v+0 == v) }'
}

@test "audit log entry contains session_id field" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local session_id
    session_id="$(jq -r '.session_id' "${log}")"
    [ "${session_id}" != "null" ]
    [ -n "${session_id}" ]
}

# ============================================================
# AC-012-5: 複数回呼び出しでスコアが蓄積される
# ============================================================

@test "multiple success calls accumulate score" {
    # Call 3 times with success
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local score
    score="$(get_domain_score "file_read")"
    # After 3 successes from 0.3, score should be > 0.345 (rough bound)
    awk -v s="${score}" 'BEGIN { exit !(s > 0.345) }'
}

@test "audit log has multiple entries after multiple calls" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local log
    log="$(audit_file)"
    local count
    count="$(wc -l < "${log}")"
    [ "${count}" -ge 2 ]
}

# ============================================================
# AC-012-6: 不正な JSON -> exit 0 (エラーでもブロックしない)
# ============================================================

@test "invalid JSON -> exit 0 (PostToolUse never blocks)" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< "not valid json"
    assert_success
}

@test "malformed JSON with missing braces -> exit 0" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< '{"tool_name":'
    assert_success
}

# ============================================================
# AC-012-7: 空の stdin -> exit 0
# ============================================================

@test "empty stdin -> exit 0" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< ""
    assert_success
}

# ============================================================
# Additional: domain mapping via rcm_get_domain
# ============================================================

@test "Write tool with is_error=false updates file_write domain score" {
    run_post_hook_env '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hi"},"is_error":false}'

    local score
    score="$(get_domain_score "file_write")"
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}

@test "is_error=true with Bash failure updates score for correct domain" {
    run_post_hook_env '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

    # ls maps to file_read domain via rcm_get_domain
    local score
    score="$(get_domain_score "file_read")"
    awk -v s="${score}" 'BEGIN { exit !(s < 0.3) }'
}
