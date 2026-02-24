#!/bin/bash
# oath-harness test helpers
# Common utilities for bats tests

# Get project root from test file location
_helpers_project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

HELPERS_PROJECT_ROOT="$(_helpers_project_root)"

# ---------------------------------------------------------------------------
# setup_test_env
# Create an isolated test environment with temp directories
# Sets all OATH env vars to point to the temp directory
# Usage: call from bats setup()
# ---------------------------------------------------------------------------
setup_test_env() {
    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${HELPERS_PROJECT_ROOT}"
    export CONFIG_DIR="${TEST_TMP}/config"
    export SETTINGS_FILE="${TEST_TMP}/config/settings.json"
    export STATE_DIR="${TEST_TMP}"
    export TRUST_SCORES_FILE="${TEST_TMP}/trust-scores.json"
    export AUDIT_DIR="${TEST_TMP}/audit"
    export OATH_PHASE_FILE="${TEST_TMP}/current-phase.md"

    # Create test settings with default values (isolated from production config)
    mkdir -p "${TEST_TMP}/config"
    create_test_settings

    echo "BUILDING" > "${OATH_PHASE_FILE}"

    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
    # Reset config cache to prevent cross-test contamination (CI-8)
    _OATH_CONFIG=""
}

# ---------------------------------------------------------------------------
# create_test_settings
# Create a settings.json with all default values in the test temp directory
# This ensures tests are isolated from production config/settings.json
# Usage: called automatically by setup_test_env, or manually in test setup
# ---------------------------------------------------------------------------
create_test_settings() {
    local dest="${SETTINGS_FILE:-${TEST_TMP}/config/settings.json}"
    mkdir -p "$(dirname "${dest}")"
    cat > "${dest}" <<'SETTINGS_EOF'
{
  "trust": {
    "hibernation_days": 14,
    "boost_threshold": 20,
    "initial_score": 0.3,
    "warmup_operations": 5,
    "failure_decay": 0.85
  },
  "risk": {
    "lambda1": 0.6,
    "lambda2": 0.4
  },
  "autonomy": {
    "auto_approve_threshold": 0.8,
    "human_required_threshold": 0.4
  },
  "audit": {
    "log_dir": "audit"
  },
  "model": {
    "opus_aot_threshold": 2
  }
}
SETTINGS_EOF
}

# ---------------------------------------------------------------------------
# teardown_test_env
# Clean up the test environment
# Usage: call from bats teardown()
# ---------------------------------------------------------------------------
teardown_test_env() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
    unset OATH_HARNESS_INITIALIZED
    unset OATH_HARNESS_SESSION_ID
}

# ---------------------------------------------------------------------------
# use_fixture
# Copy a fixture file to the test temp directory
# Usage: use_fixture "trust-scores-v2.json" "${TRUST_SCORES_FILE}"
# ---------------------------------------------------------------------------
use_fixture() {
    local fixture_name="$1"
    local dest="$2"
    local fixture_path="${HELPERS_PROJECT_ROOT}/tests/fixtures/${fixture_name}"

    if [[ ! -f "${fixture_path}" ]]; then
        echo "Fixture not found: ${fixture_path}" >&2
        return 1
    fi

    mkdir -p "$(dirname "${dest}")"
    cp "${fixture_path}" "${dest}"
}

