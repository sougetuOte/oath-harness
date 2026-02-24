#!/bin/bash
# oath-status: demo data generator (sourced by bin/oath, not executed directly)
# Generates sample trust-scores.json and audit JSONL in a temp directory,
# then runs all subcommands to showcase oath-harness output.

# Generate demo data and run all subcommands for demonstration.
cmd_demo() {
    local demo_dir
    demo_dir="$(mktemp -d)"
    # Capture path in trap string so cleanup works even if local var is out of scope
    trap "rm -rf '${demo_dir}'" EXIT

    _demo_generate_trust_scores "${demo_dir}"
    _demo_generate_audit_entries "${demo_dir}"
    _demo_generate_phase "${demo_dir}"

    # Override environment to use demo data
    local orig_trust_scores="${TRUST_SCORES_FILE}"
    local orig_audit_dir="${AUDIT_DIR}"
    local orig_phase_file="${OATH_PHASE_FILE}"

    TRUST_SCORES_FILE="${demo_dir}/trust-scores.json"
    AUDIT_DIR="${demo_dir}/audit"
    OATH_PHASE_FILE="${demo_dir}/current-phase.md"

    printf -- "${FMT_BOLD}=== oath demo ===${FMT_RESET}\n"
    printf -- "${FMT_DIM}(using generated sample data)${FMT_RESET}\n\n"

    printf -- "${FMT_BOLD}--- oath status ---${FMT_RESET}\n"
    cmd_status
    echo ""

    printf -- "${FMT_BOLD}--- oath status file_read ---${FMT_RESET}\n"
    cmd_status file_read
    echo ""

    printf -- "${FMT_BOLD}--- oath audit ---${FMT_RESET}\n"
    cmd_audit
    echo ""

    printf -- "${FMT_BOLD}--- oath config ---${FMT_RESET}\n"
    cmd_config
    echo ""

    printf -- "${FMT_BOLD}--- oath phase ---${FMT_RESET}\n"
    cmd_phase
    echo ""

    printf -- "${FMT_BOLD}=== demo complete ===${FMT_RESET}\n"

    # Restore original environment
    TRUST_SCORES_FILE="${orig_trust_scores}"
    AUDIT_DIR="${orig_audit_dir}"
    OATH_PHASE_FILE="${orig_phase_file}"
}

# Generate sample trust-scores.json with 5 domains at various trust levels.
# Args: demo_dir (path)
_demo_generate_trust_scores() {
    local dir="$1"
    cat > "${dir}/trust-scores.json" <<'EOF'
{
  "version": "2",
  "updated_at": "2026-02-24T10:00:00Z",
  "global_operation_count": 59,
  "domains": {
    "_global": {
      "score": 0.30,
      "successes": 0,
      "failures": 0,
      "total_operations": 0,
      "last_operated_at": "2026-02-24T10:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "file_read": {
      "score": 0.82,
      "successes": 34,
      "failures": 1,
      "total_operations": 35,
      "last_operated_at": "2026-02-24T09:55:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": 0.51,
      "successes": 10,
      "failures": 1,
      "total_operations": 11,
      "last_operated_at": "2026-02-24T09:50:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "file_write": {
      "score": 0.45,
      "successes": 7,
      "failures": 1,
      "total_operations": 8,
      "last_operated_at": "2026-02-24T09:48:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "git_local": {
      "score": 0.38,
      "successes": 4,
      "failures": 1,
      "total_operations": 5,
      "last_operated_at": "2026-02-24T09:45:00Z",
      "is_warming_up": true,
      "warmup_remaining": 2
    }
  }
}
EOF
}

# Generate sample audit JSONL with 8 entries covering all decision types.
# Args: demo_dir (path)
_demo_generate_audit_entries() {
    local dir="$1"
    local audit_dir="${dir}/audit"
    local today
    today="$(date -u '+%Y-%m-%d')"
    local audit_file="${audit_dir}/${today}.jsonl"
    mkdir -p "${audit_dir}"

    cat > "${audit_file}" <<'EOF'
{"timestamp":"2026-02-24T09:30:00Z","tool_name":"Read","tool_input":{"file_path":"src/main.sh"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:32:00Z","tool_name":"Read","tool_input":{"file_path":"lib/config.sh"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:34:00Z","tool_name":"Bash","tool_input":{"command":"npm test"},"domain":"shell_exec","risk_category":"medium","decision":"logged_only","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:36:00Z","tool_name":"Write","tool_input":{"file_path":"src/new-feature.sh"},"domain":"file_write","risk_category":"medium","decision":"logged_only","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:38:00Z","tool_name":"Bash","tool_input":{"command":"git commit -m fix"},"domain":"git_local","risk_category":"high","decision":"human_required","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:40:00Z","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/old"},"domain":"shell_exec","risk_category":"critical","decision":"blocked","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:42:00Z","tool_name":"Read","tool_input":{"file_path":"tests/unit.bats"},"domain":"file_read","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
{"timestamp":"2026-02-24T09:44:00Z","tool_name":"Bash","tool_input":{"command":"ls -la"},"domain":"shell_exec","risk_category":"low","decision":"auto_approved","outcome":"pending","session_id":"demo-session"}
EOF
}

# Generate sample phase file.
# Args: demo_dir (path)
_demo_generate_phase() {
    local dir="$1"
    echo "BUILDING" > "${dir}/current-phase.md"
}
