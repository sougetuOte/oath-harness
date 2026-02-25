#!/usr/bin/env bats
# Unit tests for lib/bootstrap.sh

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

# ---------------------------------------------------------------------------
# Phase 2a field backfill tests
# ---------------------------------------------------------------------------

@test "sb_ensure_initialized backfills phase2a fields for phase1 format domain" {
    # Phase 1 format: domains have no consecutive_failures, pre_failure_score, is_recovering
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 10,
  "domains": {
    "_global": {
      "score": 0.5,
      "successes": 10,
      "failures": 0,
      "total_operations": 10,
      "last_operated_at": "2026-02-20T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
EOF
    sb_ensure_initialized

    local cf pfs ir
    cf="$(jq -r '.domains._global.consecutive_failures' "${TRUST_SCORES_FILE}")"
    pfs="$(jq -r '.domains._global.pre_failure_score' "${TRUST_SCORES_FILE}")"
    ir="$(jq -r '.domains._global.is_recovering' "${TRUST_SCORES_FILE}")"

    assert_equal "${cf}" "0"
    assert_equal "${pfs}" "null"
    assert_equal "${ir}" "false"
}

@test "sb_ensure_initialized preserves existing phase2a field values" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 30,
  "domains": {
    "_global": {
      "score": 0.4,
      "successes": 25,
      "failures": 5,
      "total_operations": 30,
      "last_operated_at": "2026-02-20T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 3,
      "pre_failure_score": 0.7,
      "is_recovering": true
    }
  }
}
EOF
    sb_ensure_initialized

    local cf pfs ir
    cf="$(jq -r '.domains._global.consecutive_failures' "${TRUST_SCORES_FILE}")"
    pfs="$(jq -r '.domains._global.pre_failure_score' "${TRUST_SCORES_FILE}")"
    ir="$(jq -r '.domains._global.is_recovering' "${TRUST_SCORES_FILE}")"

    assert_equal "${cf}" "3"
    assert_equal "${pfs}" "0.7"
    assert_equal "${ir}" "true"
}

@test "sb_ensure_initialized backfills phase2a fields for all domains" {
    cat > "${TRUST_SCORES_FILE}" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-20T00:00:00Z",
  "global_operation_count": 80,
  "domains": {
    "_global": {
      "score": 0.5,
      "successes": 40,
      "failures": 2,
      "total_operations": 42,
      "last_operated_at": "2026-02-20T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "file_read": {
      "score": 0.75,
      "successes": 35,
      "failures": 1,
      "total_operations": 36,
      "last_operated_at": "2026-02-20T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": 0.4,
      "successes": 20,
      "failures": 5,
      "total_operations": 25,
      "last_operated_at": "2026-02-20T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
EOF
    sb_ensure_initialized

    # All three domains must have the new fields
    local domains="_global file_read shell_exec"
    for domain in ${domains}; do
        local cf
        cf="$(jq -r --arg d "${domain}" '.domains[$d].consecutive_failures' "${TRUST_SCORES_FILE}")"
        assert_equal "${cf}" "0" "domain ${domain}: consecutive_failures should be 0"

        local pfs
        pfs="$(jq -r --arg d "${domain}" '.domains[$d].pre_failure_score' "${TRUST_SCORES_FILE}")"
        assert_equal "${pfs}" "null" "domain ${domain}: pre_failure_score should be null"

        local ir
        ir="$(jq -r --arg d "${domain}" '.domains[$d].is_recovering' "${TRUST_SCORES_FILE}")"
        assert_equal "${ir}" "false" "domain ${domain}: is_recovering should be false"
    done
}

@test "_sb_ensure_phase2a_fields does nothing when trust-scores.json is absent" {
    rm -f "${TRUST_SCORES_FILE}"
    # Must not error even when file does not exist
    _sb_ensure_phase2a_fields
    assert [ ! -f "${TRUST_SCORES_FILE}" ]
}
