#!/usr/bin/env bats
# Integration tests: PostToolUseFailure - failure recovery flow
# AC-FR: 失敗→回復の統合フロー + 二重発火防止

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
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85,"recovery_boost_multiplier":1.5},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TESTCFG
    export STATE_DIR="${TEST_TMP}"
    export TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json"
    export AUDIT_DIR="${TEST_TMP}/audit"
    export OATH_PHASE_FILE="${TEST_TMP}/current-phase.md"

    echo "BUILDING" > "${OATH_PHASE_FILE}"

    # Create Claude settings fixture with PostToolUseFailure hook registered
    # (simulates normal installed state for delegation/double-fire tests)
    mkdir -p "${TEST_TMP}/.claude"
    cat > "${TEST_TMP}/.claude/settings.json" <<'HOOKSCFG'
{"hooks":{"PostToolUseFailure":[{"matcher":"","hooks":[{"type":"command","command":"hooks/post-tool-use-failure.sh"}]}]}}
HOOKSCFG
    export OATH_CLAUDE_SETTINGS="${TEST_TMP}/.claude/settings.json"

    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# Helper: run post-tool-use.sh (success/failure routing by is_error field)
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
        OATH_CLAUDE_SETTINGS="${OATH_CLAUDE_SETTINGS:-}" \
        bash "${PROJECT_ROOT}/hooks/post-tool-use.sh"
}

# Helper: run post-tool-use-failure.sh (explicit failure hook)
run_post_failure() {
    local json="$1"
    echo "${json}" | \
        HARNESS_ROOT="${PROJECT_ROOT}" \
        STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json" \
        AUDIT_DIR="${TEST_TMP}/audit" \
        CONFIG_DIR="${TEST_TMP}/config" \
        SETTINGS_FILE="${TEST_TMP}/config/settings.json" \
        OATH_PHASE_FILE="${TEST_TMP}/current-phase.md" \
        bash "${PROJECT_ROOT}/hooks/post-tool-use-failure.sh"
}

# Helper: get trust score for a domain
get_score() {
    local domain="$1"
    jq -r --arg d "${domain}" '.domains[$d].score // .domains._global.score // 0.3' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# Helper: get domain field value from trust-scores.json
get_domain_field() {
    local domain="$1"
    local field="$2"
    jq -r --arg d "${domain}" --arg f "${field}" '.domains[$d][$f]' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# Helper: get today's audit file path
audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${TEST_TMP}/audit/${today}.jsonl"
}

# ============================================================
# AC-FR-1: 二重発火防止 - PostToolUse(failure) + PostToolUseFailure で
#          スコアが一度だけ減衰する
# ============================================================

@test "double-fire prevention: PostToolUse(failure) + PostToolUseFailure -> score decays only once" {
    # Simulate double-fire: PostToolUse(is_error=true) fires first (audit only)
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

    local score_after_post
    score_after_post="$(get_score "file_read")"

    # Score should NOT have decayed after PostToolUse (delegated to PostToolUseFailure)
    awk -v s="${score_after_post}" 'BEGIN {
        diff = s - 0.3
        if (diff < 0) diff = -diff
        exit !(diff < 0.001)
    }'

    # Then PostToolUseFailure fires (actual score decay)
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local score_after_failure
    score_after_failure="$(get_score "file_read")"

    # Score should have decayed exactly once: 0.3 * 0.85 = 0.255
    awk -v s="${score_after_failure}" 'BEGIN {
        diff = s - 0.255
        if (diff < 0) diff = -diff
        exit !(diff < 0.001)
    }'
}

@test "double-fire prevention: PostToolUse(failure) audit outcome=failure recorded" {
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local outcome
    outcome="$(jq -r '.outcome' "${log}")"
    [ "${outcome}" = "failure" ]
}

# ============================================================
# AC-FR-2: 失敗→回復の統合フロー
#          PostToolUseFailure でスコア減衰 → PostToolUse(success) で回復ブースト
# ============================================================

@test "failure recovery flow: PostToolUseFailure decay -> PostToolUse success -> score recovers" {
    # Step 1: failure (via PostToolUseFailure)
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local score_after_failure
    score_after_failure="$(get_score "file_read")"
    # Score should have decayed: 0.3 * 0.85 = 0.255
    awk -v s="${score_after_failure}" 'BEGIN { exit !(s < 0.3) }'

    # Step 2: success (via PostToolUse) - should apply recovery boost
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local score_after_success
    score_after_success="$(get_score "file_read")"
    # Score should have increased from failure score
    awk -v s="${score_after_success}" -v f="${score_after_failure}" 'BEGIN { exit !(s > f) }'
}

@test "failure recovery flow: is_recovering becomes true after failure" {
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local recovering
    recovering="$(get_domain_field "file_read" "is_recovering")"
    [ "${recovering}" = "true" ]
}

