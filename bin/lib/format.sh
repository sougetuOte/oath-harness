#!/bin/bash
# oath-status display helpers (sourced by bin/oath, not executed directly)
# Color codes, score formatting, table drawing, relative time

# Terminal color support detection
_fmt_has_color() {
    [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

# ANSI color codes
if _fmt_has_color; then
    FMT_GREEN='\033[0;32m'
    FMT_YELLOW='\033[0;33m'
    FMT_RED='\033[0;31m'
    FMT_CYAN='\033[0;36m'
    FMT_BOLD='\033[1m'
    FMT_DIM='\033[2m'
    FMT_RESET='\033[0m'
else
    FMT_GREEN='' FMT_YELLOW='' FMT_RED=''
    FMT_CYAN='' FMT_BOLD='' FMT_DIM='' FMT_RESET=''
fi

# Score value colored output
# Args: score (float)
# Output: colored score string (stdout)
fmt_score() {
    local score="$1"
    if _float_cmp "${score} >= 0.7"; then
        printf "${FMT_GREEN}%s${FMT_RESET}" "${score}"
    elif _float_cmp "${score} >= 0.4"; then
        printf "${FMT_YELLOW}%s${FMT_RESET}" "${score}"
    else
        printf "${FMT_RED}%s${FMT_RESET}" "${score}"
    fi
}

# Fixed-width table row
# Args: col1 col2 col3 col4
fmt_table_row() {
    printf "%-16s %-8s %-6s %s\n" "$1" "$2" "$3" "$4"
}

# ISO 8601 timestamp to relative time
# Args: iso_time (string)
# Output: "just now", "X min ago", "X hours ago", "X days ago"
# Note: Requires GNU date (-d flag). On BSD/macOS, falls back to raw ISO string.
_fmt_relative_time() {
    local iso_time="$1"
    local then_epoch now_epoch diff_seconds
    then_epoch="$(date -d "${iso_time}" '+%s' 2>/dev/null)" || { echo "${iso_time}"; return; }
    now_epoch="$(date -u '+%s')"
    diff_seconds=$(( now_epoch - then_epoch ))

    if (( diff_seconds < 60 )); then
        echo "just now"
    elif (( diff_seconds < 3600 )); then
        local mins=$(( diff_seconds / 60 ))
        echo "${mins} min ago"
    elif (( diff_seconds < 86400 )); then
        local hrs=$(( diff_seconds / 3600 ))
        if (( hrs == 1 )); then echo "1 hour ago"; else echo "${hrs} hours ago"; fi
    else
        local days=$(( diff_seconds / 86400 ))
        if (( days == 1 )); then echo "1 day ago"; else echo "${days} days ago"; fi
    fi
}
