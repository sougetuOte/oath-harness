#!/usr/bin/env bats
# Unit tests for lib/config.sh

setup() {
    load '../bats-support/load'
    load '../bats-assert/load'

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    # Set up temp dir BEFORE sourcing common.sh so path constants use it
    TEST_TMP="$(mktemp -d)"
    export HARNESS_ROOT="${PROJECT_ROOT}"
    export CONFIG_DIR="${TEST_TMP}/config"
    export SETTINGS_FILE="${TEST_TMP}/config/settings.json"
    mkdir -p "${TEST_TMP}/config"

    source "${PROJECT_ROOT}/lib/common.sh"
    source "${PROJECT_ROOT}/lib/config.sh"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

# --- config_load ---

@test "config_load succeeds with valid settings.json" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    run config_load
    assert_success
}

@test "config_load uses defaults when settings.json is missing" {
    rm -f "${SETTINGS_FILE}"
    run config_load
    assert_success
}

# --- config_get ---

@test "config_get returns trust.initial_score from loaded config" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_get "trust.initial_score"
    assert_success
    assert_output "0.3"
}

@test "config_get returns risk.lambda1" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_get "risk.lambda1"
    assert_success
    assert_output "0.6"
}

@test "config_get returns risk.lambda2" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_get "risk.lambda2"
    assert_success
    assert_output "0.4"
}

@test "config_get returns autonomy.auto_approve_threshold" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_get "autonomy.auto_approve_threshold"
    assert_success
    assert_output "0.8"
}

@test "config_get returns null and warns for unknown key" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_get "nonexistent.key"
    assert_success
    assert_output --partial "null"
    assert_output --partial "unknown key"
}

@test "config_get falls back to default for key missing from settings" {
    # settings.json with trust section missing warmup_operations
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.3, "failure_decay": 0.85 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_get "trust.warmup_operations"
    assert_success
    assert_output "5"
}

# --- config_validate ---

@test "config_validate passes with valid settings" {
    cat > "${SETTINGS_FILE}" <<'TCFG'
{"trust":{"hibernation_days":14,"boost_threshold":20,"initial_score":0.3,"warmup_operations":5,"failure_decay":0.85},"risk":{"lambda1":0.6,"lambda2":0.4},"autonomy":{"auto_approve_threshold":0.8,"human_required_threshold":0.4},"audit":{"log_dir":"audit"},"model":{"opus_aot_threshold":2}}
TCFG
    config_load
    run config_validate
    assert_success
}

@test "config_validate fails when initial_score > 0.5" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.7, "warmup_operations": 5, "failure_decay": 0.85 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "initial_score"
}

@test "config_validate fails when auto_approve <= human_required threshold" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.3, "warmup_operations": 5, "failure_decay": 0.85 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.3, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "auto_approve_threshold"
}

@test "config_validate fails when failure_decay < 0.5" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.3, "warmup_operations": 5, "failure_decay": 0.3 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "failure_decay"
}

@test "config_validate fails when failure_decay >= 1.0" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.3, "warmup_operations": 5, "failure_decay": 1.0 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "failure_decay"
}

# --- Rule 5: recovery_boost_multiplier ---

@test "config_validate fails when recovery_boost_multiplier < 1.0" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "initial_score": 0.3, "failure_decay": 0.85, "recovery_boost_multiplier": 0.5 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "recovery_boost_multiplier"
}

@test "config_validate fails when recovery_boost_multiplier > 5.0" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "initial_score": 0.3, "failure_decay": 0.85, "recovery_boost_multiplier": 10.0 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "recovery_boost_multiplier"
}

@test "config_validate passes with valid recovery_boost_multiplier" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "initial_score": 0.3, "failure_decay": 0.85, "recovery_boost_multiplier": 2.0 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 }
}
EOF
    config_load
    run config_validate
    assert_success
}

@test "config_validate passes with recovery_boost_multiplier at boundary 1.0" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "initial_score": 0.3, "failure_decay": 0.85, "recovery_boost_multiplier": 1.0 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 }
}
EOF
    config_load
    run config_validate
    assert_success
}

@test "config_validate passes with recovery_boost_multiplier at boundary 5.0" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "initial_score": 0.3, "failure_decay": 0.85, "recovery_boost_multiplier": 5.0 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 }
}
EOF
    config_load
    run config_validate
    assert_success
}

@test "config_validate fails when trust_score_override exists" {
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "trust": { "hibernation_days": 14, "boost_threshold": 20, "initial_score": 0.3, "warmup_operations": 5, "failure_decay": 0.85, "trust_score_override": 1.0 },
  "risk": { "lambda1": 0.6, "lambda2": 0.4 },
  "autonomy": { "auto_approve_threshold": 0.8, "human_required_threshold": 0.4 },
  "audit": { "log_dir": "audit" },
  "model": { "opus_aot_threshold": 2 }
}
EOF
    config_load
    run config_validate
    assert_failure
    assert_output --partial "trust_score_override"
}
