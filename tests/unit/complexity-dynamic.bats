#!/usr/bin/env bats
# Unit tests for te_get_complexity and dynamic complexity integration (Phase 2a)

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

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
    config_load

    source "${PROJECT_ROOT}/lib/trust-engine.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# ============================================================
# te_get_complexity — risk_category to complexity mapping
# ============================================================

@test "te_get_complexity 'low' returns 0.2" {
    run te_get_complexity "low"
    assert_success
    assert_output "0.2"
}

@test "te_get_complexity 'medium' returns 0.5" {
    run te_get_complexity "medium"
    assert_success
    assert_output "0.5"
}

@test "te_get_complexity 'high' returns 0.7" {
    run te_get_complexity "high"
    assert_success
    assert_output "0.7"
}

@test "te_get_complexity 'critical' returns 1.0" {
    run te_get_complexity "critical"
    assert_success
    assert_output "1.0"
}

@test "te_get_complexity unknown category returns 0.5 (fallback)" {
    run te_get_complexity "unknown"
    assert_success
    assert_output "0.5"
}

@test "te_get_complexity empty string returns 0.5 (fallback)" {
    run te_get_complexity ""
    assert_success
    assert_output "0.5"
}

# ============================================================
# te_calc_autonomy with dynamic complexity values
# Formula: autonomy = 1 - (λ1 × risk_norm + λ2 × complexity) × (1 - trust)
# λ1=0.6, λ2=0.4, risk_norm = risk_value / 4.0
# ============================================================

@test "te_calc_autonomy trust=0.5 risk=1(low) complexity=0.2 returns 0.885" {
    # autonomy = 1 - (0.6*0.25 + 0.4*0.2) * (1-0.5)
    #          = 1 - (0.15 + 0.08) * 0.5
    #          = 1 - 0.23 * 0.5
    #          = 1 - 0.115 = 0.885
    run te_calc_autonomy "0.5" "1" "0.2"
    assert_success
    assert_output "0.885"
}

@test "te_calc_autonomy trust=0.5 risk=2(medium) complexity=0.5 returns 0.75" {
    # autonomy = 1 - (0.6*0.5 + 0.4*0.5) * (1-0.5)
    #          = 1 - (0.3 + 0.2) * 0.5
    #          = 1 - 0.5 * 0.5
    #          = 1 - 0.25 = 0.75
    run te_calc_autonomy "0.5" "2" "0.5"
    assert_success
    assert_output "0.75"
}

@test "te_calc_autonomy trust=0.5 risk=3(high) complexity=0.7 returns 0.635" {
    # autonomy = 1 - (0.6*0.75 + 0.4*0.7) * (1-0.5)
    #          = 1 - (0.45 + 0.28) * 0.5
    #          = 1 - 0.73 * 0.5
    #          = 1 - 0.365 = 0.635
    run te_calc_autonomy "0.5" "3" "0.7"
    assert_success
    assert_output "0.635"
}

# ============================================================
# config_get: trust.recovery_boost_multiplier default
# ============================================================

@test "config_get trust.recovery_boost_multiplier returns default 1.5" {
    run config_get "trust.recovery_boost_multiplier"
    assert_success
    assert_output "1.5"
}
