#!/bin/bash
# oath-harness Tool Profile Engine
# Phase-based tool access control
set -euo pipefail

# Phase file path (overridable for testing)
OATH_PHASE_FILE="${OATH_PHASE_FILE:-${HARNESS_ROOT}/.claude/current-phase.md}"

# Get the current phase from .claude/current-phase.md
# Output: "planning" | "building" | "auditing" (always lowercase for internal use)
# Falls back to "auditing" (most restrictive) if unknown
# Note: File stores UPPERCASE (e.g. "BUILDING"), this function normalizes to lowercase
tpe_get_current_phase() {
    if [[ ! -f "${OATH_PHASE_FILE}" ]]; then
        echo "auditing"
        return 0
    fi

    local raw_phase
    raw_phase="$(tr -d '[:space:]' < "${OATH_PHASE_FILE}" | tr '[:upper:]' '[:lower:]')"

    case "${raw_phase}" in
        planning|building|auditing)
            echo "${raw_phase}"
            ;;
        *)
            echo "auditing"
            ;;
    esac
}

# Check if a tool is allowed in the given phase
# Args: tool_name (string), domain (string), phase (string)
# Output: "allowed" | "blocked" | "trust_gated"
tpe_check() {
    local tool_name="$1"
    local domain="$2"
    local phase="$3"

    # Normalize unknown phases to auditing
    case "${phase}" in
        planning|building|auditing) ;;
        *) phase="auditing" ;;
    esac

    # Check denied first (highest priority)
    if _tpe_is_denied "${domain}" "${phase}"; then
        echo "blocked"
        return 0
    fi

    # Check trust_gated
    if _tpe_is_trust_gated "${domain}" "${phase}"; then
        echo "trust_gated"
        return 0
    fi

    # Check allowed
    if _tpe_is_allowed "${domain}" "${phase}"; then
        echo "allowed"
        return 0
    fi

    # Undefined domain: phase-dependent default
    if [[ "${phase}" == "auditing" ]]; then
        echo "blocked"
    else
        echo "allowed"
    fi
}

# Update the current phase (stores as UPPERCASE in file)
# Args: phase (string, any case — normalized to UPPERCASE for storage)
tpe_set_phase() {
    local phase="$1"
    local upper_phase
    upper_phase="$(echo "${phase}" | tr '[:lower:]' '[:upper:]')"
    echo "${upper_phase}" > "${OATH_PHASE_FILE}"
}

# --- Internal: Profile definitions ---

_tpe_is_denied() {
    local domain="$1" phase="$2"
    case "${phase}" in
        planning)
            [[ "${domain}" =~ ^(file_write|file_write_src|shell_exec|git_remote)$ ]]
            ;;
        building)
            [[ "${domain}" == "git_remote" ]]
            ;;
        auditing)
            [[ "${domain}" =~ ^(file_write|shell_exec|git_local|git_remote)$ ]]
            ;;
        *)
            # Unknown = most restrictive (auditing)
            [[ "${domain}" =~ ^(file_write|shell_exec|git_local|git_remote)$ ]]
            ;;
    esac
}

_tpe_is_trust_gated() {
    local domain="$1" phase="$2"
    case "${phase}" in
        building)
            [[ "${domain}" =~ ^(shell_exec|git_local)$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

_tpe_is_allowed() {
    local domain="$1" phase="$2"
    case "${phase}" in
        planning)
            [[ "${domain}" =~ ^(file_read|git_read|docs_write)$ ]]
            ;;
        building)
            [[ "${domain}" =~ ^(file_read|file_write|git_read|git_local|shell_exec|test_run)$ ]]
            ;;
        auditing)
            [[ "${domain}" =~ ^(file_read|git_read)$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}
