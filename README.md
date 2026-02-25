# oath-harness

A trust-based execution control harness for Claude Code that implements Earned Autonomy.

[日本語版 / Japanese](README_ja.md)

---

## What is oath-harness?

### The Problem

Claude Code offers two extremes for permission control:

| Option | Problem |
|--------|---------|
| Default manual approval | Dozens to hundreds of approval prompts per day interrupt development flow. Users habituate and stop reading what they approve — approval fatigue creates a false sense of security. |
| `--dangerouslySkipPermissions` | Every operation runs without any check. Once enabled, returning to safe defaults requires deliberate action. Full automation with no safety net. |

There is no middle ground. Either you approve everything manually, or you approve nothing.

Anthropic's own data from 750 sessions shows that users naturally expand their auto-approve scope over time (from ~20% to 40%+) as trust in the agent accumulates. This pattern — **Earned Autonomy** — exists in user behavior but not in any tool. A survey of 100+ projects found zero implementations of a system that adjusts checkpoint frequency based on accumulated track record.

### The Solution

oath-harness introduces a third option: start with minimum privileges, earn trust through successful operations, and let autonomy increase automatically based on demonstrated reliability. Safety-by-Prompt alone (relying on instructions in a system prompt) fails under adversarial conditions — ICLR 2025 research documents a mixed attack success rate of 84.30%. oath-harness enforces constraints structurally through Claude Code's hooks API, not through prompt instructions.

```
Session start:     Minimum privileges (safe by default)
As you work:       Trust accumulates per successful operation (Earned Autonomy)
On failure:        Trust score drops, autonomy is automatically restricted
After a break:     Accumulated trust is preserved; fast return to prior autonomy level
```

---

## How It Works

oath-harness intercepts every tool call through Claude Code's hooks API and runs a trust-based decision before execution.

### Trust Lifecycle

1. **Session starts at low trust.** Every new domain begins at score `0.3`.
2. **Each successful tool use raises the score.** During the first 20 operations (initial boost period), each success adds approximately `+0.05 × (1 - score)`. After that, the rate slows to `+0.02 × (1 - score)`.
3. **Failures decrease trust by 15%.** A single failure applies `score = score × 0.85`.
4. **After normal use, most safe operations auto-approve.** With 10 successes on Day 1, a domain's score reaches approximately 0.45. By Day 3 with continued use, most routine operations clear the auto-approve threshold.
5. **Dormant trust is preserved.** If a domain has not been used within the last 14 days (`hibernation_days`), the score is frozen — no decay. After 14 days, gradual decay applies: `score × 0.999^(days - 14)`.
6. **Warm-up on return.** If a domain was dormant past the hibernation window, the first 5 operations run at 2x boost speed to quickly restore prior autonomy level.

### Domain-Based Trust

Trust is tracked separately per operation domain, not as a single global score:

| Domain | Covers |
|--------|--------|
| `file_read` | File reads, directory listing |
| `file_write` | File writes, creation, deletion (outside `docs/` and `src/`) |
| `file_write_src` | Writes to `src/` (blocked in PLANNING phase) |
| `docs_write` | Writes to `docs/` (used in PLANNING phase) |
| `test_run` | pytest, npm test, go test, etc. |
| `shell_exec` | Arbitrary shell command execution |
| `git_local` | `git add`, `git commit`, local Git operations |
| `git_remote` | `git push`, `git pull`, remote Git operations |
| `_global` | Fallback when no domain record exists |

High trust in `file_read` does not raise trust in `shell_exec`. Each domain must earn its own autonomy.

---

## Architecture

oath-harness is implemented in four layers:

```
+--------------------------------------------------------------+
| Layer 1: Model Router                                        |
|  Opus(Architect) / Sonnet(Analyst) / Haiku(Worker/Reporter)  |
|  Recommends model based on task complexity + trust score     |
+--------------------------------------------------------------+
| Layer 2: Trust Engine                                        |
|  Domain-based score accumulation -> autonomy calculation     |
|  Asymmetric update (success/failure) + time decay + warmup   |
+------------------+-------------------------------------------+
| Layer 3a: Harness| Layer 3b: Guardrail                       |
|  Session Bootstrap  Risk Category Mapper                     |
|  Audit Trail        Tool Profile Engine                      |
|  State management   Phase-based tool restrictions            |
+------------------+-------------------------------------------+
| Layer 4: Execution Layer                                     |
|  hooks/pre-tool-use.sh                                       |
|  hooks/post-tool-use.sh                                      |
|  hooks/stop.sh                                               |
|  (Interface with Claude Code hooks API)                      |
+--------------------------------------------------------------+
```

