#!/usr/bin/env bats
# Unit tests for lib/audit.sh
# AC-020〜AC-023: Audit Trail Logger

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
    export AUDIT_DIR="${TEST_TMP}/audit"

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/audit.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# ============================================================
# AC-020: ツール呼び出し1回でログ1エントリ追記される
# ============================================================

@test "atl_append_pre writes one JSONL line to today's audit file" {
    local session_id="test-session-001"
    local tool_name="Bash"
    local tool_input='{"command":"ls -la"}'
    local domain="file_read"
    local risk_category="low"
    local trust_score_before="0.45"
    local autonomy_score="0.82"
    local decision="auto_approved"

    run atl_append_pre \
        "${session_id}" "${tool_name}" "${tool_input}" \
        "${domain}" "${risk_category}" \
        "${trust_score_before}" "${autonomy_score}" "${decision}"

    assert_success

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    [ -f "${log_file}" ]
    local line_count
    line_count="$(wc -l < "${log_file}")"
    [ "${line_count}" -eq 1 ]
}

# ============================================================
# AC-020: 全フィールド (B-1-3) が記録されている
# ============================================================

@test "atl_append_pre entry contains all required B-1-3 fields" {
    local session_id="test-session-002"
    local tool_name="Read"
    local tool_input='{"file_path":"/tmp/test.txt"}'
    local domain="file_read"
    local risk_category="low"
    local trust_score_before="0.5"
    local autonomy_score="0.75"
    local decision="logged_only"

    atl_append_pre \
        "${session_id}" "${tool_name}" "${tool_input}" \
        "${domain}" "${risk_category}" \
        "${trust_score_before}" "${autonomy_score}" "${decision}"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    # 全フィールドが存在するか確認
    local entry
    entry="$(tail -1 "${log_file}")"

    # jq で各フィールドを確認
    [ "$(echo "${entry}" | jq -r '.session_id')" = "${session_id}" ]
    [ "$(echo "${entry}" | jq -r '.tool_name')" = "${tool_name}" ]
    [ "$(echo "${entry}" | jq -r '.domain')" = "${domain}" ]
    [ "$(echo "${entry}" | jq -r '.risk_category')" = "${risk_category}" ]
    [ "$(echo "${entry}" | jq -r '.trust_score_before')" = "${trust_score_before}" ]
    [ "$(echo "${entry}" | jq -r '.autonomy_score')" = "${autonomy_score}" ]
    [ "$(echo "${entry}" | jq -r '.decision')" = "${decision}" ]
    [ "$(echo "${entry}" | jq -r '.outcome')" = "pending" ]
    [ "$(echo "${entry}" | jq -r '.trust_score_after')" = "null" ]
    # timestamp は ISO 8601 形式
    [[ "$(echo "${entry}" | jq -r '.timestamp')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ============================================================
# DW-2/DW-5: recommended_model と phase が記録される
# ============================================================

@test "atl_append_pre records recommended_model and phase fields" {
    atl_append_pre \
        "sess-model" "Bash" '{"command":"ls"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved" \
        "sonnet" "building"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    [ "$(echo "${entry}" | jq -r '.recommended_model')" = "sonnet" ]
    [ "$(echo "${entry}" | jq -r '.phase')" = "building" ]
}

@test "atl_append_pre defaults recommended_model and phase to unknown" {
    atl_append_pre \
        "sess-default" "Read" '{"file_path":"/tmp/x"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    [ "$(echo "${entry}" | jq -r '.recommended_model')" = "unknown" ]
    [ "$(echo "${entry}" | jq -r '.phase')" = "unknown" ]
}

@test "atl_append_pre entry has tool_input as JSON object" {
    local session_id="test-session-003"
    local tool_input='{"command":"echo hello"}'

    atl_append_pre \
        "${session_id}" "Bash" "${tool_input}" \
        "file_read" "low" "0.5" "0.75" "auto_approved"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    local entry
    entry="$(tail -1 "${log_file}")"

    # tool_input は JSON オブジェクトであること
    local ti_type
    ti_type="$(echo "${entry}" | jq -r '.tool_input | type')"
    [ "${ti_type}" = "object" ]
}

# ============================================================
# AC-020: outcome は常に "pending"、trust_score_after は null
# ============================================================

@test "atl_append_pre sets outcome=pending and trust_score_after=null" {
    atl_append_pre \
        "session-004" "Bash" '{"command":"pwd"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    [ "$(echo "${entry}" | jq -r '.outcome')" = "pending" ]
    [ "$(echo "${entry}" | jq '.trust_score_after')" = "null" ]
}

# ============================================================
# AC-021: 複数エントリは同一ファイルに追記される
# ============================================================

@test "atl_append_pre appends multiple entries to the same file" {
    atl_append_pre "sess-a" "Bash" '{"command":"ls"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved"
    atl_append_pre "sess-b" "Read" '{"file_path":"/tmp/x"}' \
        "file_read" "low" "0.6" "0.80" "auto_approved"
    atl_append_pre "sess-c" "Write" '{"file_path":"/tmp/y","content":"hi"}' \
        "file_write" "medium" "0.4" "0.60" "logged_only"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    local line_count
    line_count="$(wc -l < "${log_file}")"
    [ "${line_count}" -eq 3 ]
}

# ============================================================
# AC-022: valid JSONL である
# ============================================================

@test "atl_append_pre produces valid JSONL (each line is valid JSON)" {
    atl_append_pre "sess-valid" "Bash" '{"command":"date"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved"
    atl_append_pre "sess-valid2" "Read" '{"file_path":"/etc/hosts"}' \
        "file_read" "low" "0.6" "0.80" "logged_only"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    # 各行が valid JSON であることを確認
    local invalid_count=0
    while IFS= read -r line; do
        if ! echo "${line}" | jq . >/dev/null 2>&1; then
            invalid_count=$((invalid_count + 1))
        fi
    done < "${log_file}"

    [ "${invalid_count}" -eq 0 ]
}

# ============================================================
# AC-022: atl_update_outcome で outcome エントリが追記される
# ============================================================

@test "atl_update_outcome appends a new outcome entry" {
    # まず pre エントリを追記
    atl_append_pre "sess-upd" "Bash" '{"command":"ls"}' \
        "file_read" "low" "0.45" "0.82" "auto_approved"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    local before_count
    before_count="$(wc -l < "${log_file}")"

    # outcome を追記
    run atl_update_outcome "sess-upd" "Bash" "success" "0.457"
    assert_success

    local after_count
    after_count="$(wc -l < "${log_file}")"

    # 新しい行が追記されていること
    [ "${after_count}" -eq $((before_count + 1)) ]
}

@test "atl_update_outcome entry contains correct outcome and trust_score_after" {
    atl_append_pre "sess-upd2" "Read" '{"file_path":"/tmp/test"}' \
        "file_read" "low" "0.5" "0.75" "logged_only"

    atl_update_outcome "sess-upd2" "Read" "success" "0.51"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    [ "$(echo "${entry}" | jq -r '.session_id')" = "sess-upd2" ]
    [ "$(echo "${entry}" | jq -r '.tool_name')" = "Read" ]
    [ "$(echo "${entry}" | jq -r '.outcome')" = "success" ]
    [ "$(echo "${entry}" | jq -r '.trust_score_after')" = "0.51" ]
    # timestamp が存在する
    [[ "$(echo "${entry}" | jq -r '.timestamp')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "atl_update_outcome with failure outcome" {
    atl_append_pre "sess-fail" "Bash" '{"command":"rm -rf /"}' \
        "file_write" "critical" "0.3" "0.20" "blocked"

    atl_update_outcome "sess-fail" "Bash" "failure" "0.255"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    [ "$(echo "${entry}" | jq -r '.outcome')" = "failure" ]
    [ "$(echo "${entry}" | jq -r '.trust_score_after')" = "0.255" ]
}

# ============================================================
# AC-023: センシティブ値がマスクされる
# ============================================================

@test "_atl_mask_sensitive masks API_KEY in key name" {
    local input='{"API_KEY":"abc123","command":"ls"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    # API_KEY の値がマスクされている
    [[ "${output}" == *'"*****"'* ]]
    # command の値はそのまま
    [[ "${output}" == *'"ls"'* ]]
}

@test "_atl_mask_sensitive masks SECRET in key name" {
    local input='{"SECRET":"my-secret-value","other":"normal"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"*****"'* ]]
    [[ "${output}" == *'"normal"'* ]]
}

@test "_atl_mask_sensitive masks TOKEN in key name" {
    local input='{"TOKEN":"bearer-xyz","user":"alice"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"*****"'* ]]
    [[ "${output}" == *'"alice"'* ]]
}

@test "_atl_mask_sensitive masks PASSWORD in key name" {
    local input='{"PASSWORD":"s3cr3t","host":"localhost"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"*****"'* ]]
    [[ "${output}" == *'"localhost"'* ]]
}