# ---------------------------------------------------------------------------
# create_trust_scores
# Create a trust-scores.json with a specific global score
# Usage: create_trust_scores 0.5
# ---------------------------------------------------------------------------
create_trust_scores() {
    local score="${1:-0.3}"
    mkdir -p "$(dirname "${TRUST_SCORES_FILE}")"
    cat > "${TRUST_SCORES_FILE}" <<EOF
{
  "version": "2",
  "updated_at": "2026-01-01T00:00:00Z",
  "global_operation_count": 0,
  "domains": {
    "_global": {
      "score": ${score},
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-01-01T00:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
EOF
}

# ---------------------------------------------------------------------------
# get_audit_file
# Get today's audit file path
# ---------------------------------------------------------------------------
get_audit_file() {
    local today
    today="$(date -u '+%Y-%m-%d')"
    echo "${AUDIT_DIR}/${today}.jsonl"
}

# ---------------------------------------------------------------------------
# get_domain_score
# Get trust score for a domain from trust-scores.json
# Usage: score=$(get_domain_score "file_read")
# ---------------------------------------------------------------------------
get_domain_score() {
    local domain="$1"
    jq -r --arg d "${domain}" \
        '.domains[$d].score // .domains._global.score // 0.3' \
        "${TRUST_SCORES_FILE}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# assert_json_valid
# Assert that a file contains valid JSON
# Usage: assert_json_valid "${file_path}"
# ---------------------------------------------------------------------------
assert_json_valid() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        echo "File does not exist: ${file}" >&2
        return 1
    fi
    if ! jq '.' "${file}" > /dev/null 2>&1; then
        echo "Invalid JSON in: ${file}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_jsonl_valid
# Assert that a file contains valid JSONL (each line is valid JSON)
# Usage: assert_jsonl_valid "${audit_file}"
# ---------------------------------------------------------------------------
assert_jsonl_valid() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        echo "File does not exist: ${file}" >&2
        return 1
    fi
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if ! echo "${line}" | jq . > /dev/null 2>&1; then
            echo "Invalid JSON at line ${line_num} in: ${file}" >&2
            return 1
        fi
    done < "${file}"
}

# ---------------------------------------------------------------------------
# assert_score_increased
# Assert that a domain score has increased from initial value
# Usage: assert_score_increased "file_read" 0.3
# ---------------------------------------------------------------------------
assert_score_increased() {
    local domain="$1"
    local baseline="${2:-0.3}"
    local score
    score="$(get_domain_score "${domain}")"
    if ! awk -v s="${score}" -v b="${baseline}" 'BEGIN { exit !(s > b) }'; then
        echo "Score for ${domain} (${score}) did not increase from ${baseline}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_score_decreased
# Assert that a domain score has decreased from baseline
# Usage: assert_score_decreased "file_read" 0.3
# ---------------------------------------------------------------------------
assert_score_decreased() {
    local domain="$1"
    local baseline="${2:-0.3}"
    local score
    score="$(get_domain_score "${domain}")"
    if ! awk -v s="${score}" -v b="${baseline}" 'BEGIN { exit !(s < b) }'; then
        echo "Score for ${domain} (${score}) did not decrease from ${baseline}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# run_pre_hook
# Run pre-tool-use.sh with JSON input
# Usage: run_pre_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
# ---------------------------------------------------------------------------
run_pre_hook() {
    local json="$1"
    run bash "${HELPERS_PROJECT_ROOT}/hooks/pre-tool-use.sh" <<< "${json}"
}

# ---------------------------------------------------------------------------
# run_post_hook
# Run post-tool-use.sh with JSON input (env-passing for state persistence)
# Usage: run_post_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"is_error":false}'
# ---------------------------------------------------------------------------
run_post_hook() {
    local json="$1"
    echo "${json}" | \
        HARNESS_ROOT="${HELPERS_PROJECT_ROOT}" \
        STATE_DIR="${TEST_TMP}" \
        TRUST_SCORES_FILE="${TRUST_SCORES_FILE}" \
        AUDIT_DIR="${AUDIT_DIR}" \
        CONFIG_DIR="${CONFIG_DIR}" \
        SETTINGS_FILE="${SETTINGS_FILE}" \
        OATH_PHASE_FILE="${OATH_PHASE_FILE}" \
        bash "${HELPERS_PROJECT_ROOT}/hooks/post-tool-use.sh"
}

# ---------------------------------------------------------------------------
# run_stop_hook
# Run stop.sh
# ---------------------------------------------------------------------------
run_stop_hook() {
    HARNESS_ROOT="${HELPERS_PROJECT_ROOT}" \
    STATE_DIR="${TEST_TMP}" \
    TRUST_SCORES_FILE="${TRUST_SCORES_FILE}" \
    AUDIT_DIR="${AUDIT_DIR}" \
    CONFIG_DIR="${CONFIG_DIR}" \
    SETTINGS_FILE="${SETTINGS_FILE}" \
    OATH_PHASE_FILE="${OATH_PHASE_FILE}" \
    bash "${HELPERS_PROJECT_ROOT}/hooks/stop.sh"
}
