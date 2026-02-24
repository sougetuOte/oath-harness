#!/bin/bash
# oath-status: configuration display (sourced by bin/oath, not executed directly)

# _cfg_custom_marker — returns "(custom)" if current value differs from default, else ""
# Args: jq_key (dotted path like "trust.initial_score"), current_value (string)
_cfg_custom_marker() {
    local jq_key="$1"
    local current="$2"
    local jq_path default_val

    jq_path="$(printf '%s' "${jq_key}" | jq -R 'split(".")')"
    default_val="$(printf '%s' "${_OATH_CONFIG_DEFAULTS}" | jq -r --argjson path "${jq_path}" 'getpath($path) // empty')"

    if [[ "${current}" != "${default_val}" ]]; then
        printf " (custom)"
    fi
}

# cmd_config — display all oath-harness configuration values
# Compares each value against _OATH_CONFIG_DEFAULTS and annotates custom values.
cmd_config() {
    printf "oath-harness configuration (config/settings.json)\n"

    # --- Trust ---
    local initial_score hibernation_days boost_threshold warmup_operations failure_decay
    initial_score="$(config_get "trust.initial_score")"
    hibernation_days="$(config_get "trust.hibernation_days")"
    boost_threshold="$(config_get "trust.boost_threshold")"
    warmup_operations="$(config_get "trust.warmup_operations")"
    failure_decay="$(config_get "trust.failure_decay")"

    printf "\nTrust:\n"
    printf "  %-22s %s%s\n" "initial_score:" "${initial_score}" "$(_cfg_custom_marker "trust.initial_score" "${initial_score}")"
    printf "  %-22s %s%s\n" "hibernation_days:" "${hibernation_days}" "$(_cfg_custom_marker "trust.hibernation_days" "${hibernation_days}")"
    printf "  %-22s %s%s\n" "boost_threshold:" "${boost_threshold}" "$(_cfg_custom_marker "trust.boost_threshold" "${boost_threshold}")"
    printf "  %-22s %s%s\n" "warmup_operations:" "${warmup_operations}" "$(_cfg_custom_marker "trust.warmup_operations" "${warmup_operations}")"
    printf "  %-22s %s%s\n" "failure_decay:" "${failure_decay}" "$(_cfg_custom_marker "trust.failure_decay" "${failure_decay}")"

    # --- Risk weights ---
    local lambda1 lambda2
    lambda1="$(config_get "risk.lambda1")"
    lambda2="$(config_get "risk.lambda2")"

    printf "\nRisk weights:\n"
    printf "  %-22s %s%s\n" "lambda1:" "${lambda1}" "$(_cfg_custom_marker "risk.lambda1" "${lambda1}")"
    printf "  %-22s %s%s\n" "lambda2:" "${lambda2}" "$(_cfg_custom_marker "risk.lambda2" "${lambda2}")"

    # --- Autonomy thresholds ---
    local auto_approve human_required
    auto_approve="$(config_get "autonomy.auto_approve_threshold")"
    human_required="$(config_get "autonomy.human_required_threshold")"

    printf "\nAutonomy thresholds:\n"
    printf "  %-22s %s%s\n" "auto_approve:" "${auto_approve}" "$(_cfg_custom_marker "autonomy.auto_approve_threshold" "${auto_approve}")"
    printf "  %-22s %s%s\n" "human_required:" "${human_required}" "$(_cfg_custom_marker "autonomy.human_required_threshold" "${human_required}")"
}