@test "_atl_mask_sensitive masks PRIVATE_KEY in key name" {
    local input='{"PRIVATE_KEY":"-----BEGIN RSA-----","env":"prod"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"*****"'* ]]
    [[ "${output}" == *'"prod"'* ]]
}

@test "_atl_mask_sensitive masks ACCESS_KEY in key name" {
    local input='{"ACCESS_KEY":"AKIAIOSFODNN7EXAMPLE","region":"us-east-1"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"*****"'* ]]
    [[ "${output}" == *'"us-east-1"'* ]]
}

@test "_atl_mask_sensitive does not mask normal fields" {
    local input='{"command":"ls -la","file_path":"/tmp/test"}'
    run _atl_mask_sensitive "${input}"
    assert_success
    [[ "${output}" == *'"ls -la"'* ]]
    [[ "${output}" == *'"/tmp/test"'* ]]
}

@test "atl_append_pre masks sensitive values in tool_input" {
    local tool_input='{"API_KEY":"secret123","command":"curl https://api.example.com"}'

    atl_append_pre \
        "sess-mask" "Bash" "${tool_input}" \
        "network" "high" "0.5" "0.4" "human_required"

    local today
    today="$(date -u '+%Y-%m-%d')"
    local entry
    entry="$(tail -1 "${AUDIT_DIR}/${today}.jsonl")"

    # API_KEY の値はマスクされている
    local api_key_val
    api_key_val="$(echo "${entry}" | jq -r '.tool_input.API_KEY')"
    [ "${api_key_val}" = "*****" ]

    # command はそのまま
    local cmd_val
    cmd_val="$(echo "${entry}" | jq -r '.tool_input.command')"
    [ "${cmd_val}" = "curl https://api.example.com" ]
}

