#!/usr/bin/env bats
# Unit tests for lib/trust-engine.sh

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

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
    config_load

    source "${PROJECT_ROOT}/lib/trust-engine.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# Helper: create a v2 trust-scores.json with given domain scores
create_trust_scores() {
    local json="$1"
    echo "${json}" > "${TRUST_SCORES_FILE}"
}

# ============================================================
# Task 2-2: te_get_score / te_calc_autonomy
# ============================================================

@test "te_get_score returns _global score when file has _global domain" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    run te_get_score "_global"
    assert_success
    assert_output "0.3"
}

@test "te_get_score returns specific domain score" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{
            "_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0},
            "file_read":{"score":0.7,"successes":10,"failures":0,"total_operations":10,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}
        }
    }'
    run te_get_score "file_read"
    assert_success
    assert_output "0.7"
}

@test "te_get_score falls back to _global for unknown domain" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    run te_get_score "unknown_domain"
    assert_success
    assert_output "0.3"
}

@test "te_get_score returns initial_score when file missing" {
    rm -f "${TRUST_SCORES_FILE}"
    run te_get_score "file_read"
    assert_success
    assert_output "0.3"
}

# --- te_calc_autonomy ---
# Formula: autonomy = 1 - (λ1 × risk_norm + λ2 × complexity) × (1 - trust)
# λ1=0.6, λ2=0.4, risk_norm = risk_value/4.0

@test "te_calc_autonomy with trust=0.3, risk=1(low), complexity=0.5" {
    # autonomy = 1 - (0.6*0.25 + 0.4*0.5) * (1-0.3)
    #          = 1 - (0.15 + 0.2) * 0.7
    #          = 1 - 0.35 * 0.7
    #          = 1 - 0.245 = 0.755
    run te_calc_autonomy "0.3" "1" "0.5"
    assert_success
    assert_output "0.755"
}

@test "te_calc_autonomy with trust=0.8, risk=2(medium), complexity=0.5" {
    # autonomy = 1 - (0.6*0.5 + 0.4*0.5) * (1-0.8)
    #          = 1 - (0.3 + 0.2) * 0.2
    #          = 1 - 0.5 * 0.2
    #          = 1 - 0.1 = 0.9
    run te_calc_autonomy "0.8" "2" "0.5"
    assert_success
    assert_output "0.9"
}

@test "te_calc_autonomy with trust=0.5, risk=3(high), complexity=0.5" {
    # autonomy = 1 - (0.6*0.75 + 0.4*0.5) * (1-0.5)
    #          = 1 - (0.45 + 0.2) * 0.5
    #          = 1 - 0.65 * 0.5
    #          = 1 - 0.325 = 0.675
    run te_calc_autonomy "0.5" "3" "0.5"
    assert_success
    assert_output "0.675"
}

@test "te_calc_autonomy with trust=0.0, risk=4(critical), complexity=0.5" {
    # autonomy = 1 - (0.6*1.0 + 0.4*0.5) * (1-0.0)
    #          = 1 - (0.6 + 0.2) * 1.0
    #          = 1 - 0.8 = 0.2
    run te_calc_autonomy "0.0" "4" "0.5"
    assert_success
    assert_output "0.2"
}

@test "te_calc_autonomy with trust=1.0 always returns 1.0" {
    run te_calc_autonomy "1.0" "4" "0.5"
    assert_success
    assert_output "1"
}

@test "te_calc_autonomy defaults complexity to 0.5" {
    # Same as trust=0.3, risk=1 test above
    run te_calc_autonomy "0.3" "1"
    assert_success
    assert_output "0.755"
}

# ============================================================
# Task 2-3: te_decide (will be added here)
# ============================================================

@test "te_decide returns blocked for critical regardless of autonomy" {
    run te_decide "1.0" "critical"
    assert_success
    assert_output "blocked"
}

@test "te_decide returns blocked for critical with autonomy=0.85" {
    run te_decide "0.85" "critical"
    assert_success
    assert_output "blocked"
}

@test "te_decide returns auto_approved when autonomy > 0.8 and risk != critical" {
    run te_decide "0.85" "low"
    assert_success
    assert_output "auto_approved"
}

