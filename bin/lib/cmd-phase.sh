#!/bin/bash
# oath-status: phase display (sourced by bin/oath, not executed directly)

# cmd_phase — print current phase in uppercase with bold formatting
# Reads phase from OATH_PHASE_FILE via tpe_get_current_phase (tool-profile.sh)
cmd_phase() {
    local phase
    phase="$(tpe_get_current_phase)"
    printf "Current phase: %s%s%s\n" "${FMT_BOLD}" "$(echo "${phase}" | tr '[:lower:]' '[:upper:]')" "${FMT_RESET}"
}