@test "failure recovery flow: pre_failure_score recorded on first failure" {
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local pfs
    pfs="$(get_domain_field "file_read" "pre_failure_score")"
    [ "${pfs}" != "null" ]
    awk -v s="${pfs}" 'BEGIN {
        diff = s - 0.3
        if (diff < 0) diff = -diff
        exit !(diff < 0.001)
    }'
}

# ============================================================
# AC-FR-3: 連続失敗→成功のシーケンス: consecutive_failures の推移
# ============================================================

@test "consecutive failures: two failures increment consecutive_failures to 2" {
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local cf
    cf="$(get_domain_field "file_read" "consecutive_failures")"
    [ "${cf}" = "2" ]
}

@test "consecutive failures then success: consecutive_failures resets to 0" {
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local cf_before
    cf_before="$(get_domain_field "file_read" "consecutive_failures")"
    [ "${cf_before}" = "2" ]

    # Success via PostToolUse resets consecutive_failures
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local cf_after
    cf_after="$(get_domain_field "file_read" "consecutive_failures")"
    [ "${cf_after}" = "0" ]
}

# ============================================================
# AC-FR-4: 回復完了: score >= pre_failure_score で is_recovering=false
# ============================================================

@test "recovery completion: is_recovering=false when score >= pre_failure_score" {
    # Start with elevated score by doing multiple successes first
    # This creates a higher pre_failure_score
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local score_pre_failure
    score_pre_failure="$(get_score "file_read")"

    # Trigger failure (records pre_failure_score = score_pre_failure)
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local recovering
    recovering="$(get_domain_field "file_read" "is_recovering")"
    [ "${recovering}" = "true" ]

    # Keep running successes until recovery completes
    # With recovery_boost_multiplier=1.5 and rate=0.05, each success boosts more
    # Recovery completes when score >= pre_failure_score
    local i=0
    while [ "${i}" -lt 20 ]; do
        run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
        local current_score
        current_score="$(get_score "file_read")"
        local still_recovering
        still_recovering="$(get_domain_field "file_read" "is_recovering")"
        if [ "${still_recovering}" = "false" ]; then
            break
        fi
        i=$((i + 1))
    done

    local final_recovering
    final_recovering="$(get_domain_field "file_read" "is_recovering")"
    [ "${final_recovering}" = "false" ]

    local final_score
    final_score="$(get_score "file_read")"
    awk -v s="${final_score}" -v p="${score_pre_failure}" 'BEGIN { exit !(s >= p) }'
}

# ============================================================
# AC-FR-5: warmup + recovery 同時発動シナリオ
# ============================================================

@test "warmup + recovery simultaneous: score boosts faster than normal" {
    # The initial score is 0.3, warmup_operations=5
    # First operation enters warmup mode, rate becomes 0.05*2=0.10
    # After failure + recovery: rate becomes 0.10 * 1.5 = 0.15

    # Trigger failure immediately (domain is in warmup mode for first 5 ops)
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    # Should be in recovering state
    local recovering
    recovering="$(get_domain_field "file_read" "is_recovering")"
    [ "${recovering}" = "true" ]

    local score_after_failure
    score_after_failure="$(get_score "file_read")"

    # Success: should apply warmup boost AND recovery boost
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'

    local score_after_success
    score_after_success="$(get_score "file_read")"

    # Score should increase from the failure score
    awk -v s="${score_after_success}" -v f="${score_after_failure}" 'BEGIN { exit !(s > f) }'
}

# ============================================================
# AC-FR-6: PostToolUse(failure) では audit エントリが書かれ、
#          trust_score_after は null である
# ============================================================

@test "PostToolUse failure path: audit entry has trust_score_after=null" {
    run_post '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"},"is_error":true}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local trust_score_after
    trust_score_after="$(jq -r '.trust_score_after' "${log}")"
    [ "${trust_score_after}" = "null" ]
}

@test "PostToolUseFailure path: audit entry has trust_score_after as numeric" {
    run_post_failure '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local trust_score_after
    trust_score_after="$(jq -r '.trust_score_after' "${log}")"
    [ "${trust_score_after}" != "null" ]
    awk -v v="${trust_score_after}" 'BEGIN { exit !(v+0 == v) }'
}

# ============================================================
# AC-FR-7: 二重発火後の audit ログの整合性
# ============================================================

@test "double-fire: two audit entries written (one per hook)" {
    # PostToolUse(failure) writes one audit entry
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'
    # PostToolUseFailure writes another audit entry
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]
    local count
    count="$(wc -l < "${log}")"
    [ "${count}" -eq 2 ]
}

@test "double-fire: all audit entries are valid JSONL" {
    run_post '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":true}'
    run_post_failure '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    local log
    log="$(audit_file)"
    [ -f "${log}" ]

    local invalid=0
    while IFS= read -r line; do
        if ! echo "${line}" | jq . > /dev/null 2>&1; then
            invalid=$((invalid + 1))
        fi
    done < "${log}"
    [ "${invalid}" -eq 0 ]
}
