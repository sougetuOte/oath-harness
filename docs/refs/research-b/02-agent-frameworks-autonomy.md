# Research Memo: Agent Frameworks -- Autonomy Control & Quality Gates (2025-2026)

**Date**: 2026-02-23
**Scope**: Design patterns for balancing AI agent autonomy with human oversight
**Status**: Research complete

---

## 1. LangGraph (LangChain) -- Checkpoint-Based Agent Control

### Architecture

LangGraph models agent workflows as **state graphs** where nodes are computation steps and edges define transitions. The core autonomy control mechanism is the **checkpointer** -- a persistence layer that saves graph state at every super-step, enabling interrupt/resume, human-in-the-loop (HITL), time-travel debugging, and fault-tolerance.

### Human-in-the-Loop Patterns

LangGraph supports two HITL approaches:

| Pattern | Mechanism | Use Case |
|---------|-----------|----------|
| **Static Interrupt** | `interrupt_before` / `interrupt_after` parameters on nodes | Predetermined approval gates |
| **Dynamic Interrupt** | `interrupt()` function called within a node based on current state | Conditional, state-dependent gates |

When an interrupt fires, the human receives three options:
- **Approve**: proceed as-is
- **Edit**: modify the proposed action before execution
- **Reject**: reject with feedback, causing the agent to re-plan

### Checkpoint Persistence

Each checkpoint is scoped to a **thread** (unique `thread_id`). Checkpointer backends include:
- `InMemorySaver` (prototyping)
- `AsyncPostgresSaver` (production)
- `AsyncSqliteSaver`, DynamoDB, Redis, Snowflake, Couchbase (community)

On node failure, LangGraph stores pending writes from successfully completed nodes at that superstep, so successful work is not re-executed on resume.

### Key Design Insight

Adding just two checkpoints can transform a fully autonomous workflow into a collaborative one. The agent retains heavy-lifting responsibility (query generation, search, synthesis) while humans intervene at judgment points.

### Sources

