#!/bin/bash
# oath-harness Model Router
# Recommends Opus/Sonnet/Haiku based on task complexity
# Phase 1: recommendation is recorded in audit trail only (no runtime model switching)
set -euo pipefail

# Recommend a model based on current context
# Args: autonomy (float), risk_category (string), trust (float), decision (string)
# Output: "opus" | "sonnet" | "haiku" (stdout)
mr_recommend() {
    local autonomy="$1"
    local risk_category="$2"
    local trust="$3"
    local decision="$4"

    # Architect (Opus): critical blocked decisions
    if [[ "${decision}" == "blocked" && "${risk_category}" == "critical" ]]; then
        echo "opus"
        return 0
    fi

    # Architect (Opus): low trust domain needs supervision
    if _float_cmp "${trust} < 0.4"; then
        echo "opus"
        return 0
    fi

    # Architect (Opus): complex judgment needed (low autonomy + non-trivial risk)
    if _float_cmp "${autonomy} < 0.6"; then
        if [[ "${risk_category}" == "medium" || "${risk_category}" == "high" ]]; then
            echo "opus"
            return 0
        fi
    fi

    # Worker/Reporter (Haiku): simple auto-approved low-risk
    if [[ "${decision}" == "auto_approved" && "${risk_category}" == "low" ]]; then
        echo "haiku"
        return 0
    fi

    # Default: Analyst (Sonnet)
    echo "sonnet"
}

# Map model to persona name
# Args: model (string)
# Output: persona (string)
mr_get_persona() {
    local model="$1"
    case "${model}" in
        opus)   echo "architect" ;;
        sonnet) echo "analyst" ;;
        haiku)  echo "worker" ;;
        *)      echo "analyst" ;;
    esac
}
