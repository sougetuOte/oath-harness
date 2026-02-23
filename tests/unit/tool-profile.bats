#!/usr/bin/env bats
# Unit tests for lib/tool-profile.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${PROJECT_ROOT}/config"
    export SETTINGS_FILE="${PROJECT_ROOT}/config/settings.json"

    # Mock .claude/current-phase.md
    mkdir -p "${TEST_TMP}/.claude"
    export OATH_PHASE_FILE="${TEST_TMP}/.claude/current-phase.md"

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
    config_load
    source "${PROJECT_ROOT}/lib/tool-profile.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# --- tpe_get_current_phase ---

@test "tpe_get_current_phase returns planning when file says PLANNING" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_get_current_phase
    assert_success
    assert_output "planning"
}

@test "tpe_get_current_phase returns building when file says BUILDING" {
    echo "BUILDING" > "${OATH_PHASE_FILE}"
    run tpe_get_current_phase
    assert_success
    assert_output "building"
}

@test "tpe_get_current_phase returns auditing when file says AUDITING" {
    echo "AUDITING" > "${OATH_PHASE_FILE}"
    run tpe_get_current_phase
    assert_success
    assert_output "auditing"
}

@test "tpe_get_current_phase returns auditing when file missing" {
    rm -f "${OATH_PHASE_FILE}"
    run tpe_get_current_phase
    assert_success
    assert_output "auditing"
}

@test "tpe_get_current_phase returns auditing for unknown phase" {
    echo "UNKNOWN" > "${OATH_PHASE_FILE}"
    run tpe_get_current_phase
    assert_success
    assert_output "auditing"
}

# --- tpe_check: PLANNING ---

@test "tpe_check: PLANNING blocks shell_exec" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_check "Bash" "shell_exec" "planning"
    assert_success
    assert_output "blocked"
}

@test "tpe_check: PLANNING blocks file_write" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_check "Write" "file_write" "planning"
    assert_success
    assert_output "blocked"
}

@test "tpe_check: PLANNING allows file_read" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_check "Read" "file_read" "planning"
    assert_success
    assert_output "allowed"
}

@test "tpe_check: PLANNING allows docs_write" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_check "Write" "docs_write" "planning"
    assert_success
    assert_output "allowed"
}

@test "tpe_check: PLANNING blocks git_remote" {
    echo "PLANNING" > "${OATH_PHASE_FILE}"
    run tpe_check "Bash" "git_remote" "planning"
    assert_success
    assert_output "blocked"
}

# --- tpe_check: BUILDING ---

@test "tpe_check: BUILDING allows file_read" {
    run tpe_check "Read" "file_read" "building"
    assert_success
    assert_output "allowed"
}

@test "tpe_check: BUILDING allows file_write" {
    run tpe_check "Write" "file_write" "building"
    assert_success
    assert_output "allowed"
}

@test "tpe_check: BUILDING trust_gates shell_exec" {
    run tpe_check "Bash" "shell_exec" "building"
    assert_success
    assert_output "trust_gated"
}

@test "tpe_check: BUILDING trust_gates git_local" {
    run tpe_check "Bash" "git_local" "building"
    assert_success
    assert_output "trust_gated"
}

@test "tpe_check: BUILDING blocks git_remote" {
    run tpe_check "Bash" "git_remote" "building"
    assert_success
    assert_output "blocked"
}

# --- tpe_check: AUDITING ---

@test "tpe_check: AUDITING allows file_read" {
    run tpe_check "Read" "file_read" "auditing"
    assert_success
    assert_output "allowed"
}

@test "tpe_check: AUDITING blocks file_write" {
    run tpe_check "Write" "file_write" "auditing"
    assert_success
    assert_output "blocked"
}

@test "tpe_check: AUDITING blocks shell_exec" {
    run tpe_check "Bash" "shell_exec" "auditing"
    assert_success
    assert_output "blocked"
}

@test "tpe_check: AUDITING blocks git_local" {
    run tpe_check "Bash" "git_local" "auditing"
    assert_success
    assert_output "blocked"
}

# --- Edge cases ---

@test "tpe_check: unknown phase defaults to auditing (blocks file_write)" {
    run tpe_check "Write" "file_write" "unknown"
    assert_success
    assert_output "blocked"
}
