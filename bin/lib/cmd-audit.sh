#!/bin/bash
# oath-status: audit log display (sourced by bin/oath, not executed directly)

# Display today's audit log entries
# Args: [--tail N]
cmd_audit() {
    local tail_count=10

    # Parse --tail N option
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tail)
                shift
                tail_count="${1:?--tail requires a number}"
                shift
                ;;
            --tail=*)
                tail_count="${1#--tail=}"
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Validate tail_count is a positive integer
    if ! [[ "${tail_count}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --tail requires a positive integer, got '${tail_count}'" >&2
        return 1
    fi

    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${AUDIT_DIR}/${today}.jsonl"

    if [[ ! -f "${audit_file}" ]]; then
        echo "No audit entries for today."
        return 0
    fi

    local total_entries pending_entries
    total_entries="$(wc -l < "${audit_file}")"
    pending_entries="$(jq -c 'select(.outcome == "pending")' "${audit_file}" | wc -l)"

    printf "${FMT_BOLD}Audit log: %s  |  %s entries (%s pending)${FMT_RESET}\n" \
        "${today}" "${total_entries}" "${pending_entries}"
    echo ""
    echo "Recent decisions:"

    _cmd_audit_entries "${audit_file}" "${tail_count}"
}

# Format and print audit entries
# Args: file count
_cmd_audit_entries() {
    local file="$1"
    local count="$2"

    jq -r 'select(.outcome == "pending") |
        [.timestamp[11:19],
         (.tool_name + "(" + ((.tool_input.command // .tool_input.file_path // "...") | tostring)[0:20] + ")"),
         .domain, .risk_category, .decision] | @tsv' \
        "${file}" | tail -n "${count}" | \
    while IFS=$'\t' read -r ts tool domain risk decision; do
        printf "  %-10s %-25s %-12s %-8s %s\n" \
            "${ts}" "${tool}" "${domain}" "${risk}" "${decision}"
    done
}
