#!/usr/bin/env bats
# Unit tests for lib/common.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${PROJECT_ROOT}/lib/common.sh"
}

# --- Path constants ---

@test "HARNESS_ROOT is set to project root" {
    assert [ -n "${HARNESS_ROOT}" ]
    assert [ -d "${HARNESS_ROOT}" ]
}

@test "CONFIG_DIR points to config/" {
    assert_equal "${CONFIG_DIR}" "${HARNESS_ROOT}/config"
}

@test "STATE_DIR points to state/" {
    assert_equal "${STATE_DIR}" "${HARNESS_ROOT}/state"
}

@test "AUDIT_DIR points to audit/" {
    assert_equal "${AUDIT_DIR}" "${HARNESS_ROOT}/audit"
}

@test "LIB_DIR points to lib/" {
    assert_equal "${LIB_DIR}" "${HARNESS_ROOT}/lib"
}

@test "SETTINGS_FILE points to config/settings.json" {
    assert_equal "${SETTINGS_FILE}" "${HARNESS_ROOT}/config/settings.json"
}

@test "TRUST_SCORES_FILE points to state/trust-scores.json" {
    assert_equal "${TRUST_SCORES_FILE}" "${HARNESS_ROOT}/state/trust-scores.json"
}

# --- Logging functions ---

@test "log_info outputs to stderr with [INFO] prefix" {
    run log_info "test message"
    assert_success
    assert_output --partial "[INFO]"
    assert_output --partial "test message"
}

@test "log_error outputs to stderr with [ERROR] prefix" {
    run log_error "error message"
    assert_success
    assert_output --partial "[ERROR]"
    assert_output --partial "error message"
}

@test "log_debug outputs nothing when OATH_DEBUG is unset" {
    unset OATH_DEBUG
    run log_debug "debug message"
    assert_success
    assert_output ""
}

@test "log_debug outputs to stderr when OATH_DEBUG=1" {
    OATH_DEBUG=1
    run log_debug "debug message"
    assert_success
    assert_output --partial "[DEBUG]"
    assert_output --partial "debug message"
}

# --- Float comparison ---

@test "_float_cmp returns 0 (true) for true expression" {
    run _float_cmp "0.8 > 0.5"
    assert_success
}

@test "_float_cmp returns 1 (false) for false expression" {
    run _float_cmp "0.3 > 0.5"
    assert_failure
}

@test "_float_cmp handles equality" {
    run _float_cmp "0.5 == 0.5"
    assert_success
}

# --- flock wrapper ---

@test "with_flock executes command under lock" {
    local tmpfile lockfile
    tmpfile="$(mktemp)"
    lockfile="$(mktemp)"
    echo "original" > "${tmpfile}"
    run with_flock "${lockfile}" 5 cat "${tmpfile}"
    assert_success
    assert_output "original"
    rm -f "${tmpfile}" "${lockfile}"
}

@test "with_flock returns failure on timeout" {
    local lockfile
    lockfile="$(mktemp)"
    # Hold the lock on the .lock file (same file with_flock uses)
    exec 200>"${lockfile}.lock"
    flock -n 200
    run with_flock "${lockfile}" 1 echo "should timeout"
    assert_failure
    exec 200>&-
    rm -f "${lockfile}" "${lockfile}.lock"
}

# --- ISO 8601 datetime ---

@test "now_iso8601 returns valid ISO 8601 format" {
    run now_iso8601
    assert_success
    # Match YYYY-MM-DDTHH:MM:SS pattern
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

# --- UUID ---

@test "generate_session_id returns non-empty string" {
    run generate_session_id
    assert_success
    assert [ -n "${output}" ]
}
