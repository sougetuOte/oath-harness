#!/usr/bin/env bats
# Unit tests for hooks/stop.sh
# AC-013

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
    export AUDIT_DIR="${TEST_TMP}/audit"
    export OATH_PHASE_FILE="${TEST_TMP}/current-phase.md"

    echo "BUILDING" > "${OATH_PHASE_FILE}"

    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# Helper: create a trust-scores.json with a known state
create_trust_scores() {
    cat > "${TRUST_SCORES_FILE}" << 'EOF'
{
    "version": "2",
    "updated_at": "2026-01-01T00:00:00Z",
    "global_operation_count": 5,
    "domains": {
        "_global": {
            "score": 0.45,
            "successes": 5,
            "failures": 0,
            "total_operations": 5,
            "last_operated_at": "2026-01-01T00:00:00Z",
            "is_warming_up": false,
            "warmup_remaining": 0
        }
    }
}
EOF
}

# Helper: run stop.sh without stdin (Stop hook receives no stdin)
run_stop_hook() {
    run env \
        HARNESS_ROOT="${PROJECT_ROOT}" \
        STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json" \
        AUDIT_DIR="${TEST_TMP}/audit" \
        CONFIG_DIR="${PROJECT_ROOT}/config" \
        SETTINGS_FILE="${PROJECT_ROOT}/config/settings.json" \
        OATH_PHASE_FILE="${TEST_TMP}/current-phase.md" \
        bash "${PROJECT_ROOT}/hooks/stop.sh"
}

# ============================================================
# AC-013-1: trust-scores.json の updated_at が更新される
# ============================================================

@test "stop hook updates updated_at in trust-scores.json" {
    create_trust_scores
    local before="2026-01-01T00:00:00Z"

    run_stop_hook
    assert_success

    local after
    after="$(jq -r '.updated_at' "${TRUST_SCORES_FILE}")"
    [ "${after}" != "${before}" ]
}

# ============================================================
# AC-013-2: updated_at が ISO 8601 形式の現在時刻に近い
# ============================================================

@test "stop hook sets updated_at to a valid ISO 8601 timestamp" {
    create_trust_scores

    run_stop_hook
    assert_success

    local updated_at
    updated_at="$(jq -r '.updated_at' "${TRUST_SCORES_FILE}")"
    # Must match ISO 8601 pattern: YYYY-MM-DDTHH:MM:SSZ
    [[ "${updated_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "stop hook sets updated_at to a timestamp close to current time" {
    create_trust_scores

    local before_epoch
    before_epoch="$(date -u '+%s')"

    run_stop_hook
    assert_success

    local updated_at
    updated_at="$(jq -r '.updated_at' "${TRUST_SCORES_FILE}")"
    local after_epoch
    after_epoch="$(date -u -d "${updated_at}" '+%s' 2>/dev/null)"

    local now_epoch
    now_epoch="$(date -u '+%s')"

    # updated_at must be within 10 seconds of current time
    [ "${after_epoch}" -ge "${before_epoch}" ]
    [ "${after_epoch}" -le "$(( now_epoch + 1 ))" ]
}

# ============================================================
# AC-013-3: trust-scores.json が存在しない場合も exit 0
# ============================================================

@test "stop hook exits 0 when trust-scores.json does not exist" {
    # Ensure no trust-scores.json
    rm -f "${TRUST_SCORES_FILE}"

    run_stop_hook
    assert_success
}

@test "stop hook does not create trust-scores.json when it does not exist" {
    rm -f "${TRUST_SCORES_FILE}"

    run_stop_hook
    assert_success

    [ ! -f "${TRUST_SCORES_FILE}" ]
}

# ============================================================
# AC-013-4: score など updated_at 以外は変更されない
# ============================================================

@test "stop hook does not change score in trust-scores.json" {
    create_trust_scores

    run_stop_hook
    assert_success

    local score
    score="$(jq -r '.domains._global.score' "${TRUST_SCORES_FILE}")"
    assert_equal "${score}" "0.45"
}

@test "stop hook does not change global_operation_count" {
    create_trust_scores

    run_stop_hook
    assert_success

    local count
    count="$(jq -r '.global_operation_count' "${TRUST_SCORES_FILE}")"
    assert_equal "${count}" "5"
}

@test "stop hook does not change version field" {
    create_trust_scores

    run_stop_hook
    assert_success

    local version
    version="$(jq -r '.version' "${TRUST_SCORES_FILE}")"
    assert_equal "${version}" "2"
}

# ============================================================
# AC-013-5: atl_flush が呼ばれる（エラーなく完了）
# ============================================================

@test "stop hook completes successfully (atl_flush no-op)" {
    create_trust_scores

    run_stop_hook
    assert_success
}

# ============================================================
# AC-013-6: エラー（jq 失敗等）でも exit 0
# ============================================================

@test "stop hook exits 0 even when trust-scores.json is corrupted" {
    echo "not valid json" > "${TRUST_SCORES_FILE}"

    run_stop_hook
    assert_success
}

@test "stop hook exits 0 when AUDIT_DIR is not writable" {
    create_trust_scores
    mkdir -p "${AUDIT_DIR}"
    chmod 000 "${AUDIT_DIR}"

    run_stop_hook
    assert_success

    chmod 755 "${AUDIT_DIR}"
}