@test "te_decide returns logged_only when 0.4 <= autonomy <= 0.8" {
    run te_decide "0.6" "medium"
    assert_success
    assert_output "logged_only"
}

@test "te_decide returns logged_only at boundary autonomy=0.4" {
    run te_decide "0.4" "medium"
    assert_success
    assert_output "logged_only"
}

@test "te_decide returns logged_only at boundary autonomy=0.8" {
    run te_decide "0.8" "medium"
    assert_success
    assert_output "logged_only"
}

@test "te_decide returns human_required when autonomy < 0.4" {
    run te_decide "0.3" "high"
    assert_success
    assert_output "human_required"
}

# ============================================================
# Task 2-4: te_record_success
# ============================================================

# Helper: get score from trust-scores.json
get_score() {
    local domain="$1"
    jq -r --arg d "${domain}" '.domains[$d].score' "${TRUST_SCORES_FILE}"
}

get_field() {
    local domain="$1" field="$2"
    jq -r --arg d "${domain}" --arg f "${field}" '.domains[$d][$f]' "${TRUST_SCORES_FILE}"
}

@test "te_record_success increases score from 0.3 with initial boost rate" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_success "_global"
    local score
    score="$(get_score "_global")"
    # score = 0.3 + (1-0.3)*0.05 = 0.3 + 0.035 = 0.335
    assert_equal "${score}" "0.335"
}

@test "te_record_success increments successes and total_operations" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_success "_global"
    assert_equal "$(get_field "_global" "successes")" "1"
    assert_equal "$(get_field "_global" "total_operations")" "1"
}

@test "te_record_success uses warmup rate (2x) when is_warming_up=true" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":5,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":true,"warmup_remaining":3}}
    }'
    te_record_success "_global"
    local score
    score="$(get_score "_global")"
    # total_ops=5 (<=20, initial boost period), warming_up=true → rate=0.10
    # score = 0.3 + (1-0.3)*0.10 = 0.3 + 0.07 = 0.37
    assert_equal "${score}" "0.37"
}

@test "te_record_success decrements warmup_remaining" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":5,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":true,"warmup_remaining":1}}
    }'
    te_record_success "_global"
    # warmup_remaining was 1, now 0 → is_warming_up should be false
    assert_equal "$(get_field "_global" "warmup_remaining")" "0"
    assert_equal "$(get_field "_global" "is_warming_up")" "false"
}

@test "te_record_success uses normal rate after boost threshold" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.5,"successes":20,"failures":0,"total_operations":21,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_success "_global"
    local score
    score="$(get_score "_global")"
    # total_ops=21 (>20), warming_up=false → rate=0.02
    # score = 0.5 + (1-0.5)*0.02 = 0.5 + 0.01 = 0.51
    assert_equal "${score}" "0.51"
}

@test "te_record_success creates domain if not exists" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.3,"successes":0,"failures":0,"total_operations":0,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_success "file_read"
    local score
    score="$(get_score "file_read")"
    # New domain starts at initial_score=0.3, then +boost: 0.3 + 0.7*0.05 = 0.335
    assert_equal "${score}" "0.335"
}

# ============================================================
# Task 2-5: te_record_failure / te_apply_time_decay
# ============================================================

@test "te_record_failure reduces score by 15%" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.5,"successes":5,"failures":0,"total_operations":5,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_failure "_global"
    local score
    score="$(get_score "_global")"
    # score = 0.5 * 0.85 = 0.425
    assert_equal "${score}" "0.425"
}

@test "te_record_failure increments failures count" {
    create_trust_scores '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{"score":0.5,"successes":5,"failures":0,"total_operations":5,
        "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0}}
    }'
    te_record_failure "_global"
    assert_equal "$(get_field "_global" "failures")" "1"
}

@test "te_apply_time_decay does not change score within hibernation_days" {
    # last_operated 13 days ago (within 14-day hibernation)
    local past_date
    past_date="$(date -u -d '13 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-13d '+%Y-%m-%dT%H:%M:%SZ')"
    create_trust_scores "{
        \"version\":\"2\",\"updated_at\":\"2026-01-01T00:00:00Z\",\"global_operation_count\":10,
        \"domains\":{\"_global\":{\"score\":0.5,\"successes\":10,\"failures\":0,\"total_operations\":10,
        \"last_operated_at\":\"${past_date}\",\"is_warming_up\":false,\"warmup_remaining\":0}}
    }"
    te_apply_time_decay
    local score
    score="$(get_score "_global")"
    assert_equal "${score}" "0.5"
}

