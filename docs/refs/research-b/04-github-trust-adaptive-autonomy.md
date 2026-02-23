# GitHub Survey: Trust-Based & Adaptive Autonomy for AI Agents

**Date**: 2026-02-23
**Scope**: GitHub repositories implementing adaptive autonomy, trust engines, earned autonomy, variable autonomy, and supervised autonomy patterns for AI agents.

---

## Executive Summary

There is **no single dominant open-source project** that implements the full vision of dynamically adjusting AI agent autonomy based on a mathematical trust/performance model (e.g., SOC trust-autonomy formula). Instead, the landscape is fragmented across several categories:

1. **Static autonomy levels** (readonly / supervised / full) -- most common pattern
2. **Approval-gate architectures** (human-in-the-loop at decision points)
3. **Risk-scoring middleware** (evaluate each action's risk, route to human if threshold exceeded)
4. **Guardrail frameworks** (input/output filtering, not autonomy adjustment)
5. **Trust research** (academic, measuring trust behavior rather than controlling autonomy)

The closest implementations to a "dynamic trust-driven autonomy" system are **OwnPilot** (5 autonomy levels + risk scoring), **mcp-human-loop** (multi-dimensional scoring gates), and the **AURA** academic framework. None are production-mature with a full feedback loop.

---

## Category 1: Agent Harness / Control Plane Systems

### 1.1 HumanLayer / Agent Control Plane (ACP)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/humanlayer/agentcontrolplane |
| **Stars** | 339 |
| **Language** | Go |
| **Last Updated** | 2025-07-02 |
| **Source** | Company (HumanLayer) |
| **Maturity** | Early production |

**What it does**: Distributed agent scheduler for outer-loop agents. Agents run without supervision but can make asynchronous tool calls requesting human feedback on key operations. Built on Kubernetes, full MCP support.

**Architecture**: Cloud-native, YAML-defined agents. Entire call stack expressed as rolling context window. No separate execution state -- simple, auditable. Long-lived agents with durable task execution.

**Relevance to Adaptive Autonomy**: Provides the *infrastructure* for human-in-the-loop but does **not** dynamically adjust autonomy levels. The agent always has the same capabilities; humans are consulted on specific tool calls.

**Related**: [humanlayer/humanlayer](https://github.com/humanlayer/humanlayer) (9,434 stars) -- the coding agent product built on this foundation.

---

### 1.2 LangChain DeepAgents

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/langchain-ai/deepagents |
| **Stars** | 9,484 |
| **Language** | Python |
| **Last Updated** | 2026-02-21 |
| **Source** | Company (LangChain) |
| **Maturity** | Production |

**What it does**: Agent harness built on LangChain/LangGraph. Equipped with planning, filesystem backend, sub-agent spawning, and context management. Provider-agnostic (Claude, OpenAI, Google, etc.).

**Architecture**: Monorepo with core SDK, CLI, Agent Client Protocol integration, and sandbox integrations (Modal, Runloop, Daytona). CLI adds human-in-the-loop approval, persistent memory, custom skills.

**Relevance to Adaptive Autonomy**: Has human-in-the-loop approval mode but no dynamic trust scoring. The "harness" concept is relevant -- it wraps agents with controls. However, autonomy level is static (configured, not earned).

---

### 1.3 Dapr Agents

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/dapr/dapr-agents |
| **Stars** | 618 |
| **Language** | Python |
| **Last Updated** | 2026-02-17 |
| **Source** | Company (Microsoft / CNCF) |
| **Maturity** | Early production |

**What it does**: Production-grade agent framework built on battle-tested Dapr runtime. Agents reason, act, and collaborate using LLMs with built-in observability, stateful workflow execution, and resilience guarantees.

**Architecture**: Durable-execution workflow engine guaranteeing task completion through failures. mTLS encryption, OAuth2/OIDC, access control, secret management. Kubernetes-native.

**Relevance to Adaptive Autonomy**: Strong on infrastructure (security, resilience, observability) but autonomy level is not dynamically adjusted. No trust scoring or adaptive permissions.

---

## Category 2: Variable / Tiered Autonomy Implementations

### 2.1 OwnPilot -- 5 Autonomy Levels + Risk Scoring

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/ownpilot/OwnPilot |
| **Stars** | 95 |
| **Language** | TypeScript |
| **Last Updated** | 2026-02-22 |
| **Source** | Individual / Community |
| **Maturity** | Early prototype |

**What it does**: Privacy-first personal AI assistant with autonomous agents, tool orchestration, and multi-provider support. Implements **5 autonomy levels**: Manual, Assisted, Supervised, Autonomous, Full.

**Key Feature**: Automatic **risk scoring** for tool executions with approval workflows. Security pattern blocking, encrypted personal memory, permissions management.

**Relevance to Adaptive Autonomy**: **Closest match** to the adaptive autonomy concept in a working codebase. Has both tiered autonomy AND risk scoring. However, the autonomy level appears to be user-configured rather than dynamically adjusted based on agent performance history.

**Gap**: No feedback loop -- the system doesn't *learn* to trust the agent more over time.

---

### 2.2 ZeroClaw -- 3 Autonomy Modes (Readonly / Supervised / Full)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/zeroclaw-labs/zeroclaw |
| **Stars** | 17,034 |
| **Language** | Rust |
| **Last Updated** | 2026-02-22 |
| **Source** | Community (fork/rewrite of OpenClaw) |
| **Maturity** | Production |

**What it does**: Ultra-lightweight (3MB binary) autonomous AI assistant. Supports 22 AI providers. Connects to Telegram and Discord. Filesystem sandboxed with null-byte and symlink protection.

**Autonomy Modes**:
- **Readonly**: Inspection and low-risk tasks only
- **Supervised** (default): Human oversight on sensitive actions. Workspace scoping blocks access to sensitive directories. Requires allowlists for command execution
- **Full**: Broader autonomous execution for approved workflows

**Architecture**: Config-driven autonomy (workspace scope, allowed commands, forbidden paths). Static -- once configured, does not change.

**Relevance to Adaptive Autonomy**: Good production reference for implementing autonomy levels, but they are **static** (config file), not dynamic. No trust accumulation or performance-based escalation.

---

### 2.3 Cline -- Granular Auto-Approve with YOLO Mode

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/cline/cline |
| **Stars** | 58,244 |
| **Language** | TypeScript |
| **Last Updated** | 2026-02-22 |
| **Source** | Company (Cline) |
| **Maturity** | Production |

**What it does**: Autonomous coding agent in the IDE. Permission-based execution model where every action (file read/edit, terminal commands, browser, MCP) requires user approval by default.

**Auto-Approve Feature**: Users configure per-category auto-approve (files, commands, browser, MCP). "YOLO Mode" auto-approves everything. Can set API request limits before requiring re-approval.

**Relevance to Adaptive Autonomy**: Implements **user-configured permission tiers** (essentially variable autonomy). However, the adjustment is entirely manual -- the system does not track agent performance or suggest permission changes. Interesting pattern: "safe commands" vs. "commands requiring approval" is a form of risk classification.

---

### 2.4 Athena-Public -- Governed Autonomy with Constitutional Laws

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/winstonkoh87/Athena-Public |
| **Stars** | 359 |
| **Language** | Python |
| **Last Updated** | 2026-02-22 |
| **Source** | Individual |
| **Maturity** | Prototype / experimental |

**What it does**: "Linux OS for AI Agents" giving any LLM persistent memory, autonomy, and time-awareness. State stored in Markdown files on disk. Platform-agnostic.

**Governance**: 6 constitutional laws, 4 capability levels for bounded agency. Structured reasoning protocols. Best with frontier models (Claude Opus, Gemini 3.1 Pro, GPT-5.2).

**Relevance to Adaptive Autonomy**: The "constitutional laws" approach is interesting -- rules that constrain behavior at different capability levels. However, the levels appear to be predefined rather than dynamically earned.

---

## Category 3: Risk Scoring & Approval Workflow Systems

### 3.1 mcp-human-loop -- Multi-Dimensional Scoring Gates

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/boorich/mcp-human-loop |
| **Stars** | 16 |
| **Language** | TypeScript |
| **Last Updated** | 2025-01-01 |
| **Source** | Individual |
| **Maturity** | Prototype |

**What it does**: MCP server implementing intelligent middleware that determines when human intervention is necessary. Uses a **sequential scoring system** evaluating requests across multiple dimensions.

**Scoring Dimensions**:
1. **Complexity Score** -- Is the task too complex for autonomous handling?
2. **Permission Score** -- Does the action require human authorization?
3. **Risk Score** -- Potential impact and reversibility of the action
4. **Emotional Intelligence Score** -- Does the situation need human emotional understanding?

**Routing Logic**: If any score exceeds defined thresholds, routes to human. Otherwise allows autonomous action. Logs evaluation decisions.

**Relevance to Adaptive Autonomy**: **Most architecturally relevant** prototype. This is essentially a trust/risk gate that dynamically evaluates each action. The "supports system learning" claim suggests a feedback loop, though implementation maturity is very low (16 stars, last updated Jan 2025).

**Key Insight**: The multi-dimensional scoring approach (risk + complexity + permission + emotional) is a more nuanced model than simple binary trust/distrust.

---

### 3.2 OpenAgentsControl -- Approval-Gated Plan-First Execution

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/darrenhinde/OpenAgentsControl |
| **Stars** | 2,162 |
| **Language** | TypeScript |
| **Last Updated** | 2026-02-20 |
| **Source** | Individual |
| **Maturity** | Active development |

**What it does**: Plan-first development workflow framework. Agents propose plans, humans approve, then agents implement. Model-agnostic (Claude, GPT, Gemini, local models). Multi-language (TS, Python, Go, Rust).

**Core Design**: Every execution (bash, write, edit, task delegation) requires approval -- this is absolute. Editable agents (not baked-in), approval gates (not auto-execute), pattern-based context system.

**Relevance to Adaptive Autonomy**: Strong on the "guardrails + harness" hybrid pattern. However, the autonomy level is binary (approved/not-approved), not graduated. No trust accumulation -- you cannot "earn" less oversight.

**When NOT to use**: If you want fully autonomous execution without approval gates, or if you lack established coding patterns.

---

### 3.3 GitHub Agentic Workflows (gh-aw)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/github/gh-aw |
| **Stars** | ~3,400+ (technical preview) |
| **Language** | N/A (GitHub Actions integration) |
| **Last Updated** | 2026-02 (technical preview launch) |
| **Source** | Company (GitHub) |
| **Maturity** | Technical preview |

**What it does**: AI coding agents running automatically in GitHub Actions with strong guardrails. Read-only permissions by default; write actions must pass through safe outputs that are reviewable and controlled.

**Architecture**: Sandboxed execution, tool allowlisting, network isolation. Agents operate within controlled boundaries. Write operations require explicit approval through sanitized safe outputs.

**Relevance to Adaptive Autonomy**: Enterprise-grade reference for "supervised autonomy at scale." Static permission model (read-only default, approved write operations). No dynamic trust adjustment.

---

## Category 4: Guardrail & Safety Frameworks

### 4.1 NVIDIA NeMo Guardrails

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/NVIDIA-NeMo/Guardrails |
| **Stars** | 5,682 |
| **Language** | Python |
| **Last Updated** | 2026-02-22 |
| **Source** | Company (NVIDIA) |
| **Maturity** | Production |

**What it does**: Programmable guardrails for LLM-based conversational systems. Controls output (topic prevention, conversational flow enforcement). Industry standard for guardrails.

**Relevance**: Addresses the "guardrails" half but not the "adaptive autonomy" half. No concept of trust levels or dynamic permission adjustment.

---

### 4.2 OpenGuardrails (Guard Agent for OpenClaw)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/openguardrails/openguardrails |
| **Stars** | 235 |
| **Language** | TypeScript |
| **Last Updated** | 2026-02-22 |
| **Source** | Community |
| **Maturity** | Active development |

**What it does**: Runtime security for AI agents. Client-side plugin running local PII sanitization gateway (port 8900) intercepting prompts before they reach LLMs. Monitoring dashboard (port 8901). Detects prompt injection, data leakage, unsafe behavior.

**Relevance**: Security layer for agents but no autonomy adjustment. Purely defensive (filter bad inputs/outputs).

---

### 4.3 Mozilla AI any-guardrail

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/mozilla-ai/any-guardrail |
| **Stars** | 65 |
| **Language** | Python |
| **Last Updated** | 2026-02-22 |
| **Source** | Company (Mozilla) |
| **Maturity** | Active development |

**What it does**: Unified interface for AI safety guardrail models. Switch between encoder-based and decoder-based models (Llama Guard, ShieldGemma) without code changes. Detects toxic content, jailbreak attempts, risks.

**Key Finding**: Critical gaps remain in protecting function-calling operations. Some guardrail models show promise for prompt injection but not for agentic execution control.

---

### 4.4 FareedKhan-dev/agentic-guardrails (Aegis Framework)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/FareedKhan-dev/agentic-guardrails |
| **Stars** | 34 |
| **Language** | Jupyter Notebook |
| **Last Updated** | 2025-10-05 |
| **Source** | Individual (educational) |
| **Maturity** | Tutorial/reference |

**What it does**: Demonstrates a 3-layer "Aegis" guardrail architecture: (1) Input perimeter defense (topical, PII, threat guardrails running in parallel), (2) Command core for action plan validation, (3) Output checkpoint.

**Relevance**: Good educational reference for layered guardrail architecture but not a framework. No autonomy adjustment.

---

## Category 5: Trust Research & Frameworks

### 5.1 AURA -- Agent Autonomy Risk Assessment Framework

| Attribute | Value |
|-----------|-------|
| **URL** | https://arxiv.org/abs/2510.15739 (paper, no dedicated GitHub repo found) |
| **Published** | October 2025 |
| **Source** | Academic (University of Exeter) |
| **Maturity** | Research paper / framework specification |

**What it does**: Unified framework to detect, quantify, and mitigate risks from agentic AI. Introduces **gamma-based risk scoring** methodology balancing accuracy with computational efficiency.

**Key Features**:
- Interactive process to score, evaluate, and mitigate risks of running AI agents
- Designed for Human-in-the-Loop (HITL) oversight and Agent-to-Human (A2H) communication
- Supports synchronous and asynchronous multi-agent systems
- Enterprise-focused: positions itself as enabler for large-scale governable agentic AI

**Context**: Global trust in fully autonomous AI dropped from 43% to 27% in 2025; less than 10% of organizations have robust AI governance frameworks.

**Relevance to Adaptive Autonomy**: **Most mathematically rigorous** approach found. The gamma-based risk scoring could serve as foundation for a trust-autonomy formula. However, no open-source implementation found -- paper only.

---

### 5.2 TrustAgent (agiresearch) -- Agent Constitution Framework

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/agiresearch/TrustAgent |
| **Stars** | 56 |
| **Language** | Python |
| **Last Updated** | 2025-02-07 |
| **Source** | Academic |
| **Maturity** | Research prototype |

**What it does**: Ensures trustworthy LLM agent behavior through an "Agent Constitution" with three strategies:
1. **Pre-planning**: Inject safety knowledge before plan generation
2. **In-planning**: Enhance safety during plan generation
3. **Post-planning**: Safety inspection after plan generation

**Relevance**: Focuses on *safety* dimension of trustworthiness, not *adaptive autonomy*. No performance-based trust accumulation.

---

### 5.3 CAMEL-AI agent-trust -- LLM Trust Behavior Simulation

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/camel-ai/agent-trust |
| **Stars** | 111 |
| **Language** | Python |
| **Last Updated** | 2025-04-06 |
| **Source** | Academic (NeurIPS paper) |
| **Maturity** | Research |

**What it does**: Studies whether LLMs can simulate human trust behavior using Trust Games. Finds GPT-4 agents align with human trust behavior.

**Relevance**: Measures trust *behavior* of LLMs, not trust *in* LLMs. Interesting for understanding how agents might participate in trust protocols, but not directly applicable to adaptive autonomy control.

---

### 5.4 PFI -- Prompt Flow Integrity for Privilege Escalation Prevention

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/compsec-snu/pfi |
| **Stars** | 26 |
| **Language** | Python |
| **Last Updated** | 2025-03-26 |
| **Source** | Academic (Seoul National University) |
| **Maturity** | Research prototype |

**What it does**: Prevents privilege escalation in LLM agents through agent isolation and data tracking. Separates trusted and untrusted agents with different plugin access levels defined by policy.

**Results**: 10x improvement in Secure Utility Rate vs baseline ReAct (27.84% to 55.67% on AgentDojo).

**Relevance**: The trusted/untrusted agent separation is a form of static trust level. Interesting architectural pattern but no dynamic adjustment.

---

## Category 6: Trust Infrastructure & Protocols

### 6.1 Visa Trusted Agent Protocol (TAP)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/visa/trusted-agent-protocol |
| **Stars** | 117 |
| **Language** | Python |
| **Last Updated** | 2025-10-28 |
| **Source** | Company (Visa) |
| **Maturity** | Specification / early implementation |

**What it does**: Universal standard for trust between AI agents and merchants in agentic commerce. Built on HTTP Message Signature standard. Provides agent verification, context-bound security, replay attack prevention.

**Partners**: Adyen, Stripe, Shopify, Microsoft, Coinbase, Checkout.com, and others.

**Relevance**: Addresses **inter-agent trust** (is this agent authorized?), not **intra-agent trust** (how much autonomy should this agent have?). Different problem domain but relevant for the trust verification layer.

---

### 6.2 Gen Agent Trust Hub

| Attribute | Value |
|-----------|-------|
| **URL** | https://ai.gendigital.com/agent-trust-hub (not open source) |
| **Launched** | 2026-02-04 |
| **Source** | Company (Gen Digital -- Norton/Avast parent) |
| **Maturity** | Commercial product |

**What it does**: Security platform for safer autonomous AI agent adoption. Free AI Skills Scanner analyzes OpenClaw skill URLs for hidden logic, unauthorized data access, malicious behavior. Curated AI Skills Marketplace with security auditing.

**Context**: Gen Threat Labs found 18,000+ exposed OpenClaw instances, ~15% of observed skills containing malicious instructions.

**Relevance**: Security scanning, not autonomy adjustment. Addresses trust in *agent skills/tools*, not trust in the *agent itself*.

---

### 6.3 TrustGraph -- Graph-Powered Context Harness

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/trustgraph-ai/trustgraph |
| **Stars** | 1,302 |
| **Language** | Python |
| **Last Updated** | 2026-02-22 |
| **Source** | Company / Community |
| **Maturity** | Active development |

**What it does**: Knowledge graph infrastructure for AI agents. The "trust" in the name refers to trusted/verified knowledge context, not agent behavioral trust.

**Relevance**: Minimal direct relevance to adaptive autonomy. The knowledge graph could potentially store agent performance history for trust scoring, but this is not its current purpose.

---

## Category 7: Evolving / Self-Improving Agent Systems

### 7.1 Evolving Agents Toolkit

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/matiasmolinas/evolving-agents |
| **Stars** | 448 |
| **Language** | Python |
| **Last Updated** | 2025-11-24 |
| **Source** | Individual |
| **Maturity** | Active prototype |

**What it does**: Toolkit for autonomous, evolving agent ecosystems. Agents learn from experience, collaborate, build new capabilities, operate within guardrails.

**Key Components**:
- **SmartLibrary**: Persistent storage with dual embedding strategy (content + applicability)
- **SmartAgentBus**: Dynamic capability discovery and request routing
- **Governed Execution**: Multi-level review checkpoints via IntentReviewAgent
- **MongoDB backend**: Unified storage replacing file-based + ChromaDB

**Relevance**: The "governed execution with multi-level review checkpoints" is relevant. Has an open issue (#95) for implementing "Human-in-the-Loop Workflow for Intent Review in SystemAgent." The evolutionary aspect (agents that improve over time) is conceptually aligned with earned autonomy, though the trust/autonomy connection is not explicitly implemented.

---

## Category 8: Claude Agent SDK Ecosystem

### 8.1 Official Claude Agent SDKs

| Repository | Stars | Language | Last Updated |
|-----------|-------|----------|-------------|
| [anthropics/claude-agent-sdk-python](https://github.com/anthropics/claude-agent-sdk-python) | N/A | Python | Active |
| [anthropics/claude-agent-sdk-typescript](https://github.com/anthropics/claude-agent-sdk-typescript) | N/A | TypeScript | Active |
| [anthropics/claude-agent-sdk-demos](https://github.com/anthropics/claude-agent-sdk-demos) | N/A | Various | Active |

**What they do**: High-level framework for building custom AI agent systems using Claude Code as the core agent. Bundles Claude Code CLI automatically.

**Relevance**: These are the official harness SDKs. No built-in trust scoring or adaptive autonomy. Permission model is defined by the calling application.

### 8.2 Open-Agent (AFK-surf) -- Claude Agent SDK Alternative

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/AFK-surf/open-agent |
| **Stars** | 651 |
| **Language** | TypeScript |
| **Last Updated** | 2025-10-10 |
| **Source** | Community |
| **Maturity** | Prototype |

**What it does**: Open-source alternative to Claude Agent SDK, ChatGPT Agents, and Manus. No adaptive autonomy features found.

---

## Category 9: Pattern Collections & Reference Materials

### 9.1 Awesome Agentic Patterns

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/nibzard/awesome-agentic-patterns |
| **Stars** | 3,369 |
| **Language** | Python |
| **Last Updated** | 2026-02-06 |
| **Source** | Community |
| **Maturity** | Reference documentation |

**What it does**: 80+ documented production-ready agentic AI patterns across 8 categories. Includes human-in-the-loop approval framework pattern.

**HITL Pattern Description**: "Systematically insert human approval gates for designated high-risk functions while maintaining agent autonomy for safe operations, creating lightweight feedback loops that enable time-sensitive human decisions without blocking the entire agent workflow."

**Categories**: Orchestration & Control, Context & Memory, Feedback Loops, Learning & Adaptation, Reliability & Eval, Security & Safety, Tool Use & Environment, UX & Collaboration.

**Relevance**: Excellent reference for patterns but not an implementation.

---

### 9.2 "Supervised Autonomy Agents" (Edge Case, Medium)

| Attribute | Value |
|-----------|-------|
| **URL** | https://edge-case.medium.com/supervised-autonomy-the-ai-framework-everyone-will-be-talking-about-in-2026-fe6c1350ab76 |
| **Published** | December 2025 |
| **Source** | Industry thought piece |
| **Maturity** | Conceptual framework |

**Core Thesis**: Supervised Autonomy is "the architectural principle that AI systems operating on probabilistic problems must include human checkpoints -- not as a fallback, but as a core design requirement."

**Key Observation**: Failure cases are the norm, not edge cases. Teams succeeding with AI in production have designed for this.

**Examples**: Cursor, GitHub Copilot, Claude Code, Windsurf -- none commit code directly to repos or merge to main without approval.

**Relevance**: Articulates the design philosophy well but provides no implementation.

---

## Category 10: Authorization / Permission Infrastructure

### 10.1 Permit.io -- AI Agent Authorization

| Attribute | Value |
|-----------|-------|
| **URL** | https://www.permit.io (commercial, SDK open source) |
| **Source** | Company (Permit.io) |
| **Maturity** | Production (commercial) |

**What it does**: Fine-grained authorization for human, machine, and agentic identities. Assign machine identities to agents to track/manage access. RBAC, ABAC, ReBAC support. MCP server enables tools that agents can call but only execute after human approval.

**Relevance**: Could serve as the *authorization enforcement layer* for an adaptive autonomy system. The agent's trust level could map to RBAC roles that are dynamically adjusted. However, Permit.io itself does not implement the trust scoring -- it would need to be connected to one.

---

## Synthesis: Gaps & Opportunities

### What Exists

| Capability | Best Implementation | Maturity |
|-----------|-------------------|----------|
| Static autonomy levels (manual/supervised/full) | ZeroClaw (17k stars) | Production |
| Human-in-the-loop approval gates | OpenAgentsControl (2.2k stars) | Active |
| Per-action risk scoring | mcp-human-loop (16 stars) | Prototype |
| Tiered autonomy + risk scoring | OwnPilot (95 stars) | Prototype |
| Agent trust measurement | CAMEL-AI agent-trust (111 stars) | Research |
| Risk assessment framework (academic) | AURA (paper only) | Research |
| Guardrails (input/output filtering) | NVIDIA NeMo (5.7k stars) | Production |
| Agent authorization/permissions | Permit.io | Production (commercial) |
| Agent harness with HITL | LangChain DeepAgents (9.5k stars) | Production |

### What Does NOT Exist (Gaps)

1. **Dynamic trust accumulation**: No project tracks agent performance over time and automatically adjusts autonomy levels based on success/failure history
2. **Mathematical trust-autonomy model**: No implementation of SOC or similar formulas converting trust metrics into autonomy decisions
3. **Earned autonomy with degradation**: No system where agents start restricted, earn broader permissions through demonstrated competence, and lose them through failures
4. **Risk-aware autonomy escalation**: No production system that combines per-action risk scoring with a trust state machine that evolves over the agent's lifetime
5. **Multi-dimensional trust scoring with feedback**: mcp-human-loop has the scoring dimensions but no persistent learning or trust accumulation

### Architectural Patterns Worth Borrowing

1. **ZeroClaw's 3-tier model** (readonly/supervised/full): Clean, simple, well-understood. Good starting point for autonomy levels
2. **mcp-human-loop's multi-dimensional scoring**: Risk + Complexity + Permission + Emotional Intelligence as independent evaluation axes
3. **AURA's gamma-based risk scoring**: Mathematical rigor for quantifying agent risk
4. **OwnPilot's 5-level autonomy with risk scoring**: Most complete vision, though prototype quality
5. **OpenAgentsControl's plan-first pattern**: Approval at the *plan* level rather than action level reduces approval fatigue
6. **Permit.io's RBAC model**: Map trust levels to authorization roles with well-understood access control semantics
7. **PFI's trusted/untrusted agent separation**: Architectural isolation based on trust level
8. **Cline's per-category auto-approve**: Granular control where different *types* of actions have different autonomy settings

### Key Insight

The industry is converging on **Supervised Autonomy** (human checkpoints as core design) but has not yet implemented the next evolution: **Earned Autonomy** (checkpoints that dynamically adjust based on demonstrated competence). This represents a significant open-source opportunity.

---

## Appendix: SOC Trust-Autonomy Formula Search

No GitHub repository was found implementing the SOC (Situation-Operator-Craft) trust-autonomy formula or any equivalent mathematical model that:
- Takes inputs: agent performance history, action risk level, domain confidence
- Produces output: autonomy level / permission set

The closest academic work is AURA's gamma-based risk scoring, but it focuses on risk *assessment* rather than autonomy *adjustment*.

The Frontiers in Neuroergonomics survey on "Mathematical Models of Human Trust in Automation" identifies three trust variability sources (dispositional, situational, learned) which could inform a trust model, but no LLM agent implementation exists.

---

## Appendix: Star Count Summary (sorted descending)

| Stars | Repository | Category |
|-------|-----------|----------|
| 58,244 | cline/cline | Coding agent with permission model |
| 17,034 | zeroclaw-labs/zeroclaw | 3-tier autonomy modes |
| 9,484 | langchain-ai/deepagents | Agent harness with HITL |
| 9,434 | humanlayer/humanlayer | Coding agent with human loop |
| 5,682 | NVIDIA-NeMo/Guardrails | Guardrails framework |
| 3,369 | nibzard/awesome-agentic-patterns | Pattern catalogue |
| 2,162 | darrenhinde/OpenAgentsControl | Approval-gated execution |
| 1,302 | trustgraph-ai/trustgraph | Knowledge graph context |
| 651 | AFK-surf/open-agent | Claude SDK alternative |
| 618 | dapr/dapr-agents | Production agent runtime |
| 448 | matiasmolinas/evolving-agents | Self-evolving agents |
| 359 | winstonkoh87/Athena-Public | Governed autonomy OS |
| 339 | humanlayer/agentcontrolplane | Agent scheduler |
| 235 | openguardrails/openguardrails | Runtime security |
| 117 | visa/trusted-agent-protocol | Commerce trust protocol |
| 114 | valory-xyz/open-autonomy | Multi-agent services |
| 111 | camel-ai/agent-trust | Trust behavior research |
| 95 | ownpilot/OwnPilot | 5-level autonomy + risk |
| 65 | mozilla-ai/any-guardrail | Unified guardrail interface |
| 56 | agiresearch/TrustAgent | Agent constitution safety |
| 34 | FareedKhan-dev/agentic-guardrails | Guardrail tutorial |
| 26 | compsec-snu/pfi | Privilege escalation prevention |
| 16 | boorich/mcp-human-loop | Multi-dim scoring gates |
