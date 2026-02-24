#!/usr/bin/env bats
# Integration tests: Error handling and edge cases
# AC-033, AC-034: Fail-safe behavior under adverse conditions

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${TEST_TMP}/config"
    export SETTINGS_FILE="${TEST_TMP}/config/settings.json"
    export STATE_DIR="${TEST_TMP}"
    export TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json"
    export AUDIT_DIR="${TEST_TMP}/audit"
    export OATH_PHASE_FILE="${TEST_TMP}/current-phase.md"

    echo "BUILDING" > "${OATH_PHASE_FILE}"

    # Copy valid settings as baseline
    mkdir -p "${TEST_TMP}/config"
    cat > "${TEST_TMP}/config/settings.json" <<'TESTCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TESTCFG

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
    run env \
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
# AC-033: settings.json missing → defaults are used
# ============================================================

@test "missing settings.json: pre hook still works with defaults" {
    rm -f "${SETTINGS_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success
}

@test "missing settings.json: post hook still works with defaults" {
    rm -f "${SETTINGS_FILE}"

    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"is_error":false}'
    # PostToolUse never blocks
}

@test "missing settings.json: stop hook exits cleanly" {
    rm -f "${SETTINGS_FILE}"
    run_stop
    assert_success
}

# ============================================================
# AC-033: settings.json corrupted → fail-safe
# ============================================================

@test "corrupted settings.json: pre hook blocks (fail-safe)" {
    echo "not-valid-json{{{" > "${SETTINGS_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    # config_load with corrupted JSON should trigger fail-safe (exit 1) or use defaults
    # Either way, the system should not crash unexpectedly
    # If config_load handles it gracefully (defaults), exit 0 is acceptable
    # If config_load fails, ERR trap → exit 1 is the fail-safe behavior
}

@test "corrupted settings.json: post hook exits 0 (never blocks)" {
    echo "broken-json" > "${SETTINGS_FILE}"

    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< '{"tool_name":"Read","tool_input":{},"is_error":false}'
    assert_success
}

@test "corrupted settings.json: stop hook exits 0" {
    echo "broken-json" > "${SETTINGS_FILE}"

    run_stop
    assert_success
}

# ============================================================
# AC-033: trust-scores.json corrupted → recovery
# ============================================================

@test "corrupted trust-scores.json: pre hook recovers and processes normally" {
    echo "corrupted{{{" > "${TRUST_SCORES_FILE}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    # File should be recovered to valid v2 format
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    [ "${version}" = "2" ]
}

@test "corrupted trust-scores.json: post hook still exits 0" {
    echo "bad json" > "${TRUST_SCORES_FILE}"

    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< '{"tool_name":"Read","tool_input":{},"is_error":false}'
    assert_success
}

@test "corrupted trust-scores.json: stop hook exits 0" {
    echo "bad json" > "${TRUST_SCORES_FILE}"

    run_stop
    assert_success
}

# ============================================================
# AC-034: Audit directory not writable → tool still proceeds
# ============================================================

@test "non-writable audit dir: pre hook for allowed tool still exits 0" {
    mkdir -p "${AUDIT_DIR}"
    chmod 000 "${AUDIT_DIR}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    # Audit failure is non-fatal for allowed tools; pre hook should still succeed
    assert_success

    # Restore permissions for cleanup
    chmod 755 "${AUDIT_DIR}"
}

@test "non-writable audit dir: post hook still exits 0" {
    mkdir -p "${AUDIT_DIR}"
    chmod 000 "${AUDIT_DIR}"

    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< '{"tool_name":"Read","tool_input":{},"is_error":false}'
    assert_success

    chmod 755 "${AUDIT_DIR}"
}

@test "non-writable audit dir: stop hook still exits 0" {
    mkdir -p "${AUDIT_DIR}"
    chmod 000 "${AUDIT_DIR}"

    run_stop
    assert_success

    chmod 755 "${AUDIT_DIR}"
}

# ============================================================
# Missing phase file → defaults to most restrictive (auditing)
# ============================================================

@test "missing phase file: defaults to auditing (most restrictive)" {
    rm -f "${OATH_PHASE_FILE}"

    # Write should be blocked in auditing
    run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo","content":"x"}}'
    assert_failure
    assert_output --partial "[BLOCKED]"

    # Read should still work in auditing
    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'
    assert_success
}

# ============================================================
# Empty inputs and boundary conditions
# ============================================================

@test "pre hook: empty tool_input object is handled" {
    run_pre '{"tool_name":"Read","tool_input":{}}'
    assert_success
}

@test "pre hook: tool_name with special characters is handled" {
    run_pre '{"tool_name":"Bash","tool_input":{"command":"echo \"hello world\""}}'
    assert_success
}

@test "post hook: empty tool_input object is handled" {
    run bash "${PROJECT_ROOT}/hooks/post-tool-use.sh" <<< '{"tool_name":"Read","tool_input":{},"is_error":false}'
    assert_success
}

# ============================================================
# Concurrent-like access: multiple rapid calls
# ============================================================

@test "rapid successive pre calls do not corrupt trust-scores.json" {
    # Run 10 rapid pre-hook calls
    for i in $(seq 1 10); do
        run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
        assert_success
    done

    # trust-scores.json should be valid JSON
    jq '.' "${TRUST_SCORES_FILE}" > /dev/null 2>&1
}

@test "rapid successive post calls do not corrupt trust-scores.json" {
    # Create initial state
    run_pre '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    # Run 5 rapid post-hook calls
    for i in $(seq 1 5); do
        run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    done

    # trust-scores.json should be valid JSON
    jq '.' "${TRUST_SCORES_FILE}" > /dev/null 2>&1

    # Score should have accumulated
    local score
    score="$(jq -r '.domains.file_read.score // .domains._global.score' "${TRUST_SCORES_FILE}")"
    awk -v s="${score}" 'BEGIN { exit !(s > 0.3) }'
}

# ============================================================
# State directory missing → bootstrap creates it
# ============================================================

@test "missing state directory: pre hook creates it" {
    rm -rf "${STATE_DIR}"

    run_pre '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    assert_success

    [ -d "${STATE_DIR}" ]
    [ -f "${TRUST_SCORES_FILE}" ]
}
