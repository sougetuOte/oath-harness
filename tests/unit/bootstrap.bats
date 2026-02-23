#!/usr/bin/env bats
# Unit tests for lib/bootstrap.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${PROJECT_ROOT}/config"
    export SETTINGS_FILE="${PROJECT_ROOT}/config/settings.json"
    export STATE_DIR="${TEST_TMP}"
    export TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json"

    # Reset initialization flag
    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
    config_load
    source "${PROJECT_ROOT}/lib/trust-engine.sh"
    source "${PROJECT_ROOT}/lib/bootstrap.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

@test "sb_ensure_initialized creates trust-scores.json when missing" {
    rm -f "${TRUST_SCORES_FILE}"
    sb_ensure_initialized
    assert [ -f "${TRUST_SCORES_FILE}" ]
}

@test "sb_ensure_initialized creates v2 format with _global domain" {
    rm -f "${TRUST_SCORES_FILE}"
    sb_ensure_initialized
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    assert_equal "${version}" "2"

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    assert_equal "${score}" "0.3"
}

@test "sb_ensure_initialized sets session_id" {
    sb_ensure_initialized
    assert [ -n "${OATH_HARNESS_SESSION_ID}" ]
}

@test "sb_ensure_initialized is idempotent" {
    sb_ensure_initialized
    local first_sid="${OATH_HARNESS_SESSION_ID}"
    sb_ensure_initialized
    assert_equal "${OATH_HARNESS_SESSION_ID}" "${first_sid}"
}

@test "sb_ensure_initialized preserves existing scores" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 50,
  "domains": {
    "_global": { "score": 0.3, "successes": 0, "failures": 0, "total_operations": 0,
                 "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 },
    "file_read": { "score": 0.75, "successes": 40, "failures": 2, "total_operations": 42,
                   "last_operated_at": "2026-02-20T00:00:00Z", "is_warming_up": false, "warmup_remaining": 0 }
  }
}
EOF
    sb_ensure_initialized
    local score
    score="$(jq -r '.domains.file_read.score' "${TRUST_SCORES_FILE}")"
    assert_equal "${score}" "0.75"
}

@test "sb_ensure_initialized migrates v1 to v2 format" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "score": 0.6,
  "successes": 20,
  "failures": 3
}
EOF
    sb_ensure_initialized
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    assert_equal "${version}" "2"

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    assert_equal "${score}" "0.6"
}

@test "sb_ensure_initialized handles corrupted JSON" {
    echo "not valid json" > "${TRUST_SCORES_FILE}"
    sb_ensure_initialized
    # Should reset to defaults
    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    assert_equal "${version}" "2"
    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    assert_equal "${score}" "0.3"
}

@test "sb_get_session_id returns consistent value within session" {
    sb_ensure_initialized
    local sid1 sid2
    sid1="$(sb_get_session_id)"
    sid2="$(sb_get_session_id)"
    assert_equal "${sid1}" "${sid2}"
}
