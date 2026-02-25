#!/bin/bash
# oath-harness uninstaller
# Removes only oath-harness hooks from Claude Code settings.json
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="${1:-${PWD}}"
CLAUDE_SETTINGS="${PROJECT_ROOT}/.claude/settings.json"

if [ ! -f "${CLAUDE_SETTINGS}" ]; then
    echo "No settings file found: ${CLAUDE_SETTINGS}"
    exit 0
fi

# Remove only entries whose command references oath-harness
jq --arg root "${HARNESS_ROOT}" '
    def remove_oath($root):
        if type == "array" then
            [.[] | select(
                (.hooks // []) | all(.command | test($root) | not)
            )]
        else .
        end;
    .hooks.PreToolUse = (.hooks.PreToolUse // [] | remove_oath($root))
    | .hooks.PostToolUse = (.hooks.PostToolUse // [] | remove_oath($root))
    | .hooks.PostToolUseFailure = (.hooks.PostToolUseFailure // [] | remove_oath($root))
    | .hooks.Stop = (.hooks.Stop // [] | remove_oath($root))
    | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
    | if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end
    | if .hooks.PostToolUseFailure == [] then del(.hooks.PostToolUseFailure) else . end
    | if .hooks.Stop == [] then del(.hooks.Stop) else . end
' "${CLAUDE_SETTINGS}" > "${CLAUDE_SETTINGS}.tmp" \
&& mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}"

echo "oath-harness hooks removed from: ${CLAUDE_SETTINGS}"