**Model Router** — Recommends Opus, Sonnet, or Haiku based on task complexity (AoT criteria) and domain trust level. Low-trust domains escalate to Opus (Architect persona) for higher scrutiny.

**Trust Engine** — Calculates autonomy score using the formula `autonomy = 1 - (lambda1 * risk + lambda2 * complexity) * (1 - trust)`. Produces one of four decisions per tool call.

**Harness + Guardrail Layer** — Session Bootstrap loads persisted scores and applies time decay on startup. Audit Trail Logger records every tool call in JSONL format. Risk Category Mapper classifies tool calls into `low / medium / high / critical`. Tool Profile Engine enforces phase-specific tool restrictions structurally.

**Execution Layer** — Three bash scripts that integrate directly with the Claude Code hooks API: `pre-tool-use.sh`, `post-tool-use.sh`, and `stop.sh`.

---

## Prerequisites

- Linux (bash + standard Unix tools)
- `jq` >= 1.6 (for JSON processing; `walk` function required)
- Claude Code (hooks API support required)

No external package installation is required beyond these.

---

## Installation

```bash
git clone https://github.com/sougetuOte/oath-harness.git
cd oath-harness
bash install/install.sh
```

The installer registers the hooks in your Claude Code project configuration (`.claude/settings.json`) and creates the required state and audit directories.

---

## Usage

After installation, hooks fire automatically on every tool call. No manual invocation is needed.

### Phase Switching

oath-harness enforces different tool restrictions per development phase. Switch phases using slash commands in your Claude Code session:

| Command | Phase | Restrictions |
|---------|-------|-------------|
| `/planning` | PLANNING | `shell_exec` blocked, `src/` writes blocked, only `docs/` writes permitted |
| `/building` | BUILDING | `git_remote` blocked, `shell_exec` and `git_local` require trust gating |
| `/auditing` | AUDITING | `file_write`, `shell_exec`, all Git writes blocked — read-only mode |

Phase restrictions are enforced by the Tool Profile Engine at the hooks level, not through prompt instructions. The current phase is written to `.claude/current-phase.md`.

When the phase is unknown or unset, oath-harness applies the most restrictive profile (equivalent to AUDITING) as a safe default.

---

## oath CLI

oath-harness includes a status visualization CLI. No installation beyond the harness itself is required.

```bash
bin/oath                      # Trust score summary
bin/oath status file_read     # Domain detail with autonomy estimates
bin/oath audit --tail 20      # Recent audit log entries
bin/oath config               # Current configuration values
bin/oath phase                # Current execution phase
bin/oath demo                 # Run all commands with sample data
```

`oath demo` generates realistic sample data and runs every subcommand, useful for evaluating output without a live session.

---

## Checking Trust Scores

Trust scores are persisted between sessions in `state/trust-scores.json`:

```bash
cat state/trust-scores.json | jq .
```

Example output:

```json
{
  "version": "2",
  "updated_at": "2026-02-23T10:00:00Z",
  "global_operation_count": 47,
  "domains": {
    "file_read": {
      "score": 0.82,
      "successes": 34,
      "failures": 1,
      "total_operations": 35,
      "last_operated_at": "2026-02-23T09:55:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": 0.51,
      "successes": 9,
      "failures": 2,
      "total_operations": 11,
      "last_operated_at": "2026-02-23T09:30:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
```

Score constraints enforced at write time: `initial_score` cannot exceed 0.5 (safe default enforcement), and scores cannot be directly set to 1.0 via configuration override.

---

## Checking the Audit Trail

Every tool call is recorded to a daily JSONL file:

```bash
cat audit/$(date +%Y-%m-%d).jsonl | jq .
```

