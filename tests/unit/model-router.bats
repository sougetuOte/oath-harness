#!/usr/bin/env bats
# Unit tests for lib/model-router.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${PROJECT_ROOT}/config"
    export SETTINGS_FILE="${PROJECT_ROOT}/config/settings.json"

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
    config_load
    source "${PROJECT_ROOT}/lib/model-router.sh"
}

# --- mr_recommend ---

@test "mr_recommend: blocked critical → opus" {
    run mr_recommend "0.2" "critical" "0.3" "blocked"
    assert_success
    assert_output "opus"
}

@test "mr_recommend: low trust (< 0.4) → opus" {
    run mr_recommend "0.5" "medium" "0.3" "logged_only"
    assert_success
    assert_output "opus"
}

@test "mr_recommend: low autonomy + medium risk → opus" {
    run mr_recommend "0.5" "medium" "0.6" "logged_only"
    assert_success
    assert_output "opus"
}

@test "mr_recommend: auto_approved + low risk → haiku" {
    run mr_recommend "0.9" "low" "0.8" "auto_approved"
    assert_success
    assert_output "haiku"
}

@test "mr_recommend: default case → sonnet" {
    run mr_recommend "0.7" "medium" "0.7" "logged_only"
    assert_success
    assert_output "sonnet"
}

@test "mr_recommend: high autonomy + high risk → sonnet (not haiku)" {
    run mr_recommend "0.85" "high" "0.8" "auto_approved"
    assert_success
    assert_output "sonnet"
}

# --- mr_get_persona ---

@test "mr_get_persona: opus → architect" {
    run mr_get_persona "opus"
    assert_success
    assert_output "architect"
}

@test "mr_get_persona: sonnet → analyst" {
    run mr_get_persona "sonnet"
    assert_success
    assert_output "analyst"
}

@test "mr_get_persona: haiku → worker" {
    run mr_get_persona "haiku"
    assert_success
    assert_output "worker"
}

@test "mr_get_persona: unknown → analyst (default)" {
    run mr_get_persona "unknown"
    assert_success
    assert_output "analyst"
}
