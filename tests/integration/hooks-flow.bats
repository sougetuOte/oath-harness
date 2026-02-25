#!/usr/bin/env bats
# Integration tests: hooks end-to-end flow
# AC-011〜AC-014: PreToolUse → PostToolUse → state verification

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

# Helper: run pre-tool-use hook
run_pre() {
    local json="$1"
    run bash "${PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< "${json}"
}

# Helper: run post-tool-use hook (always uses env-passing for state persistence)
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

# Helper: run post-tool-use-failure hook (Phase 2a: failure score update delegated here)
run_post_failure() {
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

# Helper: run stop hook
run_stop() {
    HARNESS_ROOT="${PROJECT_ROOT}" \
    STATE_DIR="${TEST_TMP}" \
    TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json" \
    AUDIT_DIR="${TEST_TMP}/audit" \
    CONFIG_DIR="${TEST_TMP}/config" \
    SETTINGS_FILE="${TEST_TMP}/config/settings.json" \
    OATH_PHASE_FILE="${TEST_TMP}/current-phase.md" \
    bash "${PROJECT_ROOT}/hooks/stop.sh"
}

# Helper: get trust score for a domain
get_score() {
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
# Full flow: PreToolUse → PostToolUse → state verification
# ============================================================

@test "full flow: ls (allow list) -> pre exit 0, post success, score increases" {
    # Step 1: PreToolUse allows ls
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    assert_success

    # Step 2: PostToolUse records success
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"is_error":false}'

    # Step 3: Verify trust score increased from initial 0.3
    local score
    score="$(get_score "file_read")"
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}

@test "full flow: curl (critical) -> pre exit 1, no post needed, audit records blocked" {
    # Step 1: PreToolUse blocks curl
    run_pre '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
    assert_failure
    assert_equal "${status}" "1"
    assert_output --partial "[BLOCKED]"

    # Step 2: Verify audit trail has blocked entry
    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local decision
    decision="$(jq -r '.decision' "${log}")"
    [ "${decision}" = "blocked" ]
}

@test "full flow: multiple tool calls accumulate trust score" {
    # Run 5 successful ls calls through full pre→post cycle
    for i in 1 2 3 4 5; do
        run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
        assert_success
        run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    done

    # Score should be noticeably higher than 0.3
    local score
    score="$(get_score "file_read")"
    awk -v s="${score}" 'BEGIN { exit !(s > 0.36) }'
}

@test "full flow: failure reduces trust score" {
    # First: one success to establish a score
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"},"is_error":false}'

    local score_before
    score_before="$(get_score "file_read")"

    # Then: one failure
    # Phase 2a: PostToolUse(is_error=true) fires first (audit only, no score update)
    # PostToolUseFailure fires second (actual score decay)
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/b"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/b"},"is_error":true}'
    run_post_failure '{"tool_name":"Read","tool_input":{"file_path":"/tmp/b"}}'

    local score_after
    score_after="$(get_score "file_read")"

    # Score after failure should be less than score before failure
    awk -v a="${score_after}" -v b="${score_before}" 'BEGIN { exit !(a < b) }'
}

# ============================================================
# Phase transition affects tool access
# ============================================================

@test "phase transition: Write allowed in BUILDING, blocked in AUDITING" {
    # BUILDING: Write should pass (file_write is allowed)
    echo "BUILDING" > "${OATH_PHASE_FILE}"
    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}'
    assert_success

    # AUDITING: Write should be blocked
    echo "AUDITING" > "${OATH_PHASE_FILE}"
    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}'
    assert_failure
    assert_output --partial "[BLOCKED]"
}

@test "phase transition: Read allowed in all phases" {
    for phase in PLANNING BUILDING AUDITING; do
        echo "${phase}" > "${OATH_PHASE_FILE}"
        run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
        assert_success
    done
}

# ============================================================
# Stop hook finalization
# ============================================================

@test "stop hook updates updated_at after tool operations" {
    # Run a tool call first to create trust-scores.json
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    # Run stop hook
    run_stop

    # Verify updated_at is valid ISO 8601 format
    local after
    after="$(jq -r '.updated_at' "${TRUST_SCORES_FILE}")"
    [[ "${after}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "stop hook preserves trust scores" {
    # Build up some trust
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local score_before
    score_before="$(get_score "file_read")"

    # Stop should not change scores
    run_stop

    local score_after
    score_after="$(get_score "file_read")"
    [ "${score_before}" = "${score_after}" ]
}

# ============================================================
# Audit trail across multiple hooks
# ============================================================

@test "audit trail: pre and post entries recorded for same tool call" {
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"is_error":false}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    # Should have at least 2 lines: pre entry + outcome entry
    local count
    count="$(wc -l < "${log}")"
    [ "${count}" -ge 2 ]

    # First line should have decision field (pre entry)
    local first_decision
    first_decision="$(head -1 "${log}" | jq -r '.decision // empty')"
    [ -n "${first_decision}" ]

    # Last line should have outcome field (post entry)
    local last_outcome
    last_outcome="$(tail -1 "${log}" | jq -r '.outcome // empty')"
    [ "${last_outcome}" = "success" ]
}

@test "audit trail: all entries are valid JSONL" {
    # Multiple operations
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"is_error":false}'
    run_pre '{"tool_name":"Bash","tool_input":{"command":"curl https://evil.com"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    # Every line must be valid JSON
    local invalid=0
    while IFS= read -r line; do
        if ! echo "${line}" | jq . > /dev/null 2>&1; then
            invalid=$((invalid + 1))
        fi
    done < "${log}"
    [ "${invalid}" -eq 0 ]
}

# ============================================================
# Domain isolation: different tools affect different domains
# ============================================================

@test "domain isolation: Read and Write affect different domain scores" {
    # Success on Read (file_read domain)
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"},"is_error":false}'

    # Failure on Write (file_write domain)
    # Phase 2a: PostToolUse(is_error=true) fires first (audit only, no score update)
    # PostToolUseFailure fires second (actual score decay)
    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/b","content":"x"}}'
    run_post '{"tool_name":"Write","tool_input":{"file_path":"/tmp/b","content":"x"},"is_error":true}'
    run_post_failure '{"tool_name":"Write","tool_input":{"file_path":"/tmp/b","content":"x"}}'

    local read_score write_score
    read_score="$(get_score "file_read")"
    write_score="$(get_score "file_write")"

    # file_read should have increased, file_write should have decreased
    awk -v r="${read_score}" 'BEGIN { exit !(r > 0.3) }'
    awk -v w="${write_score}" 'BEGIN { exit !(w < 0.3) }'
}

# ============================================================
# Error recovery: hooks handle malformed input gracefully
# ============================================================

@test "error recovery: invalid pre input does not corrupt state for subsequent valid calls" {
    # First: invalid input (blocked)
    run_pre 'not-json'
    assert_failure

    # Then: valid input should still work
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_success
}
