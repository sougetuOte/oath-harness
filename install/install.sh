#!/bin/bash
# oath-harness installer
# Registers hooks in Claude Code settings.json
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="${1:-${PWD}}"
CLAUDE_SETTINGS="${PROJECT_ROOT}/.claude/settings.json"

echo "oath-harness install"
echo "  harness: ${HARNESS_ROOT}"
echo "  project: ${PROJECT_ROOT}"

# --- Prerequisites ---

check_prerequisites() {
    local missing=()
    command -v bash >/dev/null || missing+=("bash")
    command -v jq >/dev/null || missing+=("jq")
    command -v flock >/dev/null || missing+=("flock (util-linux)")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing commands: ${missing[*]}" >&2
        exit 1
    fi

    # Ensure hook scripts are executable
    for hook in pre-tool-use.sh post-tool-use.sh stop.sh; do
        chmod +x "${HARNESS_ROOT}/hooks/${hook}"
    done
}

# --- Hooks registration ---

install_hooks() {
    mkdir -p "${PROJECT_ROOT}/.claude"

    local pre_hook="${HARNESS_ROOT}/hooks/pre-tool-use.sh"
    local post_hook="${HARNESS_ROOT}/hooks/post-tool-use.sh"
    local stop_hook="${HARNESS_ROOT}/hooks/stop.sh"

    if [ -f "${CLAUDE_SETTINGS}" ]; then
        # Validate existing settings.json before merging
        if ! jq empty "${CLAUDE_SETTINGS}" 2>/dev/null; then
            echo "Error: existing settings.json is not valid JSON: ${CLAUDE_SETTINGS}" >&2
            echo "Please fix or remove it before installing oath-harness." >&2
            exit 1
        fi
        # Merge into existing settings
        jq --arg pre "${pre_hook}" \
           --arg post "${post_hook}" \
           --arg stop "${stop_hook}" \
        'def remove_cmd($cmd): map(select((.hooks // []) | all(.command != $cmd)));
        .hooks.PreToolUse = ((.hooks.PreToolUse // [] | remove_cmd($pre)) + [{"matcher":"","hooks":[{"type":"command","command":$pre}]}])
        | .hooks.PostToolUse = ((.hooks.PostToolUse // [] | remove_cmd($post)) + [{"matcher":"","hooks":[{"type":"command","command":$post}]}])
        | .hooks.Stop = ((.hooks.Stop // [] | remove_cmd($stop)) + [{"hooks":[{"type":"command","command":$stop}]}])' \
        "${CLAUDE_SETTINGS}" > "${CLAUDE_SETTINGS}.tmp" \
        && mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}"
    else
        # Create new settings file
        jq -n --arg pre "${pre_hook}" \
              --arg post "${post_hook}" \
              --arg stop "${stop_hook}" \
        '{
          "hooks": {
            "PreToolUse": [{"matcher":"","hooks":[{"type":"command","command":$pre}]}],
            "PostToolUse": [{"matcher":"","hooks":[{"type":"command","command":$post}]}],
            "Stop": [{"hooks":[{"type":"command","command":$stop}]}]
          }
        }' > "${CLAUDE_SETTINGS}"
    fi
}

# --- Directory initialization ---

init_directories() {
    mkdir -p "${HARNESS_ROOT}"/{state,audit,config}
}

# --- Main ---

check_prerequisites
install_hooks
init_directories

echo ""
echo "Install complete."
echo "oath-harness will be active in the next Claude Code session."
echo ""
echo "Hooks registered in: ${CLAUDE_SETTINGS}"
jq '.hooks' "${CLAUDE_SETTINGS}"
