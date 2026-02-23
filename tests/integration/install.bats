#!/usr/bin/env bats
# Integration tests: install.sh / uninstall.sh
# AC-031: Claude Code hooks registration

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    TEST_TMP="$(mktemp -d)"
    # Simulate a project directory
    TEST_PROJECT="${TEST_TMP}/test-project"
    mkdir -p "${TEST_PROJECT}"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# ============================================================
# install.sh: new project (no existing settings)
# ============================================================

@test "install.sh creates .claude/settings.json with hooks" {
    run bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}"
    assert_success

    local settings="${TEST_PROJECT}/.claude/settings.json"
    [ -f "${settings}" ]
}

@test "install.sh registers PreToolUse hook with absolute path" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    local pre_cmd
    pre_cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "${settings}")"

    # Must be an absolute path
    [[ "${pre_cmd}" == /* ]]
    # Must end with pre-tool-use.sh
    [[ "${pre_cmd}" == */hooks/pre-tool-use.sh ]]
}

@test "install.sh registers PostToolUse hook with absolute path" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    local post_cmd
    post_cmd="$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "${settings}")"

    [[ "${post_cmd}" == /* ]]
    [[ "${post_cmd}" == */hooks/post-tool-use.sh ]]
}

@test "install.sh registers Stop hook with absolute path" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    local stop_cmd
    stop_cmd="$(jq -r '.hooks.Stop[0].hooks[0].command' "${settings}")"

    [[ "${stop_cmd}" == /* ]]
    [[ "${stop_cmd}" == */hooks/stop.sh ]]
}

@test "install.sh creates valid JSON settings" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    jq '.' "${settings}" > /dev/null 2>&1
}

# ============================================================
# install.sh: existing settings (merge)
# ============================================================

@test "install.sh merges hooks into existing settings" {
    mkdir -p "${TEST_PROJECT}/.claude"
    echo '{"customSetting": true}' > "${TEST_PROJECT}/.claude/settings.json"

    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"

    # Original setting preserved
    local custom
    custom="$(jq -r '.customSetting' "${settings}")"
    [ "${custom}" = "true" ]

    # Hooks added
    local pre_cmd
    pre_cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "${settings}")"
    [[ "${pre_cmd}" == */hooks/pre-tool-use.sh ]]
}

# ============================================================
# install.sh: hook scripts are executable
# ============================================================

@test "install.sh makes hook scripts executable" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    [ -x "${PROJECT_ROOT}/hooks/pre-tool-use.sh" ]
    [ -x "${PROJECT_ROOT}/hooks/post-tool-use.sh" ]
    [ -x "${PROJECT_ROOT}/hooks/stop.sh" ]
}

# ============================================================
# install.sh: creates state and audit directories
# ============================================================

@test "install.sh creates state and audit directories" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    [ -d "${PROJECT_ROOT}/state" ]
    [ -d "${PROJECT_ROOT}/audit" ]
}

# ============================================================
# install.sh: idempotent (can run twice)
# ============================================================

@test "install.sh is idempotent" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    jq '.' "${settings}" > /dev/null 2>&1

    # Should still have exactly one PreToolUse entry
    local count
    count="$(jq '.hooks.PreToolUse | length' "${settings}")"
    [ "${count}" -eq 1 ]
}

# ============================================================
# uninstall.sh: removes hooks
# ============================================================

@test "uninstall.sh removes hooks from settings" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null
    bash "${PROJECT_ROOT}/install/uninstall.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    [ -f "${settings}" ]

    # Hooks should be removed
    local pre
    pre="$(jq -r '.hooks.PreToolUse // "removed"' "${settings}")"
    [ "${pre}" = "removed" ]
}

@test "uninstall.sh handles missing settings gracefully" {
    run bash "${PROJECT_ROOT}/install/uninstall.sh" "${TEST_PROJECT}"
    assert_success
}

# ============================================================
# PreToolUse hook matcher is empty string (matches all tools)
# ============================================================

@test "PreToolUse matcher is empty string (matches all tools)" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    local matcher
    matcher="$(jq -r '.hooks.PreToolUse[0].matcher' "${settings}")"
    [ "${matcher}" = "" ]
}

@test "PostToolUse matcher is empty string (matches all tools)" {
    bash "${PROJECT_ROOT}/install/install.sh" "${TEST_PROJECT}" > /dev/null

    local settings="${TEST_PROJECT}/.claude/settings.json"
    local matcher
    matcher="$(jq -r '.hooks.PostToolUse[0].matcher' "${settings}")"
    [ "${matcher}" = "" ]
}
