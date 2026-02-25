#!/bin/bash
# oath-harness configuration loader and validator
# Loads settings.json, validates constraints, provides config_get accessor
set -euo pipefail

# Internal: cached config JSON
_OATH_CONFIG=""

# Default settings (used when settings.json is missing or incomplete)
_OATH_CONFIG_DEFAULTS='{
  "trust": {
    "hibernation_days": 14,
    "boost_threshold": 20,
    "initial_score": 0.3,
    "warmup_operations": 5,
    "failure_decay": 0.85,
    "recovery_boost_multiplier": 1.5
  },
  "risk": {
    "lambda1": 0.6,
    "lambda2": 0.4
  },
  "autonomy": {
    "auto_approve_threshold": 0.8,
    "human_required_threshold": 0.4
  },
  "audit": {
    "log_dir": "audit"
  },
  "model": {
    "opus_aot_threshold": 2
  }
}'

# Load settings.json into memory. Merges with defaults so partial configs work.
config_load() {
    if [[ -f "${SETTINGS_FILE}" ]]; then
        _OATH_CONFIG="$(jq -c --argjson defaults "${_OATH_CONFIG_DEFAULTS}" \
            '$defaults * .' "${SETTINGS_FILE}" 2>/dev/null)" || {
            log_error "Failed to parse settings.json, using defaults"
            _OATH_CONFIG="${_OATH_CONFIG_DEFAULTS}"
        }
    else
        log_debug "settings.json not found, using defaults"
        _OATH_CONFIG="${_OATH_CONFIG_DEFAULTS}"
    fi
}

# Get a config value by dotted key path (e.g. "trust.initial_score")
# Outputs the raw value (no quotes for numbers/booleans, quoted for strings)
# Warns on stderr if the key is not in the known defaults structure.
config_get() {
    local key="$1"
    if [[ -z "${_OATH_CONFIG}" ]]; then
        config_load
    fi
    local jq_path
    jq_path="$(printf '%s' "${key}" | jq -R 'split(".")')"

    # Validate key against defaults structure
    local known
    known="$(printf '%s' "${_OATH_CONFIG_DEFAULTS}" | jq --argjson path "${jq_path}" 'getpath($path) != null')"
    if [[ "${known}" != "true" ]]; then
        log_error "config_get: unknown key '${key}'"
    fi

    printf '%s' "${_OATH_CONFIG}" | jq -r --argjson path "${jq_path}" 'getpath($path) // null'
}

# Validate loaded config against safety constraints
# Returns 0 on success, 1 on validation failure
config_validate() {
    if [[ -z "${_OATH_CONFIG}" ]]; then
        config_load
    fi

    local initial_score auto_th human_th failure_decay has_override

    initial_score="$(printf '%s' "${_OATH_CONFIG}" | jq -r '.trust.initial_score // 0.3')"
    auto_th="$(printf '%s' "${_OATH_CONFIG}" | jq -r '.autonomy.auto_approve_threshold // 0.8')"
    human_th="$(printf '%s' "${_OATH_CONFIG}" | jq -r '.autonomy.human_required_threshold // 0.4')"
    failure_decay="$(printf '%s' "${_OATH_CONFIG}" | jq -r '.trust.failure_decay // 0.85')"
    has_override="$(printf '%s' "${_OATH_CONFIG}" | jq 'has("trust") and (.trust | has("trust_score_override"))')"

    # Rule 1: initial_score <= 0.5
    if _float_cmp "${initial_score} > 0.5"; then
        log_error "Validation failed: trust.initial_score must be <= 0.5, got: ${initial_score}"
        return 1
    fi

    # Rule 2: auto_approve_threshold > human_required_threshold
    if _float_cmp "${auto_th} <= ${human_th}"; then
        log_error "Validation failed: autonomy.auto_approve_threshold (${auto_th}) must be > autonomy.human_required_threshold (${human_th})"
        return 1
    fi

    # Rule 3: 0.5 <= failure_decay < 1.0
    if _float_cmp "${failure_decay} < 0.5"; then
        log_error "Validation failed: trust.failure_decay must be >= 0.5, got: ${failure_decay}"
        return 1
    fi
    if _float_cmp "${failure_decay} >= 1.0"; then
        log_error "Validation failed: trust.failure_decay must be < 1.0, got: ${failure_decay}"
        return 1
    fi

    # Rule 4: trust_score_override is forbidden
    if [[ "${has_override}" == "true" ]]; then
        log_error "Validation failed: trust.trust_score_override is not allowed"
        return 1
    fi

    return 0
}
