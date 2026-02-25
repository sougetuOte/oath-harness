#!/usr/bin/env bats
# Unit tests for trust-update.jq recovery boost mechanism (Phase 2a)
# Tests call jq directly to verify filter behavior independent of trust-engine.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    JQ_FILTER="${PROJECT_ROOT}/lib/jq/trust-update.jq"
    TEST_TMP="$(mktemp -d)"
    TRUST_FILE="${TEST_TMP}/trust-scores.json"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# ---------------------------------------------------------------------------
# Helper: write a domain JSON to TRUST_FILE
# ---------------------------------------------------------------------------
write_trust() {
    local json="$1"
    printf '%s\n' "${json}" > "${TRUST_FILE}"
}

# Helper: run jq filter with standard args for success action
run_success() {
    local domain="${1:-_global}"
    local bt="${2:-20}"
    local rb="${3:-1.5}"
    run jq \
        --arg d "${domain}" \
        --arg action "success" \
        --argjson bt "${bt}" \
        --argjson fd 0 \
        --argjson rb "${rb}" \
        --arg now "2026-01-01T00:00:00Z" \
        -f "${JQ_FILTER}" "${TRUST_FILE}"
}

# Helper: run jq filter with standard args for failure action
run_failure() {
    local domain="${1:-_global}"
    local fd="${2:-0.85}"
    local rb="${3:-1.5}"
    run jq \
        --arg d "${domain}" \
        --arg action "failure" \
        --argjson bt 0 \
        --argjson fd "${fd}" \
        --argjson rb "${rb}" \
        --arg now "2026-01-01T00:00:00Z" \
        -f "${JQ_FILTER}" "${TRUST_FILE}"
}

# Helper: extract a field from jq output
get_field() {
    local output="$1"
    local domain="$2"
    local field="$3"
    printf '%s\n' "${output}" | jq -r --arg d "${domain}" --arg f "${field}" \
        '.domains[$d][$f]'
}

# ============================================================
# FR-DM-001: consecutive_failures フィールド追加
# ============================================================

@test "failure: consecutive_failures is incremented from 0 to 1 on first failure" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.6,"successes":25,"failures":0,"total_operations":25,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":null,"is_recovering":false
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    cf="$(get_field "${result}" "_global" "consecutive_failures")"
    assert_equal "${cf}" "1"
}

@test "failure: consecutive_failures increments from 1 to 2 on second failure" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    cf="$(get_field "${result}" "_global" "consecutive_failures")"
    assert_equal "${cf}" "2"
}

@test "success: consecutive_failures is reset to 0 after success" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_success "_global"
    assert_success
    result="$output"
    cf="$(get_field "${result}" "_global" "consecutive_failures")"
    assert_equal "${cf}" "0"
}

# ============================================================
# FR-DM-002: pre_failure_score 記録
# ============================================================

@test "failure: pre_failure_score is recorded on first failure (consecutive_failures==0, not recovering)" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.6,"successes":25,"failures":0,"total_operations":25,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":null,"is_recovering":false
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    pfs="$(get_field "${result}" "_global" "pre_failure_score")"
    assert_equal "${pfs}" "0.6"
}

@test "failure: pre_failure_score is NOT overwritten during recovery (consecutive_failures>0)" {
    # FR-RB-003: 回復中の再失敗では pre_failure_score を最初の値で維持
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    pfs="$(get_field "${result}" "_global" "pre_failure_score")"
    # pre_failure_score should remain 0.6 (not overwritten with current 0.51)
    assert_equal "${pfs}" "0.6"
}

# ============================================================
# FR-DM-003: is_recovering フラグ
# ============================================================

@test "failure: is_recovering is set to true on first failure" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.6,"successes":25,"failures":0,"total_operations":25,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":null,"is_recovering":false
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    ir="$(get_field "${result}" "_global" "is_recovering")"
    assert_equal "${ir}" "true"
}

@test "failure: is_recovering stays true on second failure" {
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    ir="$(get_field "${result}" "_global" "is_recovering")"
    assert_equal "${ir}" "true"
}

# ============================================================
# FR-RB-001: Recovery boost 発動
# ============================================================

@test "success: recovery boost applies 1.5x rate when is_recovering=true" {
    # score=0.51, total_ops=25 (>20, normal period), is_recovering=true
    # Without boost: rate = 0.02
    # With boost: final_rate = 0.02 * 1.5 = 0.03
    # new_score = 0.51 + (1 - 0.51) * 0.03 = 0.51 + 0.49 * 0.03 = 0.51 + 0.0147 = 0.5247
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    new_score="$(get_field "${result}" "_global" "score")"
    assert_equal "${new_score}" "0.5247"
}

@test "success: no boost when is_recovering=false (normal success)" {
    # score=0.51, total_ops=25 (>20, normal period), is_recovering=false
    # rate = 0.02
    # new_score = 0.51 + (1 - 0.51) * 0.02 = 0.51 + 0.0098 = 0.5198
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":0,"total_operations":25,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":null,"is_recovering":false
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    new_score="$(get_field "${result}" "_global" "score")"
    assert_equal "${new_score}" "0.5198"
}