@test "te_apply_time_decay applies decay after hibernation_days" {
    # last_operated 15 days ago (1 day past hibernation)
    local past_date
    past_date="$(date -u -d '15 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-15d '+%Y-%m-%dT%H:%M:%SZ')"
    create_trust_scores "{
        \"version\":\"2\",\"updated_at\":\"2026-01-01T00:00:00Z\",\"global_operation_count\":10,
        \"domains\":{\"_global\":{\"score\":0.5,\"successes\":10,\"failures\":0,\"total_operations\":10,
        \"last_operated_at\":\"${past_date}\",\"is_warming_up\":false,\"warmup_remaining\":0}}
    }"
    te_apply_time_decay
    local score
    score="$(get_score "_global")"
    # score = 0.5 * 0.999^1 = 0.4995
    assert_equal "${score}" "0.4995"
}

@test "te_apply_time_decay sets warmup flags on hibernated domain" {
    local past_date
    past_date="$(date -u -d '15 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-15d '+%Y-%m-%dT%H:%M:%SZ')"
    create_trust_scores "{
        \"version\":\"2\",\"updated_at\":\"2026-01-01T00:00:00Z\",\"global_operation_count\":10,
        \"domains\":{\"_global\":{\"score\":0.5,\"successes\":10,\"failures\":0,\"total_operations\":10,
        \"last_operated_at\":\"${past_date}\",\"is_warming_up\":false,\"warmup_remaining\":0}}
    }"
    te_apply_time_decay
    assert_equal "$(get_field "_global" "is_warming_up")" "true"
    assert_equal "$(get_field "_global" "warmup_remaining")" "5"
}

@test "te_apply_time_decay handles multiple domains in single call" {
    local stale_date recent_date
    stale_date="$(date -u -d '20 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-20d '+%Y-%m-%dT%H:%M:%SZ')"
    recent_date="$(date -u -d '5 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-5d '+%Y-%m-%dT%H:%M:%SZ')"
    create_trust_scores "{
        \"version\":\"2\",\"updated_at\":\"2026-01-01T00:00:00Z\",\"global_operation_count\":20,
        \"domains\":{
            \"_global\":{\"score\":0.5,\"successes\":10,\"failures\":0,\"total_operations\":10,
            \"last_operated_at\":\"${stale_date}\",\"is_warming_up\":false,\"warmup_remaining\":0},
            \"file_read\":{\"score\":0.8,\"successes\":10,\"failures\":0,\"total_operations\":10,
            \"last_operated_at\":\"${recent_date}\",\"is_warming_up\":false,\"warmup_remaining\":0},
            \"shell_exec\":{\"score\":0.6,\"successes\":5,\"failures\":1,\"total_operations\":6,
            \"last_operated_at\":\"${stale_date}\",\"is_warming_up\":false,\"warmup_remaining\":0}
        }
    }"
    te_apply_time_decay

    # _global: 20 days ago, 6 decay days → score = 0.5 * 0.999^6 ≈ 0.497
    local global_score
    global_score="$(get_score "_global")"
    # 0.5 * 0.999^6 = 0.5 * 0.994015 = 0.497007... → round to 0.497
    assert_equal "${global_score}" "0.497"
    assert_equal "$(get_field "_global" "is_warming_up")" "true"

    # file_read: 5 days ago (within 14d) → unchanged
    assert_equal "$(get_score "file_read")" "0.8"
    assert_equal "$(get_field "file_read" "is_warming_up")" "false"

    # shell_exec: 20 days ago, 6 decay days → score = 0.6 * 0.999^6 ≈ 0.5964
    local shell_score
    shell_score="$(get_score "shell_exec")"
    assert_equal "${shell_score}" "0.5964"
    assert_equal "$(get_field "shell_exec" "is_warming_up")" "true"
}