Each entry includes the tool name, arguments (with sensitive values masked), domain, risk category, trust score before and after, the autonomy score, and the final decision. This provides full visibility into why a given operation was approved, flagged, or blocked.

---

## Configuration

Key parameters in `config/settings.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `trust.initial_score` | `0.3` | Starting score for any new domain (max 0.5 enforced) |
| `trust.hibernation_days` | `14` | Days before time decay begins after last use |
| `trust.boost_threshold` | `20` | Number of operations in the initial boost period |
| `trust.warmup_operations` | `5` | Operations at 2x boost speed after returning from hibernation |
| `trust.failure_decay` | `0.85` | Multiplier applied on failure (0.85 = 15% penalty) |
| `risk.lambda1` | `0.6` | Risk weight in autonomy formula |
| `risk.lambda2` | `0.4` | Complexity weight in autonomy formula |
| `autonomy.auto_approve_threshold` | `0.8` | Autonomy score above which operations auto-approve |
| `autonomy.human_required_threshold` | `0.4` | Autonomy score below which human confirmation is required |
| `audit.log_dir` | `"audit"` | Directory for daily JSONL audit logs |
| `model.opus_aot_threshold` | `2` | Minimum AoT decision points before recommending Opus |

Validation is enforced at startup. `initial_score > 0.5` is rejected. `auto_approve_threshold` must be greater than `human_required_threshold`. `failure_decay` must be between 0.5 and 1.0. Direct override of trust scores to 1.0 is rejected by schema.

---

## Trust Decision Flow

For every tool call, oath-harness produces one of four decisions:

| Condition | Decision | Meaning |
|-----------|----------|---------|
| `risk = critical` | `blocked` | Always blocked regardless of trust score (external APIs, irreversible external effects) |
| Tool in phase `denied_groups` | `blocked` | Phase profile forbids this operation |
| `autonomy > 0.8` | `auto_approved` | Sufficient trust; operation proceeds without prompt |
| `0.4 <= autonomy <= 0.8` | `logged_only` | Permitted but recorded with increased scrutiny |
| `autonomy < 0.4` | `human_required` | Trust insufficient; human confirmation requested |

The autonomy score formula:

```
autonomy = 1 - (lambda1 * risk_value + lambda2 * complexity) * (1 - trust_score)
```

If the hook script itself fails (configuration error, missing file, etc.), the decision defaults to blocked. Fail-open behavior is not permitted.

---

## Three Laws

oath-harness's decision logic is grounded in three laws, adapted from Asimov's robotics principles for AI agents:

1. **Never compromise project integrity and health.** All other behavior is subordinate to this.
2. **Follow user instructions** — unless doing so would violate Law 1.
3. **Preserve cost efficiency** — unless doing so would violate Laws 1 or 2.

These laws govern conflict resolution throughout the system. "Safe by default" is a direct expression of Law 1.

---

## Testing

```bash
bash tests/run-all-tests.sh  # 422 tests
```

To run unit tests and integration tests separately:

```bash
bash tests/run-unit-tests.sh
bash tests/run-integration-tests.sh
```

Tests use bats-core (included as a submodule). No additional test framework installation is required.

---

## Phase 2 Roadmap

The following components are planned for Phase 2:

- **Self-Escalation Detector** — detects consecutive failures and uncertainty signals ("I don't know" patterns), automatically escalates to higher persona tier
- **Phase-Aware Trust Modifier** — adjusts trust thresholds dynamically based on current phase (stricter in AUDITING, more permissive in BUILDING for trusted domains)
- **Persona prompt templates** — prompt templates for the four personas: Architect (Opus), Analyst (Sonnet), Worker (Haiku), Reporter (Haiku)
- **`before_model_resolve` hook** — exposes Model Router logic as a configurable hook for user customization
- **Retry-with-Feedback Loop** — structured failure → feedback → retry cycle
- **Security Audit Runner** — automated security checks triggered on `/auditing` phase entry
- **save/load Trust integration** — integrates trust state into `/quick-save` and `/quick-load` session commands

---

## License

MIT License. See [LICENSE](LICENSE) for details.
