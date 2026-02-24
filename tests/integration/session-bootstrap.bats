#!/usr/bin/env bats
# Integration tests: Session Trust Bootstrap
# AC-028〜AC-030: Session initialization and persistence through hooks

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

# Helper: run post hook with env
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

# ============================================================
# AC-028: Fresh start - no trust-scores.json
# ============================================================

@test "fresh start: pre hook creates trust-scores.json when missing" {
    rm -f "${TRUST_SCORES_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    [ -f "${TRUST_SCORES_FILE}" ]
}

@test "fresh start: created trust-scores.json is v2 format with initial score 0.3" {
    rm -f "${TRUST_SCORES_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'

    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    [ "${version}" = "2" ]

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    [ "${score}" = "0.3" ]
}

# ============================================================
# AC-029: Existing v2 state is preserved
# ============================================================

@test "existing state: pre hook preserves existing scores" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 100,
  "domains": {
    "_global": { "score": 0.3, "successes": 0, "failures": 0, "total_operations": 0,
                 "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 },
    "file_read": { "score": 0.8, "successes": 80, "failures": 5, "total_operations": 85,
                   "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 }
  }
}
EOF

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    # file_read score should still be 0.8 (pre hook doesn't change scores)
    local score
    score="$(jq -r '.domains.file_read.score' "${TRUST_SCORES_FILE}")"
    [ "${score}" = "0.8" ]
}

@test "existing state: post hook updates score on top of existing" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 100,
  "domains": {
    "_global": { "score": 0.3, "successes": 0, "failures": 0, "total_operations": 0,
                 "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 },
    "file_read": { "score": 0.8, "successes": 80, "failures": 5, "total_operations": 85,
                   "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 }
  }
}
EOF

    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"is_error":false}'

    local score
    score="$(jq -r '.domains.file_read.score' "${TRUST_SCORES_FILE}")"
    # Should be > 0.8 (success on existing 0.8)
    awk -v s="${score}" 'BEGIN { exit !(s > 0.8) }'
}

# ============================================================
# AC-030: v1 migration through hook flow
# ============================================================

@test "v1 migration: pre hook migrates v1 format to v2" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "score": 0.65,
  "successes": 30,
  "failures": 5
}
EOF

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    [ "${version}" = "2" ]

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    [ "${score}" = "0.65" ]

    local successes
    successes="$(jq -r '.domains._global.successes' "${TRUST_SCORES_FILE}")"
    [ "${successes}" = "30" ]
}

# ============================================================
# Corrupted state recovery
# ============================================================

@test "corrupted state: pre hook recovers from corrupted trust-scores.json" {
    echo "not valid json at all" > "${TRUST_SCORES_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    # Should have been reset to defaults
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    [ "${version}" = "2" ]

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    [ "${score}" = "0.3" ]
}

# ============================================================
# Session lifecycle: init → operations → stop → verify persisted
# ============================================================

@test "full session lifecycle: init -> tool calls -> stop -> state persisted" {
    rm -f "${TRUST_SCORES_FILE}"

    # Step 1: First tool call initializes session
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_success
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    # Step 2: More tool calls
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}'
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"},"is_error":false}'

    # Step 3: Record scores before stop
    local score_before
    score_before="$(jq -r '.domains.file_read.score' "${TRUST_SCORES_FILE}")"
    awk -v s="${score_before}" 'BEGIN { exit !(s > 0.3) }'

    # Step 4: Stop hook finalizes
    run_stop

    # Step 5: Verify state is still valid after stop
    [ -f "${TRUST_SCORES_FILE}" ]
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    [ "${version}" = "2" ]

    # Score should be preserved (stop doesn't change scores)
    local score_after
    score_after="$(jq -r '.domains.file_read.score' "${TRUST_SCORES_FILE}")"
    [ "${score_before}" = "${score_after}" ]

    # updated_at should be set
    local updated_at
    updated_at="$(jq -r '.updated_at' "${TRUST_SCORES_FILE}")"
    [ "${updated_at}" != "null" ]
    [[ "${updated_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# ============================================================
# New domain creation through hook flow
# ============================================================

@test "new domain: first Write creates file_write domain in trust-scores.json" {
    rm -f "${TRUST_SCORES_FILE}"

    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/new.txt","content":"hi"}}'
    assert_success
    run_post '{"tool_name":"Write","tool_input":{"file_path":"/tmp/new.txt","content":"hi"},"is_error":false}'

    # file_write domain should now exist with score > initial
    local score
    score="$(jq -r '.domains.file_write.score // "missing"' "${TRUST_SCORES_FILE}")"
    [ "${score}" != "missing" ]
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}