# ============================================================
# エラー処理: audit ディレクトリが存在しない場合
# ============================================================

@test "atl_append_pre creates audit directory if it does not exist" {
    # AUDIT_DIR はまだ存在しない
    [ ! -d "${AUDIT_DIR}" ]

    run atl_append_pre \
        "sess-mkdir" "Bash" '{"command":"pwd"}' \
        "file_read" "low" "0.5" "0.75" "auto_approved"

    assert_success
    [ -d "${AUDIT_DIR}" ]
}

# ============================================================
# エラー処理: 不正な JSON の tool_input
# ============================================================

@test "atl_append_pre handles invalid JSON tool_input with fallback" {
    local invalid_json="not-valid-json"

    run atl_append_pre \
        "sess-invalid" "Bash" "${invalid_json}" \
        "file_read" "low" "0.5" "0.75" "auto_approved"

    # エラーが記録失敗で処理を止めないこと（exit 0 または exit 1 は実装依存だが行は記録される）
    local today
    today="$(date -u '+%Y-%m-%d')"
    local log_file="${AUDIT_DIR}/${today}.jsonl"

    [ -f "${log_file}" ]
    local line_count
    line_count="$(wc -l < "${log_file}")"
    [ "${line_count}" -ge 1 ]

    # フォールバック行は valid JSON であること
    local last_line
    last_line="$(tail -1 "${log_file}")"
    echo "${last_line}" | jq . >/dev/null 2>&1
}

# ============================================================
# atl_flush: セッション終了時のフラッシュ
# ============================================================

@test "atl_flush completes without error" {
    run atl_flush
    assert_success
}
