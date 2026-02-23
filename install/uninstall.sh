#!/bin/bash
# oath-harness uninstaller
# Removes hooks from Claude Code settings.json
set -euo pipefail

PROJECT_ROOT="${1:-${PWD}}"
CLAUDE_SETTINGS="${PROJECT_ROOT}/.claude/settings.json"

if [ ! -f "${CLAUDE_SETTINGS}" ]; then
    echo "No settings file found: ${CLAUDE_SETTINGS}"
    exit 0
fi

jq 'del(.hooks.PreToolUse, .hooks.PostToolUse, .hooks.Stop)' \
   "${CLAUDE_SETTINGS}" > "${CLAUDE_SETTINGS}.tmp" \
&& mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}"

echo "oath-harness hooks removed from: ${CLAUDE_SETTINGS}"