- [LangChain Human-in-the-Loop Docs](https://docs.langchain.com/oss/python/langchain/human-in-the-loop)
- [LangGraph 201: Adding Human Oversight (Towards Data Science)](https://towardsdatascience.com/langgraph-201-adding-human-oversight-to-your-deep-research-agent/)
- [LangGraph Persistence Docs](https://docs.langchain.com/oss/python/langgraph/persistence)
- [Build Durable AI Agents with LangGraph and DynamoDB (AWS)](https://aws.amazon.com/blogs/database/build-durable-ai-agents-with-langgraph-and-amazon-dynamodb/)
- [MarkTechPost: Plan-and-Execute with LangGraph and Streamlit (Feb 2026)](https://www.marktechpost.com/2026/02/16/how-to-build-human-in-the-loop-plan-and-execute-ai-agents-with-explicit-user-approval-using-langgraph-and-streamlit/)

---

## 2. CrewAI -- Task-Level Guardrails with Retry

### Architecture

CrewAI organizes work as **Crews** of **Agents** executing **Tasks**. Autonomy control is implemented at the task boundary through **task guardrails** -- validation checks that run immediately after an agent completes a task's output.

### Guardrail Types

| Type | Mechanism | Characteristics |
|------|-----------|-----------------|
| **Function-based** | Python functions with custom validation logic | Deterministic, full control |
| **LLM-based** | Natural language criteria evaluated by the agent's LLM | Flexible, semantic validation |

### Validation & Retry Flow

```
Agent executes task
  -> Guardrail activates, receives output
    -> Pass: (True, validated_result) -> workflow continues
    -> Fail: (False, "error message") -> retry or halt
```

Retry behavior is controlled via `guardrail_max_retries` (the older `max_retries` attribute is deprecated as of v1.0.0). Retry intervals and custom error messages are configurable.

### What Guardrails Validate

- Output length, format, and structure
- Presence/absence of specific keywords or patterns
- Tone and quality thresholds
- Hallucination detection (CrewAI Enterprise feature, out-of-box)

### Key Design Insight

CrewAI treats guardrails as **course-correction**: if the agent drifts, the guardrail forces a retry rather than halting the entire workflow. This creates a self-healing loop at the task level. No-code guardrail creation was recently added to simplify configuration.

### Sources

- [CrewAI Tasks Documentation](https://docs.crewai.com/en/concepts/tasks)
- [Analytics Vidhya: Introduction to Task Guardrails in CrewAI](https://www.analyticsvidhya.com/blog/2025/11/introduction-to-task-guardrails-in-crewai/)
- [Towards Data Science: How to Implement Guardrails with CrewAI](https://towardsdatascience.com/how-to-implement-guardrails-for-your-ai-agents-with-crewai-80b8cb55fa43/)
- [CrewAI Guardrails PR #1742](https://github.com/crewAIInc/crewAI/pull/1742)

---

## 3. Microsoft AutoGen / Agent Framework -- Enterprise Governance

### Evolution: AutoGen to Microsoft Agent Framework

Microsoft Agent Framework entered **public preview** on October 1, 2025, merging AutoGen's dynamic multi-agent orchestration with Semantic Kernel's production foundations. AutoGen and Semantic Kernel are now in **maintenance mode** (bug fixes and security patches only). GA target: end of Q1 2026.

### Governance Architecture

At Ignite 2025, Microsoft introduced **agent-level guardrails** in Microsoft Foundry Control Plane:

- **Content filters** (renamed "guardrails") can now be applied at the agent level, not just model deployments
- **Foundry Control Plane** governs any agent in one place regardless of where it was built
- Controls cover: task adherence, sensitive data detection (PII), groundedness, prompt injection mitigation

### Enterprise Features

| Capability | Description |
|------------|-------------|
| **Agent Identity** | Each agent receives a Microsoft Entra Agent ID for identity, lineage, and access governance |
| **Model Router** | Mix and match models (Claude, GPT, custom) with unified governance, no code changes |
| **Observability** | OpenTelemetry-based tracing, continuous red teaming, Azure Monitor integration (GA) |
| **Prompt Shields** | Spotlighting-based protection against prompt injection |
| **Multi-agent Orchestration** | Persistent state, error recovery, context sharing across agents |

### Key Design Insight

Microsoft's approach treats governance as a **platform concern**, not an agent concern. The Control Plane provides a single pane of glass for all agents regardless of framework origin. This architectural separation means agents don't need to implement their own governance -- it's imposed externally.

### Sources

- [Microsoft Agent Framework Overview (Microsoft Learn)](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)
- [VentureBeat: Microsoft Retires AutoGen, Debuts Agent Framework](https://venturebeat.com/ai/microsoft-retires-autogen-and-debuts-agent-framework-to-unify-and-govern)
- [What's New in Microsoft Foundry (Oct/Nov 2025)](https://devblogs.microsoft.com/foundry/whats-new-in-microsoft-foundry-oct-nov-2025/)
- [Governance and Security for AI Agents (Cloud Adoption Framework)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ai-agents/governance-security-across-organization)
- [Foundry Agent Service at Ignite 2025](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-agent-service-at-ignite-2025-simple-to-build-powerful-to-deploy-trusted-/4469788)

---

## 4. Claude Code / Anthropic -- Layered Permission & Hook System

### Permission Architecture

Claude Code implements a **three-tier permission rule system** evaluated in strict order:

```
1. Deny rules  -> block regardless of other rules
2. Allow rules -> permit if matched
3. Ask rules   -> prompt user for approval
```

Permissions are configured in `settings.json` with pattern matching:
- Allow: `Bash(npm run lint)`, `Bash(npm run test:*)`, `Read(~/.zshrc)`
- Deny: `Bash(curl:*)`, `Read(./.env)`, `Read(./secrets/**)`

### Autonomous Execution Modes

| Mode | Flag | Use Case |
|------|------|----------|
| Interactive | (default) | Human approves each sensitive action |
| Headless | `claude -p "prompt"` | CI/CD pipelines, scripted workflows |
| Full Autonomous | `--dangerously-skip-permissions` | Sandboxed environments only |

Anthropic reports that sandboxing reduces permission prompts by **84%** while maintaining security.

### Hooks System (14 Lifecycle Events as of Feb 2026)

Claude Code hooks are the primary mechanism for **deterministic quality gates**:

| Event | Timing | Use Case |
|-------|--------|----------|
| `PreToolUse` | Before tool execution | Input validation, sandboxing, security enforcement |
| `PostToolUse` | After tool completion | Output validation, logging |
| `Stop` | Agent finishes responding | Autonomous re-prompting (Ralph Wiggum pattern) |
| `UserPromptSubmit` | User submits prompt | Input filtering, routing |
| `Notification` | Permission/idle prompts | Desktop notifications, monitoring |
| `SessionStart/End` | Session lifecycle | State management |
| `PreCompact` | Before context compaction | State preservation |

Three handler types:
- **Command hooks**: shell commands for deterministic checks
- **Prompt hooks**: LLM-based semantic evaluation
- **Agent hooks**: deep analysis with tool access (sub-agents)

Since v2.0.10, `PreToolUse` hooks can **modify tool inputs** before execution, enabling transparent correction rather than blocking.

### Ralph Wiggum Plugin -- Autonomous Iteration Loop

The Ralph Wiggum plugin is an **official Anthropic plugin** that implements autonomous iteration:
- A `Stop` hook intercepts session exit and re-feeds the original prompt
- Each iteration sees modified files and git history from prior runs
- Claude reads its own past work as learning data
- Safety net: `--max-iterations` parameter
- Cost consideration: 50-iteration loop on a large codebase can cost $50-100+ in API credits

### Key Design Insight

Anthropic's approach is **layered defense**: sandboxing at the OS level, deny/allow/ask rules at the permission level, hooks at the workflow level. The hooks system's three handler types (command/prompt/agent) map naturally to different quality gate requirements -- deterministic checks, semantic evaluation, and deep analysis.

### Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Security](https://code.claude.com/docs/en/security)
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [Anthropic: Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)
- [Claude Agent SDK Permissions](https://platform.claude.com/docs/en/agent-sdk/permissions)
- [Ralph Wiggum Plugin (GitHub)](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [Claude Code Hooks Guide (Feb 2026)](https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)
- [Claude Code Hooks: 20+ Examples (aiorg.dev)](https://aiorg.dev/blog/claude-code-hooks)

---

## 5. OpenAI Codex & Agents SDK -- Sandboxed Autonomy with Parallel Guardrails

### Codex Agent Architecture

OpenAI Codex operates in two modes:
- **Codex CLI**: local agent-style coding with iterative review and human oversight
- **Codex Cloud**: isolated sandbox with internet disabled, full autonomy within the sandbox

The cloud agent edits files, runs commands, and executes tests without supervision, but the sandbox is the guardrail -- the agent cannot affect the outside world.

### OpenAI Agents SDK (March 2025)

The Agents SDK is a lightweight, provider-agnostic framework with four pillars:

| Pillar | Description |
|--------|-------------|
| **Guardrails** | Input, output, and tool guardrails with parallel or blocking execution |
| **Handoffs** | Multi-agent delegation and coordination |
| **Tracing** | Built-in comprehensive event recording |
| **Tool Use** | Auto-schema generation with Pydantic validation |

Guardrail execution modes:
- **Parallel** (`run_in_parallel=True`, default): guardrail and agent run simultaneously; fail-fast on tripwire
- **Blocking** (`run_in_parallel=False`): guardrail completes before agent starts; prevents token consumption on failure

Smart approvals are enabled by default for MCP tool calls. Multi-agent has max-depth guardrails to prevent runaway delegation chains.

### Devin (Cognition AI) and Competing Tools

Devin operates as a fully autonomous software engineer but the industry consensus as of 2025-2026 is that **human oversight remains essential**:
- Policy controls: approved task types (bug fixes, docs, small features) vs. disallowed (schema migrations, prod config)
- Least privilege: start read-only, elevate to write only when necessary
- All AI-generated code must undergo human review before merge
- Static analysis (SAST) and dynamic analysis (DAST) augment human review

### Key Design Insight

OpenAI's approach with Codex uses **containment as the primary guardrail** (sandbox with no network), while the Agents SDK uses **parallel validation** (guardrails run alongside agent execution for minimal latency). The tension in autonomous coding tools remains: the purpose is to reduce human involvement, but reliability is not yet sufficient for unsupervised operation.

### Sources

- [OpenAI Codex](https://developers.openai.com/codex)
- [Introducing Upgrades to Codex](https://openai.com/index/introducing-upgrades-to-codex/)
- [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/)
- [OpenAI Agents SDK Guardrails](https://openai.github.io/openai-agents-python/guardrails/)
- [OpenAI Agents SDK Tracing](https://openai.github.io/openai-agents-python/tracing/)
- [Pillar Security: Hidden Risks of SWE Agents](https://www.pillar.security/blog/the-hidden-security-risks-of-swe-agents-like-openai-codex-and-devin-ai)

---

## 6. Adaptive / Variable Autonomy -- Emerging Patterns

### Autonomy Level Taxonomy

The industry is converging on a multi-level autonomy model:

| Level | Name | Characteristics |
|-------|------|-----------------|
| 0 | Fixed GenAI | Static behavior, no agency |
| 1 | Rules-based | Deterministic automation |
| 2 | Workflow | Predefined actions, dynamic sequencing |
| 3 | Partially Autonomous | Planning, execution, adaptation with minimal oversight |
| 4 | Fully Autonomous | Self-directed goals, learning from outcomes |

Higher autonomy increases capability but also increases complexity and security risk, as behavior becomes harder to predict and audit.

### Supervised Autonomy Pattern (2026 Breakthrough Concept)

"Supervised Autonomy" has emerged as a key architectural pattern:

> **Core Principle**: AI systems operating on probabilistic problems must include human checkpoints -- not as a fallback, but as a core design requirement.

Rationale:
- LLMs are inherently non-deterministic
- Text generation is statistically plausible, not factually verified
- A 15% error rate may be acceptable for drafts but is unacceptable for production without review

The pattern goes beyond simple approval gates:
- Agents handle **routine cases autonomously**
- **Edge cases** are flagged for human review
- Humans focus on **judgment, exceptions, and policy interpretation**
- Rules and escalation criteria are **adjusted over time** based on auditing

### Bounded Autonomy Architecture

Leading organizations implement "bounded autonomy" with:
1. **Clear operational limits** per agent or task type
2. **Escalation paths** to humans for high-stakes decisions
3. **Comprehensive audit trails** of all agent actions
4. **Dynamic role assignment** and memory sharing across agents

### Governance as Architecture (Not Afterthought)

A critical 2026 realization: governance cannot be "added later" to autonomous systems. It must be baked into the agent framework from the start. The shift is from viewing governance as compliance overhead to recognizing it as an **enabler** -- mature governance frameworks increase organizational confidence to deploy agents in higher-value scenarios.

### Maturity Gap

Fewer than 25% of organizations deploying agentic AI have implemented formal agent monitoring or escalation protocols, despite agents being projected to handle 15% of work decisions autonomously by 2026. This gap between deployment and governance represents a significant risk.

### Sources

- [Supervised Autonomy: The AI Framework for 2026 (Medium)](https://edge-case.medium.com/supervised-autonomy-the-ai-framework-everyone-will-be-talking-about-in-2026-fe6c1350ab76)
- [Agentic AI Design Patterns 2026 Edition (Medium)](https://medium.com/@dewasheesh.rana/agentic-ai-design-patterns-2026-ed-e3a5125162c5)
- [The 2026 Guide to Agentic Workflow Architectures (Stack AI)](https://www.stack-ai.com/blog/the-2026-guide-to-agentic-workflow-architectures)
- [AI in 2026: Predictions Mapped to Agentic AI Maturity Model](https://dr-arsanjani.medium.com/ai-in-2026-predictions-mapped-to-the-agentic-ai-maturity-model-c6f851a40ef5)
- [IMDA: Model AI Governance Framework for Agentic AI](https://www.imda.gov.sg/-/media/imda/files/about/emerging-tech-and-research/artificial-intelligence/mgf-for-agentic-ai.pdf)
- [AWS: Agentic AI Security Scoping Matrix](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/)
- [Palo Alto Networks: 2026 Predictions for Autonomous AI](https://www.paloaltonetworks.com/2025/11/2026-predictions-for-autonomous-ai/)

---

## Cross-Framework Comparison

### Autonomy Control Mechanisms

| Framework | Primary Mechanism | Granularity | Persistence |
|-----------|-------------------|-------------|-------------|
| **LangGraph** | Checkpoint + interrupt | Graph node level | Thread-scoped, DB-backed |
| **CrewAI** | Task guardrails + retry | Task output level | In-memory |
| **MS Agent Framework** | Control Plane guardrails | Agent level (platform) | Entra ID, Azure Monitor |
| **Claude Code** | Deny/Allow/Ask + hooks | Tool call level | Session-scoped |
| **OpenAI Agents SDK** | Parallel guardrails + sandbox | Input/output/tool level | Trace-backed |

### Quality Gate Patterns

| Pattern | Used By | Description |
|---------|---------|-------------|
| **Checkpoint-interrupt** | LangGraph | Pause execution at graph nodes, persist state, resume after human review |
| **Output validation + retry** | CrewAI | Validate task output, auto-retry on failure |
| **Platform-level governance** | MS Agent Framework | External control plane applies guardrails across all agents |
| **Layered defense** | Claude Code | OS sandbox + permission rules + lifecycle hooks |
| **Parallel validation** | OpenAI Agents SDK | Guardrails execute alongside agent for fail-fast with minimal latency |
| **Containment** | OpenAI Codex | Sandbox with no network as primary guardrail |
| **Autonomous iteration** | Claude Code (Ralph Wiggum) | Stop-hook re-prompting loop with iteration limits |

### Emerging Architectural Principles (2026)

1. **Governance is architectural, not optional**: Cannot be retrofitted; must be designed in from the start.
2. **Supervised autonomy > full autonomy**: Human checkpoints are core design requirements, not fallbacks.
3. **Containment + validation**: Best results combine environmental isolation (sandboxing) with semantic validation (guardrails).
4. **Escalation over halting**: Prefer routing to humans over stopping the workflow entirely.
5. **Observability is non-negotiable**: Tracing, audit trails, and monitoring are baseline requirements for any autonomous system.
6. **Least privilege by default**: Start with minimal permissions, elevate only when justified.

---

## Relevance to Living Architect Model

The Living Architect Model's existing design aligns well with the industry direction:

| LAM Feature | Industry Equivalent |
|-------------|-------------------|
| Phase gates (planning/building/auditing) | Supervised autonomy checkpoints |
| Allow/Deny command lists | Claude Code permission rules |
| Three Agents Model (Affirmative/Critical/Mediator) | Multi-agent debate for quality control |
| Approval gates between sub-phases | LangGraph interrupt_before/after pattern |
| Spec-before-code requirement | Bounded autonomy with clear operational limits |

Potential enhancement areas based on this research:
- **Adaptive autonomy**: Dynamically adjust oversight level based on task risk/complexity (currently fixed per phase)
- **Retry with feedback**: CrewAI-style guardrail retry loops for building phase quality gates
- **Parallel validation**: Running quality checks alongside execution rather than sequentially
- **Tracing/observability**: Structured audit trails beyond session state files