# ============================================================
# FR-RB-002: Recovery completion
# ============================================================

@test "success: is_recovering set to false when new_score >= pre_failure_score" {
    # score=0.59, pre_failure_score=0.6, is_recovering=true
    # total_ops=26 (>20), rate=0.02, boost: 0.03
    # new_score = 0.59 + (1-0.59)*0.03 = 0.59 + 0.0123 = 0.6023 >= 0.6 -> recovery complete
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.59,"successes":26,"failures":1,"total_operations":27,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    ir="$(get_field "${result}" "_global" "is_recovering")"
    assert_equal "${ir}" "false"
}

@test "success: pre_failure_score set to null when recovery completes" {
    # Same scenario as above: new_score >= pre_failure_score -> pfs becomes null
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.59,"successes":26,"failures":1,"total_operations":27,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":0,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    pfs="$(get_field "${result}" "_global" "pre_failure_score")"
    assert_equal "${pfs}" "null"
}

@test "success: is_recovering stays true when new_score < pre_failure_score" {
    # score=0.51, pre_failure_score=0.6, is_recovering=true
    # new_score = 0.5247 (< 0.6) -> still recovering
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    ir="$(get_field "${result}" "_global" "is_recovering")"
    assert_equal "${ir}" "true"
}

# ============================================================
# FR-RB-005: warmup + recovery 同時発動
# ============================================================

@test "success: warmup and recovery boost both applied simultaneously" {
    # trust=0.30, total_ops=5 (<=20, boost period), is_warming_up=true, warmup_remaining=3
    # is_recovering=true, pre_failure_score=0.40
    # base_rate (warmup + initial boost): is_warming_up=true, ops<=20 -> 0.10
    # final_rate = 0.10 * 1.5 (recovery) = 0.15
    # new_score = 0.30 + (1 - 0.30) * 0.15 = 0.30 + 0.105 = 0.405
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.30,"successes":5,"failures":1,"total_operations":6,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":true,"warmup_remaining":3,
            "consecutive_failures":0,"pre_failure_score":0.40,"is_recovering":true
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    new_score="$(get_field "${result}" "_global" "score")"
    assert_equal "${new_score}" "0.405"
}

# ============================================================
# 後方互換性: Phase 1 形式（新フィールドなし）
# ============================================================

@test "backward compat: failure on Phase 1 format (no new fields) does not error" {
    # Phase 1 形式: consecutive_failures, pre_failure_score, is_recovering なし
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.5,"successes":10,"failures":0,"total_operations":10,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0
        }}
    }'
    run_failure "_global"
    assert_success
    result="$output"
    # Score should be decayed
    score="$(get_field "${result}" "_global" "score")"
    assert_equal "${score}" "0.425"
    # New fields should be initialized correctly
    cf="$(get_field "${result}" "_global" "consecutive_failures")"
    assert_equal "${cf}" "1"
    ir="$(get_field "${result}" "_global" "is_recovering")"
    assert_equal "${ir}" "true"
}

@test "backward compat: success on Phase 1 format (no new fields) does not error" {
    # Phase 1 形式: consecutive_failures, pre_failure_score, is_recovering なし
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.5,"successes":10,"failures":0,"total_operations":10,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0
        }}
    }'
    run_success "_global" "20" "1.5"
    assert_success
    result="$output"
    # Score should be updated without boost (is_recovering defaults to false)
    score="$(get_field "${result}" "_global" "score")"
    # total_ops=10 (<=20), is_warming_up=false -> rate=0.05
    # new_score = 0.5 + (1-0.5)*0.05 = 0.5 + 0.025 = 0.525
    assert_equal "${score}" "0.525"
    cf="$(get_field "${result}" "_global" "consecutive_failures")"
    assert_equal "${cf}" "0"
}

@test "backward compat: $rb parameter defaults gracefully (1.5 if not provided)" {
    # $rb は trust-update.jq 内で $rb // 1.5 として扱われるべき
    # ここでは rb を明示的に 1.5 として渡すが、フィルタ内の // 1.5 が機能することを確認
    write_trust '{
        "version":"2","updated_at":"2026-01-01T00:00:00Z","global_operation_count":0,
        "domains":{"_global":{
            "score":0.51,"successes":25,"failures":1,"total_operations":26,
            "last_operated_at":"2026-01-01T00:00:00Z","is_warming_up":false,"warmup_remaining":0,
            "consecutive_failures":1,"pre_failure_score":0.6,"is_recovering":true
        }}
    }'
    # $rb // 1.5 のフォールバックを検証するために rb=null 相当を渡す（実際は argjson null）
    run jq \
        --arg d "_global" \
        --arg action "success" \
        --argjson bt 20 \
        --argjson fd 0 \
        --argjson rb "null" \
        --arg now "2026-01-01T00:00:00Z" \
        -f "${JQ_FILTER}" "${TRUST_FILE}"
    assert_success
    result="$output"
    new_score="$(get_field "${result}" "_global" "score")"
    # rb=null -> $rb // 1.5 -> boost 1.5 applies
    # same as FR-RB-001 test: 0.5247
    assert_equal "${new_score}" "0.5247"
}
