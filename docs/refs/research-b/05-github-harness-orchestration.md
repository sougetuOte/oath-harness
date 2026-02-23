# GitHub Research: Agent Harness & Orchestration Frameworks

**Date**: 2026-02-23
**Scope**: Agent harness implementations, guardrails-by-construction, workflow engines, hook-based control, sandboxing, meta-agent frameworks
**Method**: GitHub API, web search, repository analysis

---

## Table of Contents

1. [Agent Harness Implementations](#1-agent-harness-implementations)
2. [Guardrails-by-Construction](#2-guardrails-by-construction)
3. [Agent Workflow Engines with Variable HITL](#3-agent-workflow-engines-with-variable-hitl)
4. [Hook-Based Agent Control](#4-hook-based-agent-control)
5. [Agent Sandboxing](#5-agent-sandboxing)
6. [Meta-Agent / Agent-of-Agents Frameworks](#6-meta-agent--agent-of-agents-frameworks)
7. [OS-Kernel-Inspired Safety Enforcement](#7-os-kernel-inspired-safety-enforcement)
8. [Ralph Wiggum Ecosystem](#8-ralph-wiggum-ecosystem)
9. [Claude Code Ecosystem](#9-claude-code-ecosystem)
10. [Gap Analysis: Existing vs. Trust Engine + Harness + Guardrails Vision](#10-gap-analysis)

---

## 1. Agent Harness Implementations

### 1.1 Deep Agents (LangChain)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/langchain-ai/deepagents |
| Stars | 9,484 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |
| Top Contributors | mdrxy (233), eyurtsev (142), vtrivedy (63), hwchase17 (40) |

**Self-described as "The batteries-included agent harness."** This is the most direct match for the harness pattern in the entire ecosystem.

**Architecture & Key Decisions**:
- Built on LangGraph; `create_deep_agent()` returns a compiled LangGraph graph
- Planning via `write_todos` tool for task breakdown and progress tracking
- Filesystem backend: `read_file`, `write_file`, `edit_file`, `ls`, `glob`, `grep`
- Shell access via `execute` (with sandboxing)
- Sub-agents via `task` tool for delegating work with isolated context windows
- Auto-summarization when conversations grow long; large outputs saved to files
- Smart defaults in prompts that teach the model how to use tools effectively
- CLI adds: conversation resume, web search, remote sandboxes (Modal, Runloop, Daytona), persistent memory, custom skills, headless mode, human-in-the-loop approval

**Security Model**: "Trust the LLM" -- explicitly states that boundaries should be enforced at the tool/sandbox level, not by expecting the model to self-police.

**Contribution**: Fully open, MIT licensed, LangChain community. Provider agnostic (Claude, OpenAI, Google).

**Relevance to LAM**: High. This is the closest existing implementation to the "harness" concept. However, it lacks structured guardrails-by-construction and has no built-in trust engine. Safety is delegated entirely to sandbox/tool boundaries.

---

### 1.2 Langroid

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/langroid/langroid |
| Stars | 3,904 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |
| Top Contributors | pchalasani (2268), Mohannadcse (43), nilspalumbo (21) |

**Architecture & Key Decisions**:
- Explicitly "Harness LLMs with Multi-Agent Programming"
- Actor Framework-inspired: Agents as message transformers
- Agent class encapsulates LLM conversation state + optional vector-store + tools
- Task class wraps Agent, provides orchestration via hierarchical, recursive task-delegation
- `Task.run()` has same type-signature as responder methods, enabling recursive sub-task delegation
- Agents take turns responding in round-robin fashion

**Contribution**: Heavily single-contributor (pchalasani = 2268 of ~2350 commits). Academic origin (CMU/UW-Madison). Open to community but concentrated development.

**Relevance to LAM**: The message-passing and task-delegation architecture is elegant but lacks guardrails infrastructure, quality gates, or trust mechanisms.

---

### 1.3 XAgent (OpenBMB)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/OpenBMB/XAgent |
| Stars | 8,498 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |

**Architecture & Key Decisions**:
- Dispatcher: dynamically instantiates and dispatches tasks to different agents
- Planner: generates and rectifies plans, divides into subtasks with milestones
- Actor: conducts actions using tools, collaborates with humans
- Inner/Outer loop mechanism for iterative refinement
- ToolServer: all actions confined inside Docker containers
- Tools: File Editor, Python Notebook, Web Browser, Shell, Rapid API

**Contribution**: Academic project (Tsinghua University). Open but less active community.

**Relevance to LAM**: The Dispatcher/Planner/Actor decomposition is architecturally interesting. Docker-based tool isolation is genuine sandboxing. However, no trust engine or graduated autonomy.

---

## 2. Guardrails-by-Construction

### 2.1 Parlant (emcie)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/emcie-co/parlant |
| Stars | 17,761 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |
| Top Contributors | mc-dorzo (1910), kichanyurd (1810), MCBarKar (545), MenachemBrichta (372) |

**The strongest "guardrails-by-construction" implementation found.**

**Architecture & Key Decisions**:
- Three-layer decomposition: Policy (Guidelines/Journeys), Tools/Variables, Inference/Model
- Guidelines and journeys are declarative objects -- business logic separated from prompts
- Runtime contextual matching: guidelines and tools relevant to current state are matched and enforced
- Built-in guardrails prevent hallucination and off-topic responses
- Tools as deterministic data sources that can be mocked/swapped
- Runtime compatible with OpenAI/Gemini/Llama -- model-swappable without changing policies
- Parlant 3.0: parallel processing where journey state matching happens in parallel with guideline evaluation (60% latency reduction)

**Contribution**: Active multi-contributor team (emcie company). Open source but company-driven. Healthy contributor distribution.

**Relevance to LAM**: Very high. Parlant's separation of policy from inference is exactly the "guardrails-by-construction" pattern. Its declarative guidelines enable versioning and auditing. The gap: it's focused on conversational agents, not coding agents. No trust escalation or graduated autonomy.

---

### 2.2 NeMo Guardrails (NVIDIA)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/NVIDIA-NeMo/Guardrails |
| Stars | 5,682 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Custom (NVIDIA) |
| Top Contributors | drazvan (1125), schuellc-nvidia (741), Pouyanpi (591) |

**Architecture & Key Decisions**:
- Colang: a custom event-driven interaction modeling language for defining rails
- Colang 2.0 (beta): improved syntax, same core event-driven model
- Five rail types: Input, Dialog, Retrieval, Output, and Execution rails
- Event-driven architecture: user utterance, LLM response, action trigger, action result, guardrail trigger
- Parallel rails execution for performance
- OpenTelemetry tracing infrastructure
- Integration with LangGraph for multi-agent workflows
- Latest: v0.20.0 beta

**Contribution**: NVIDIA-driven, open source but vendor-controlled. Custom license (not standard OSS). Community can contribute but NVIDIA controls direction.

**Relevance to LAM**: High for the guardrails pattern. Colang as a DSL for defining rails is powerful conceptually. The gap: it's primarily for conversational AI, not agent harness workflows. No planning/task-decomposition. Vendor-locked license.

---

### 2.3 Guardrails AI

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/guardrails-ai/guardrails |
| Stars | 6,436 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |
| Top Contributors | CalebCourier (861), zsimjee (672), dtam (265), aaravnavani (198) |

**Architecture & Key Decisions**:
- Input/Output Guards that detect, quantify, and mitigate risks
- Validators for structured output validation
- Hub marketplace for community-contributed validators
- Integration with major LLM providers
- Pydantic-based structured output enforcement

**Contribution**: Open community with healthy contributor distribution. Company-backed (Guardrails AI Inc) but genuinely open.

**Relevance to LAM**: Useful for I/O validation layer but not a harness or orchestration framework. Could be composed into a harness as a validation middleware.

---

### 2.4 Superagent

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/superagent-ai/superagent |
| Stars | 6,414 |
| Last Updated | 2026-02-22 |
| Language | TypeScript |
| License | MIT |
| Top Contributors | homanp (132), alanzabihi (6) |

**Architecture & Key Decisions**:
- Safety Agent pattern: policy enforcement layer evaluating agent actions before execution
- Blocks prompt injections, redacts PII/secrets, scans repos for threats
- Red team scenario testing against agents
- Policies defined declaratively -- security teams express constraints without modifying agent logic
- Actions violating rules can be blocked, modified, or logged

**Contribution**: Heavily single-contributor dominated (homanp). MIT licensed.

**Relevance to LAM**: The Safety Agent as a pre-execution policy enforcement layer is directly relevant. However, it's focused on security scanning rather than being a full harness.

---

## 3. Agent Workflow Engines with Variable HITL

### 3.1 LangGraph

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/langchain-ai/langgraph |
| Stars | 24,940 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |
| Backing | LangChain Inc |

**Architecture & Key Decisions**:
- Graph-based orchestration: nodes (functions/tools/agents), edges (conditional transitions/loops/branches)
- Typed shared state that persists between steps
- Checkpointing: durable snapshots for resume/retry/time-travel
- Human-in-the-loop via interrupt nodes -- pause at approval points, persist state, notify reviewer, resume
- Moderation/quality loops embedded in graph
- Production patterns: checkpointing after every node, idempotent tool calls, strict state validation, bounded retries
- Policy gates for compliance

**Contribution**: LangChain ecosystem, large open community, vendor-backed but MIT licensed.

**Relevance to LAM**: Very high. LangGraph's checkpoint + interrupt + approval pattern is the closest existing implementation to "variable HITL with quality gates." The gap: it's a low-level graph runtime, not an opinionated harness. You build the harness on top of it (as Deep Agents does).

---

### 3.2 Agent Control Plane (HumanLayer)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/humanlayer/agentcontrolplane |
| Stars | 339 |
| Last Updated | 2026-02-22 |
| Language | Go |
| License | Custom |
| Top Contributors | dexhorthy (339), allisoneer (164), balanceiskey (40) |

**Architecture & Key Decisions**:
- Cloud-native orchestrator for AI agents built on Kubernetes
- Designed for "outer-loop" agents that run without supervision
- Asynchronous tool calls including human feedback requests
- Human approval via Slack, email, and other channels
- Full MCP (Model Context Protocol) support
- 12-factor-agents philosophy
- Long-lived agent processes as first-class K8s citizens

**Contribution**: Company-driven (HumanLayer). Small team, custom license. Early stage.

**Relevance to LAM**: The "outer-loop agent with async human approval" pattern is directly relevant. The K8s-native approach is interesting for production deployment. The gap: early stage (339 stars), unclear community trajectory, custom license.

---

### 3.3 CrewAI

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/crewAIInc/crewAI |
| Stars | 44,452 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |

**Architecture**: Role-playing autonomous agents with collaborative intelligence. Crew Control Plane for managing, monitoring, and scaling agents. Focus on task assignment via role definitions.

**Relevance to LAM**: Large community, production-ready. But focused on multi-agent role orchestration rather than harness + guardrails. No structured trust escalation.

---

### 3.4 Haystack (deepset)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/deepset-ai/haystack |
| Stars | 24,258 |
| Last Updated | 2026-02-22 |
| Language | MDX (docs-heavy) |
| License | Apache 2.0 |

**Architecture**: Modular pipelines with explicit control over retrieval, routing, memory, and generation. Component-based design where each component has typed inputs/outputs.

**Relevance to LAM**: Strong pipeline architecture pattern with explicit component interfaces. Relevant for the "typed interfaces between components" aspect of LAM but not focused on agent autonomy or guardrails.

---

## 4. Hook-Based Agent Control

### 4.1 Agno (formerly Phidata)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/agno-agi/agno |
| Stars | 38,092 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |
| Top Contributors | ashpreetbedi (2319), ysolanky (499), dirkbrnd (453) |

**Architecture & Key Decisions**:
- Pre-hooks: execute before model context preparation, before LLM execution
  - Input validation, security checks, data preprocessing
  - Can modify run_input before it reaches LLM
- Post-hooks: execute after response generation, before return to user
  - Output filtering, compliance checks, response enrichment
  - Can modify run_output before delivery
- Tool-level hooks: `pre_hook` and `post_hook` in `@tool` decorator
  - Per-tool or agent-wide hook application
- State management at every execution step
- Guardrails via `pre_hooks` parameter

**Contribution**: Company-driven but large open community. Apache 2.0. Healthy contributor spread.

**Relevance to LAM**: Very high. Agno's hook system is the most comprehensive pre/post hook implementation in the agent framework space. The gap: hooks are structural but not policy-declarative. No trust escalation or graduated autonomy built in.

---

### 4.2 Claude Code Hooks

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/anthropics/claude-code |
| Stars | 68,911 |
| Last Updated | 2026-02-22 |
| Language | Shell |
| License | Proprietary (Anthropic) |

**Hook Architecture**:
- PreToolUse: fires before tool execution, with matcher groups for filtering
- PermissionRequest: fires during permission check
- PostToolUse: fires after successful tool execution
- PostToolUseFailure: fires after failed tool execution
- Hooks are user-defined shell commands or LLM prompts
- Execute automatically at specific lifecycle points

**Plugin Ecosystem**:
- Plugins: custom collections of slash commands, agents, MCP servers, and hooks
- Install with single command
- Community: awesome-claude-code (24,632 stars), hooks-mastery (3,119 stars)
- Plugin marketplace emerging (DevOps automation, documentation generation, testing suites)
- Over 80+ specialized sub-agents catalogued

**Contribution**: Anthropic-controlled core. Community contributes plugins/hooks/skills. Not modifiable at the core level.

**Relevance to LAM**: The hook system is the most production-proven implementation of the pattern. The plugin architecture is extensible. The gap: closed-source core, Anthropic-controlled evolution, hooks are external scripts rather than typed policy definitions.

---

## 5. Agent Sandboxing

### 5.1 Kubernetes Agent Sandbox (K8s SIG)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/kubernetes-sigs/agent-sandbox |
| Stars | 1,039 |
| Last Updated | 2026-02-22 |
| Language | Go |
| License | Apache 2.0 |

**Architecture**: Formal K8s SIG Apps subproject. Standardizes Kubernetes as the secure, scalable platform for agentic workloads. Manages isolated, stateful, singleton workloads for AI agent runtimes.

**Relevance**: Infrastructure-level sandboxing. The right layer for production deployment of sandboxed agents.

---

### 5.2 Sandbox Agent (Rivet)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/rivet-dev/sandbox-agent |
| Stars | 909 |
| Last Updated | 2026-02-22 |
| Language | Rust |
| License | Apache 2.0 |

**Architecture**: HTTP API to control coding agents remotely in sandboxes. Supports Claude Code, Codex, OpenCode, and Amp. Agent-agnostic control plane.

**Relevance**: Directly relevant for running coding agents in isolation with HTTP-based control.

---

### 5.3 Vibekit (Superagent)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/superagent-ai/vibekit |
| Stars | 1,720 |
| Last Updated | 2026-02-22 |
| Language | TypeScript |
| License | MIT |

**Architecture**: Run Claude Code, Gemini, Codex, or any coding agent in isolated sandbox with sensitive data redaction and observability baked in.

**Relevance**: Combines sandboxing with data redaction -- a trust-aware sandbox.

---

### 5.4 Agent Sandbox (Enterprise)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/agent-sandbox/agent-sandbox |
| Stars | 62 |
| Last Updated | 2026-02-22 |
| Language | Go |
| License | Apache 2.0 |

**Architecture**: E2B compatible, enterprise-grade cloud-native runtime. Supports code execution, browser use, computer use, shell commands. Stateful, long-running, multi-session, multi-tenant.

**Relevance**: Enterprise-focused but early stage.

---

## 6. Meta-Agent / Agent-of-Agents Frameworks

### 6.1 MetaGPT

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/FoundationAgents/MetaGPT |
| Stars | 64,364 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |

**Architecture**: Multi-agent framework modeling human procedural knowledge. SOPs (Standard Operating Procedures) as the organizing principle. Agents map to software company roles. AFlow paper (ICLR 2025 oral) for automated agentic workflow generation.

**Contribution**: Academic + community. Very large community (64K stars). Active development.

**Relevance to LAM**: The SOP-based role decomposition is conceptually aligned with LAM's phase-based approach. The gap: MetaGPT is opinionated about software company simulation, not a generic harness with guardrails.

---

### 6.2 AutoGen (Microsoft)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/microsoft/autogen |
| Stars | 54,715 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | CC BY 4.0 |

**Architecture**: Multi-agent conversations with human participation. Agents can act autonomously or alongside humans. Customizable conversation patterns. Code execution in Docker containers.

**Relevance to LAM**: Mature, large community. Flexible HITL support. The gap: no structured trust engine or guardrails-by-construction. CC BY 4.0 license is unusual.

---

### 6.3 Swarms

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/kyegomez/swarms |
| Stars | 5,771 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |

**Architecture**: Enterprise-grade multi-agent orchestration. Multiple swarm topologies (sequential, parallel, hierarchical, mesh). Production-scale deployment focus.

**Relevance**: Enterprise-focused multi-agent patterns. Less relevant to harness+guardrails specifically.

---

### 6.4 AutoAgent (HKUDS)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/HKUDS/AutoAgent |
| Stars | 8,592 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |

**Architecture**: Fully automated, zero-code LLM agent framework. Intelligent resource orchestration. Iterative self-improvement for agent/tool/workflow creation. Supports single agent creation and multi-agent workflow generation.

**Relevance**: Meta-agent that creates other agents. Interesting for automation but orthogonal to trust/guardrails concerns.

---

### 6.5 AgentScope

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/agentscope-ai/agentscope |
| Stars | 16,409 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |

**Architecture**: Production-ready agent framework. Essential abstractions that scale with rising model capability. Built-in finetuning support. Designed to be easy to use at production scale.

**Relevance**: Production-ready focus with good abstractions but not specifically guardrails-oriented.

---

### 6.6 Agent Squad (AWS)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/awslabs/agent-squad |
| Stars | 7,452 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | Apache 2.0 |

**Architecture**: Lightweight framework for orchestrating multiple AI agents with complex conversations. AWS-backed.

**Relevance**: AWS ecosystem integration. Good for multi-agent routing but not harness/guardrails focused.

---

## 7. OS-Kernel-Inspired Safety Enforcement

These represent the most architecturally interesting approach to "guardrails by construction" -- applying proven OS security patterns to agent control.

### 7.1 agentsh

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/canyonroad/agentsh |
| Stars | 35 |
| Last Updated | 2026-02-20 |
| Language | Go |
| License | Apache 2.0 |

**Architecture**: SELinux-inspired execution gateway. Intercepts file, network, and process activity including subprocess trees. Per-operation policy engine with allow/deny/approve(human OK)/soft_delete/redirect. Structured audit events. Runtime enforcement regardless of how work is triggered.

**Relevance to LAM**: Very high conceptual alignment. The allow/deny/approve trichotomy maps directly to trust levels. The subprocess interception means LLM-spawned processes are also governed. Early stage but architecturally sound.

---

### 7.2 agent-os

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/imran-siddique/agent-os |
| Stars | 55 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |

**Architecture**: POSIX-inspired primitives for autonomous AI agents. Kernel-based safety intercepts actions before execution. Policy engine decides (not the LLM). Applications request resources; kernel grants or denies based on permissions. 1,500+ tests. Claims 0% policy violation guarantee.

**Relevance to LAM**: Very high. The "kernel decides, not the LLM" principle is exactly the right separation of concerns. Early stage but the philosophy is sound.

---

### 7.3 TrustAgent

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/agiresearch/TrustAgent |
| Stars | 56 |
| Last Updated | 2026-01-14 |
| Language | Python |

**Architecture**: Three-phase safety: pre-planning (inject safety knowledge), in-planning (enhance safety during plan generation), post-planning (inspection). Agent Constitution approach.

**Relevance to LAM**: The pre/in/post planning safety phases map well to LAM's phase system. Academic research; low maturity.

---

### 7.4 LLM Guard (Protect AI)

| Attribute | Value |
|-----------|-------|
| URL | https://github.com/protectai/llm-guard |
| Stars | 2,566 |
| Last Updated | 2026-02-22 |
| Language | Python |
| License | MIT |

**Architecture**: Security toolkit for LLM interactions. Input/output scanning for threats. Composable scanner pipeline.

**Relevance**: Useful as a component but not a harness or orchestration framework.

---

## 8. Ralph Wiggum Ecosystem

The Ralph Wiggum technique represents autonomous agent loops -- the "AFK" (Away From Keyboard) pattern where agents iterate until task completion.

### 8.1 how-to-ralph-wiggum (Original)

| URL | https://github.com/ghuntley/how-to-ralph-wiggum |
| Stars | 1,339 |
| Concept | Iterative bash loop: run agent, check completion, provide feedback, repeat |

### 8.2 ralph-wiggum (fstandhartinger)

| URL | https://github.com/fstandhartinger/ralph-wiggum |
| Stars | 176 |
| Concept | Combines iterative loop with SpecKit-style specifications for spec-driven development |

### 8.3 ralph-loop-agent (Vercel Labs)

| URL | https://github.com/vercel-labs/ralph-loop-agent |
| Stars | 674 |
| Concept | AI SDK wrapper with feedback loops, runs until `verifyCompletion` confirms success |

**Relevance to LAM**: The Ralph pattern is the opposite extreme from LAM's approach. Ralph is "maximum autonomy, zero guardrails" -- the agent runs unsupervised until done. LAM's value proposition is precisely filling the gap between "fully supervised" and "fully autonomous Ralph loops" with graduated trust.

---

## 9. Claude Code Ecosystem

### 9.1 awesome-claude-code

| URL | https://github.com/hesreallyhim/awesome-claude-code |
| Stars | 24,632 |
| Content | Curated skills, hooks, slash-commands, agent orchestrators, applications, plugins |

### 9.2 claude-code-hooks-mastery

| URL | https://github.com/disler/claude-code-hooks-mastery |
| Stars | 3,119 |
| Content | Comprehensive tutorial on hook lifecycle (PreToolUse, PostToolUse, etc.) |

### 9.3 everything-claude-code

| URL | https://github.com/affaan-m/everything-claude-code |
| Content | Complete configuration collection -- agents, skills, hooks, commands, rules, MCPs |

**Relevance to LAM**: The Claude Code plugin/hooks ecosystem is where LAM's ideas would be implemented if targeting Claude Code as the runtime. The hooks system provides the interception points; LAM would provide the policy logic that makes decisions at those points.

---

## 10. Gap Analysis

### What Exists vs. The Trust Engine + Harness + Guardrails Vision

```
                     Harness  Guardrails  Trust    HITL    Sandbox  Hooks
                     Pattern  by-Constr.  Engine   Grad.   Support  System
                     -------  ----------  ------   -----   -------  ------
Deep Agents           +++       -          -        +        ++      -
Langroid              ++        -          -        -        -       -
LangGraph             +         -          -        +++      -       +
Parlant               +         +++        -        +        -       -
NeMo Guardrails       -         +++        -        -        -       -
Guardrails AI         -         ++         -        -        -       -
Agno                  ++        +          -        +        -       +++
Claude Code           +++       +          -        +        ++      +++
Superagent            -         ++         +        -        -       -
ACP (HumanLayer)      -         -          -        +++      -       -
agentsh               -         +          +        ++       -       -
agent-os              -         ++         +        -        -       -
TrustAgent            -         +          ++       -        -       -
MetaGPT               ++        -          -        -        -       -
CrewAI                ++        -          -        +        -       -

Legend: +++ = core strength, ++ = supported, + = partial, - = absent
```

### Key Gaps Identified

**1. No Unified Trust Engine Exists**
- TrustAgent is the closest to a "trust" concept but is academic and not production-ready (56 stars, research paper)
- agentsh has trust-relevant policy enforcement but no graduated trust levels
- No project implements "earned trust through demonstrated reliability"

**2. Harness + Guardrails = Separate Worlds**
- Deep Agents (best harness) has no guardrails-by-construction
- Parlant (best guardrails) is not a coding agent harness
- NeMo Guardrails is conversational, not agentic-workflow
- No project combines planning + tool use + context management + subagent orchestration WITH declarative policy enforcement

**3. Graduated HITL is Primitive**
- LangGraph supports checkpoints and interrupts but the graduation logic (when to ask vs. when to proceed) must be hand-coded
- ACP provides async human approval but binary (approve/deny), not graduated
- No project implements "trust score that adjusts autonomy level dynamically"

**4. Hook Systems are Structural, Not Policy-Driven**
- Agno and Claude Code have comprehensive hook lifecycle coverage
- But hooks execute shell scripts or Python functions, not declarative policies
- No project combines hooks with a typed policy language (closest: NeMo's Colang, but it's for conversations)

**5. The agentsh/agent-os Pattern is Under-Explored**
- The OS-kernel analogy (intercept -> evaluate policy -> allow/deny/approve) is the most architecturally sound approach
- Both projects are extremely early (35-55 stars)
- No project applies this pattern to a full agent harness with planning, context management, and subagent orchestration

### The Missing Integration

What does NOT exist and would be novel:

```
+--------------------------------------------------+
|               Trust Engine (Dynamic)              |
|  trust_score = f(history, task_risk, phase)       |
|  Adjusts autonomy level per-action               |
+--------------------------------------------------+
         |                    |                 |
    +---------+        +-----------+     +----------+
    | Harness |        | Guardrails|     | Sandbox  |
    | (Deep   |  <-->  | (Parlant- |     | (K8s/    |
    | Agents  |        |  style    |     | Docker)  |
    | pattern)|        |  policies)|     |          |
    +---------+        +-----------+     +----------+
         |                    |                 |
    +---------+        +-----------+     +----------+
    | Hooks   |        | Colang-   |     | OS-level |
    | (Agno/  |        | style DSL |     | intercept|
    | Claude  |        | for agent |     | (agentsh |
    | style)  |        | workflows |     |  pattern)|
    +---------+        +-----------+     +----------+
```

This integration -- a trust-aware agent harness with declarative policy guardrails and kernel-level enforcement -- does not exist in any single project. The LAM project could fill this gap.

---

## Summary by Relevance to LAM

### Tier 1: Directly Relevant Architecture Patterns
| Project | What to Learn |
|---------|---------------|
| **Deep Agents** | Harness pattern, tool structure, context management, sub-agent delegation |
| **Parlant** | Declarative policy separation, guardrails-by-construction, three-layer architecture |
| **LangGraph** | Checkpointing, interrupt/resume, quality gates, graph-based orchestration |
| **Agno** | Pre/post hooks at agent and tool level, lifecycle interception |
| **agentsh** | OS-kernel policy enforcement, allow/deny/approve pattern |

### Tier 2: Useful Components or Concepts
| Project | What to Learn |
|---------|---------------|
| **Claude Code hooks** | Production-proven hook lifecycle, plugin ecosystem |
| **NeMo Guardrails** | Colang DSL for defining rails, event-driven guardrail architecture |
| **Superagent** | Safety Agent as policy enforcement layer |
| **K8s agent-sandbox** | Production-grade agent isolation on Kubernetes |
| **TrustAgent** | Pre/in/post planning safety phases |
| **agent-os** | POSIX-inspired primitives, "kernel decides not LLM" philosophy |

### Tier 3: Ecosystem Context
| Project | Significance |
|---------|-------------|
| **MetaGPT** (64K stars) | Dominant multi-agent framework; SOP-based decomposition |
| **AutoGen** (55K stars) | Microsoft-backed; broad multi-agent conversations |
| **CrewAI** (44K stars) | Popular role-based agent orchestration |
| **Claude Code** (69K stars) | The runtime LAM is most likely to target |
| **Ralph Wiggum** | The "fully autonomous" extreme that LAM's graduated trust improves upon |

---

*Research conducted 2026-02-23. Star counts and update dates reflect GitHub state at time of research.*
