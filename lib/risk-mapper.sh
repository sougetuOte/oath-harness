#!/bin/bash
# oath-harness Risk Category Mapper
# Classifies tool calls into risk categories and maps to domains
set -euo pipefail

# Classify a tool call into a risk category
# Args: tool_name (string), tool_input (JSON string)
# Output: "low 1 0.2" | "medium 2 0.5" | "high 3 0.7" | "critical 4 1.0" (stdout)
rcm_classify() {
    local tool_name="$1"
    local tool_input="$2"

    # Extract command for Bash tool
    local cmd=""
    if [[ "${tool_name}" == "Bash" ]]; then
        cmd="$(printf '%s' "${tool_input}" | jq -r '.command // ""' 2>/dev/null)"
    fi

    # Priority 1: critical patterns (always block)
    if _rcm_is_critical "${tool_name}" "${cmd}" "${tool_input}"; then
        echo "critical 4 1.0"
        return 0
    fi

    # Priority 2: Deny List (high risk)
    if _rcm_is_denied "${tool_name}" "${cmd}"; then
        echo "high 3 0.7"
        return 0
    fi

    # Priority 2.5: Compound command analysis (CW-1, WARN-001)
    # Split on ;, &&, ||, | and check each sub-command independently.
    # Limitation: sed-based splitting does not respect quoted strings.
    # e.g., `echo "hello; world"` would be split on the semicolon.
    # This is intentionally fail-safe: over-classification (higher risk) is acceptable,
    # under-classification (missing a dangerous sub-command) is not.
    # Full bash parsing is out of scope for this project (ADR: no external dependencies).
    if echo "${cmd}" | grep -qE '[;|&]{1,2}'; then
        local subcmd
        local has_non_allowed=false
        while IFS= read -r subcmd; do
            subcmd="$(echo "${subcmd}" | sed 's/^[[:space:]]*//')"
            [[ -z "${subcmd}" ]] && continue
            if _rcm_is_critical "${tool_name}" "${subcmd}" "${tool_input}"; then
                echo "critical 4 1.0"
                return 0
            fi
            if _rcm_is_denied "${tool_name}" "${subcmd}"; then
                echo "high 3 0.7"
                return 0
            fi
            if ! _rcm_is_allowed "${tool_name}" "${subcmd}"; then
                has_non_allowed=true
            fi
        done < <(echo "${cmd}" | sed 's/[;&|]\+/\n/g')

        if [[ "${has_non_allowed}" == "true" ]]; then
            echo "medium 2 0.5"
        else
            echo "low 1 0.2"
        fi
        return 0
    fi

    # Priority 3: Allow List (low risk)
    if _rcm_is_allowed "${tool_name}" "${cmd}"; then
        echo "low 1 0.2"
        return 0
    fi

    # Priority 4: Gray Area (medium)
    echo "medium 2 0.5"
}

# Get the domain for a tool call
# Args: tool_name (string), tool_input (JSON string)
# Output: domain (string, stdout)
rcm_get_domain() {
    local tool_name="$1"
    local tool_input="$2"

    # Non-Bash tools
    case "${tool_name}" in
        Read|Glob|Grep)
            echo "file_read"
            return 0
            ;;
        Write|Edit)
            local file_path
            file_path="$(printf '%s' "${tool_input}" | jq -r '.file_path // ""' 2>/dev/null)"
            if command -v realpath >/dev/null 2>&1; then
                file_path="$(realpath -m "${file_path}" 2>/dev/null || printf '%s' "${file_path}")"
            fi
            if [[ "${file_path}" == */docs/* ]]; then
                echo "docs_write"
            elif [[ "${file_path}" == */src/* || "${file_path}" == src/* ]]; then
                echo "file_write_src"
            else
                echo "file_write"
            fi
            return 0
            ;;
    esac

    # Bash tool: inspect command
    if [[ "${tool_name}" == "Bash" ]]; then
        local cmd
        cmd="$(printf '%s' "${tool_input}" | jq -r '.command // ""' 2>/dev/null)"
        local first_word
        first_word="$(echo "${cmd}" | awk '{print $1}')"

        # File read commands
        if [[ "${first_word}" =~ ^(ls|cat|grep|find|head|tail|wc|file|du|pwd)$ ]]; then
            echo "file_read"
            return 0
        fi

        # Test execution
        if [[ "${cmd}" =~ (pytest|npm\ test|go\ test|bats) ]]; then
            echo "test_run"
            return 0
        fi

        # Git operations
        if [[ "${first_word}" == "git" ]]; then
            local git_sub
            git_sub="$(echo "${cmd}" | awk '{print $2}')"
            case "${git_sub}" in
                push|pull|fetch|clone)
                    echo "git_remote"
                    return 0
                    ;;
                add|commit|stash|rebase|merge|cherry-pick|tag)
                    echo "git_local"
                    return 0
                    ;;
                status|log|diff|show|branch|remote)
                    echo "git_read"
                    return 0
                    ;;
            esac
        fi

        echo "shell_exec"
        return 0
    fi

    # Unknown tool
    echo "_global"
}

# --- Internal classification functions ---

_rcm_is_critical() {
    local tool_name="$1" cmd="$2" tool_input="$3"

    # curl/wget with external URL
    if [[ "${cmd}" =~ (curl|wget)[[:space:]] ]] && [[ "${cmd}" =~ https?:// ]]; then
        return 0
    fi

    # Sensitive environment variables in command
    if [[ "${cmd^^}" =~ (API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY|ACCESS_KEY)= ]]; then
        return 0
    fi

    # Email sending commands
    if [[ "${cmd}" =~ ^(mail|sendmail|smtp)[[:space:]] ]]; then
        return 0
    fi

    return 1
}

_rcm_is_denied() {
    local tool_name="$1" cmd="$2"

    local first_word
    first_word="$(echo "${cmd}" | awk '{print $1}')"

    # Destructive file operations
    if [[ "${first_word}" == "rm" ]]; then
        return 0
    fi

    # Permission changes
    if [[ "${first_word}" =~ ^(chmod|chown)$ ]]; then
        return 0
    fi

    # Package managers (system modification)
    if [[ "${first_word}" =~ ^(apt|apt-get|brew|yum|dnf)$ ]]; then
        return 0
    fi
    if [[ "${cmd}" =~ ^pip\ install ]]; then
        return 0
    fi

    # Git remote operations
    if [[ "${cmd}" =~ ^git\ (push|force|merge) ]]; then
        return 0
    fi

    # Remote access
    if [[ "${first_word}" =~ ^(ssh|scp)$ ]]; then
        return 0
    fi

    # System control
    if [[ "${first_word}" =~ ^(systemctl|reboot|shutdown)$ ]]; then
        return 0
    fi

    return 1
}

_rcm_is_allowed() {
    local tool_name="$1" cmd="$2"

    # Non-Bash safe tools
    if [[ "${tool_name}" =~ ^(Read|Glob|Grep)$ ]]; then
        return 0
    fi

    local first_word
    first_word="$(echo "${cmd}" | awk '{print $1}')"

    # Safe read-only commands
    if [[ "${first_word}" =~ ^(ls|cat|grep|find|pwd|du|file|head|tail|wc|echo|printf|jq|sort|uniq|tr|cut|tee|basename|dirname|date|whoami)$ ]]; then
        return 0
    fi

    # Git read-only
    if [[ "${cmd}" =~ ^git\ (status|log|diff|show|branch) ]]; then
        return 0
    fi

    # Test runners
    if [[ "${cmd}" =~ (pytest|npm\ test|go\ test|bats) ]]; then
        return 0
    fi

    return 1
}
