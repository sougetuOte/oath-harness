# GitHub Individual/Small-Team AI Agent Projects Research

**Date**: 2026-02-23
**Scope**: AI agent frameworks and tools built by individuals or small teams (NOT major vendors)
**Focus Period**: 2025-2026

---

## 1. Executive Summary

The AI agent framework space in 2025-2026 has seen an explosion of individual/small-team projects, particularly in three categories: (1) minimal coding agent harnesses, (2) agent safety/guardrails systems, and (3) Claude Code ecosystem extensions. The market is consolidating around vendor frameworks (LangGraph, CrewAI, Microsoft Agent Framework) for general-purpose use, but significant gaps remain that individuals can fill -- particularly in opinionated workflow orchestration, TDD-agent integration, constitutional governance patterns, and developer experience tooling.

Key finding: The "sweet spot" for individual contribution is NOT building yet another general-purpose agent framework, but rather building **opinionated workflow layers**, **safety/quality systems**, **domain-specific orchestrators**, and **developer experience tooling** on top of existing foundations.

---

## 2. Minimal / Lightweight Agent Harness Projects

### 2.1 Pi (badlogic/pi-mono) -- Mario Zechner

- **URL**: https://github.com/badlogic/pi-mono
- **Blog post**: https://mariozechner.at/posts/2025-11-30-pi-coding-agent/
- **Language**: TypeScript monorepo (npm workspaces)
- **What makes it unique**: Ships with only 4 core tools (read, write, edit, bash) and a ~300-word system prompt. Philosophy: "All frontier models have been RL-trained extensively, so they inherently understand what a coding agent is." Adding specialized tools just adds tokens without capability.
- **Significance**: Became the engine behind OpenClaw, which rocketed to 145,000+ GitHub stars in a single week. Proves that extreme minimalism can beat sophisticated tooling.
- **Individual feasibility**: High. The core insight is that less is more -- a single developer can maintain a minimal harness effectively.
- **Gap filled**: Vendor agents (Claude Code, Codex) evolve into "spaceships with 80% functionality nobody uses." Pi fills the need for simplicity.

### 2.2 Oh-My-Pi (can1357/oh-my-pi)

- **URL**: https://github.com/can1357/oh-my-pi
- **What makes it unique**: Fork/extension of Pi adding hash-anchored edits, optimized tool harness, LSP integration, Python support, browser automation, and subagents.
- **Gap filled**: Shows that even a minimal harness benefits from community extension.

### 2.3 OpenCode (opencode-ai/opencode)

- **URL**: https://github.com/opencode-ai/opencode
- **Language**: Go (with Bubble Tea TUI)
- **Stars**: 100,000+
- **What makes it unique**: Go-based CLI with interactive TUI, multi-provider support, session management. Has grown from small project to major platform.
- **Note**: Has grown beyond "individual project" scale but started as one. Good reference for project growth trajectory.

### 2.4 Single-File AI Agent Tutorial (leobeeson/single-file-ai-agent-tutorial)

- **URL**: https://github.com/leobeeson/single-file-ai-agent-tutorial
- **Language**: Python (218 lines, single file)
- **What makes it unique**: Complete agent in 218 lines with no frameworks. Uses uv's inline dependencies (no pip installs). Educational focus -- shows exactly how agents parse responses, execute tools, and maintain conversation context.
- **Individual feasibility**: Extremely high. Perfect learning reference.

### 2.5 MiniAGI (muellerberndt/mini-agi)

- **URL**: https://github.com/muellerberndt/mini-agi
- **What makes it unique**: Simple autonomous agent with minimal toolset, chain-of-thoughts, and short-term memory with summarization.

### 2.6 SanityHarness (lemon07r/SanityHarness)

- **URL**: https://github.com/lemon07r/SanityHarness
- **What makes it unique**: Lightweight evaluation harness for coding agents. Runs tasks in isolated Docker containers across 26 tasks in 6 languages with weighted scoring. Not an agent itself but a harness for evaluating agents.
- **Gap filled**: Agent benchmarking is dominated by complex academic benchmarks. SanityHarness is practical and lightweight.

---

## 3. Agent Safety / Guardrails Projects

### 3.1 Superagent (superagent-ai/superagent)

- **URL**: https://github.com/superagent-ai/superagent
- **What makes it unique**: Open-source SDK for AI agent safety. Blocks prompt injections, redacts PII and secrets, scans repositories for threats, runs red team scenarios. Focus is purely on the safety layer, not the agent itself.
- **Individual feasibility**: Medium (small team project). But the approach of "safety as a separate layer" is learnable.
- **Gap filled**: Most frameworks bolt safety on as an afterthought. Superagent makes safety the primary concern.

### 3.2 Agentic Guardrails -- Aegis Framework (FareedKhan-dev/agentic-guardrails)

- **URL**: https://github.com/FareedKhan-dev/agentic-guardrails
- **What makes it unique**: Three-layer defense-in-depth architecture (perimeter defense for input, command core for action plans, final checkpoint for output). Three parallel input guardrails: Topical Guardrail, Sensitive Data Guardrail, Threat & Compliance Guardrail (using Llama-Guard).
- **Individual feasibility**: High. The author (FareedKhan-dev) also maintains related repos:
  - [all-agentic-architectures](https://github.com/FareedKhan-dev/all-agentic-architectures) -- 17+ agentic architecture implementations
  - [production-grade-agentic-system](https://github.com/FareedKhan-dev/production-grade-agentic-system) -- 7 layers of production-grade systems
- **Gap filled**: Educational implementations of safety patterns that vendors describe but don't open-source in digestible form.

### 3.3 OpenGuardrails / OpenClaw (openguardrails/openguardrails)

- **URL**: https://github.com/openguardrails/openguardrails
- **What makes it unique**: Security framework scanning every input/output through configurable detection pipeline. Enforces security policies with full visibility. Partnered with Pi coding agent.

### 3.4 AgentSafety (OSU-NLP-Group/AgentSafety)

- **URL**: https://github.com/OSU-NLP-Group/AgentSafety
- **What makes it unique**: Academic project tracking papers on agent attacks, defenses, evaluations, benchmarks, and surveys. Good reference collection rather than a framework.

---

## 4. Constitutional / Rules-Based Agent Governance

### 4.1 GitHub Spec Kit -- Constitutional Governance (github/spec-kit)

- **URL**: https://github.com/github/spec-kit
- **What makes it unique**: Spec-Driven Development with a "constitution" as immutable project principles stored in `.specify/memory/constitution.md`. The constitution establishes non-negotiable rules before any coding begins. The `/speckit.constitution` command sets up governance before feature work.
- **Significance**: This is GitHub's official take on "agent constitution" patterns. Validates the approach used in projects like Living Architect Model.
- **Individual feasibility**: High. The constitutional pattern itself is portable and can be adapted to any project.

### 4.2 AGENTS.md Standard (Emerging Community Standard)

- **Reference**: https://github.com/continuedev/continue/issues/6716
- **What it is**: A proposed community standard for a single `AGENTS.md` file in project root containing natural language instructions for AI coding agents. Addresses the fragmentation where Cline, Aider, Cursor, and GitHub Copilot each use proprietary configs.
- **Gap filled**: No universal standard exists for "how to tell an agent about your project." CLAUDE.md, .cursorrules, .github/copilot-instructions.md, etc. are all vendor-specific.

### 4.3 Agent Rules MCP (4regab/agent-rules-mcp)

- **URL**: https://github.com/4regab/agent-rules-mcp
- **What makes it unique**: MCP server that enables agents to use coding rules from any GitHub repository. Instead of workspace rules files, you can prompt agents to access coding rules from any repository.

### 4.4 Awesome AI System Prompts (dontriskit/awesome-ai-system-prompts)

- **URL**: https://github.com/dontriskit/awesome-ai-system-prompts
- **What makes it unique**: Curated collection of system prompts for top AI tools (ChatGPT, Claude, Perplexity, Manus, Claude Code, Loveable, v0, Grok, etc.). Good reference for understanding how different tools implement their "constitutions."

---

## 5. TDD + Agent Integration Projects

### 5.1 tddGPT (gimlet-ai/tddGPT)

- **URL**: https://github.com/gimlet-ai/tddGPT
- **Status**: Early alpha
- **What makes it unique**: Autonomous coding agent that strictly follows TDD: writes tests first, implements code, runs tests, fixes issues. Self-learning -- evaluates mistakes and incorporates insights into operating prompts.
- **Individual feasibility**: High (simple architecture). But requires GPT-4 API key.
- **Gap filled**: Most agent frameworks don't enforce TDD discipline. This makes TDD the core workflow, not an option.

### 5.2 AI-TDD (di-sukharev/AI-TDD)

- **URL**: https://github.com/di-sukharev/AI-TDD
- **What makes it unique**: CLI where you write the test and GPT writes the code to pass it. Clean separation of human concern (test design) and AI concern (implementation).
- **Individual feasibility**: Very high. Simple CLI tool.

### 5.3 tdd-ai (allenheltondev/tdd-ai)

- **URL**: https://github.com/allenheltondev/tdd-ai
- **What makes it unique**: Proof of concept for using Generative AI to write code from human-written tests.

### 5.4 MoAI-ADK (modu-ai/moai-adk)

- **URL**: https://github.com/modu-ai/moai-adk
- **Language**: Go (single binary, zero dependencies)
- **Origin**: Korean developer community
- **What makes it unique**: Combines SPEC-First development, TDD, and 28 specialized AI agents. Claims 90% reduction in rework, 70% reduction in bugs (85%+ coverage), 15% shorter total development time. Functions as a strategic orchestrator delegating to specialized agents rather than writing code directly.
- **Gap filled**: Integrates spec-driven and test-driven approaches into agent orchestration -- a combination vendors haven't packaged together.

### 5.5 Copilot Orchestra (ShepAlderson/copilot-orchestra)

- **URL**: https://github.com/ShepAlderson/copilot-orchestra
- **What makes it unique**: Multi-agent orchestration for structured TDD development with AI. Conductor agent orchestrates Planning -> Implementation -> Review -> Commit cycle. Uses custom chat modes in VSCode Insiders. Featured by VS Code's official Twitter account.
- **Gap filled**: Shows how to build structured development workflow on top of existing IDE agent capabilities.

---

## 6. Claude Code Ecosystem Projects

### 6.1 Claudekit (carlrannaberg/claudekit)

- **URL**: https://github.com/carlrannaberg/claudekit
- **What makes it unique**: Toolkit providing auto-save checkpointing, code quality hooks, specification generation/execution, and 20+ specialized subagents (including oracle, code-reviewer, ai-sdk-expert, typescript-expert). Installable via npm.
- **Individual feasibility**: High. Shows how one developer can build a comprehensive toolkit.

### 6.2 Claude Code Hooks Collection (karanb192/claude-code-hooks)

- **URL**: https://github.com/karanb192/claude-code-hooks
- **What makes it unique**: Growing collection of tested, documented hooks for safety, automation, and notifications. Copy-paste-customize approach.

### 6.3 Claude Code Hooks Mastery (disler/claude-code-hooks-mastery)

- **URL**: https://github.com/disler/claude-code-hooks-mastery
- **What makes it unique**: Educational repository for mastering Claude Code hooks.

### 6.4 Claude Code Marketplace (Dev-GOM/claude-code-marketplace)

- **URL**: https://github.com/Dev-GOM/claude-code-marketplace
- **What makes it unique**: Plugin marketplace for Claude Code -- hooks, commands, and agents for developer productivity and workflow automation.

### 6.5 Claude Code Sub-Agents (lst97/claude-code-sub-agents)

- **URL**: https://github.com/lst97/claude-code-sub-agents
- **What makes it unique**: Collection of specialized AI subagents for Claude Code for personal full-stack development use.

### 6.6 Awesome Claude Code (hesreallyhim/awesome-claude-code)

- **URL**: https://github.com/hesreallyhim/awesome-claude-code
- **What makes it unique**: Comprehensive curated list of skills, hooks, slash-commands, agent orchestrators, applications, and plugins. Includes a collection of CLAUDE.md files from various projects. The go-to directory for Claude Code extensions.

### 6.7 Claude Flow (ruvnet/claude-flow)

- **URL**: https://github.com/ruvnet/claude-flow
- **What makes it unique**: Multi-agent orchestration platform for Claude with 54+ specialized agents, shared memory, consensus mechanisms, and continuous learning. V3 is a complete rebuild in TypeScript and WASM. Claims ~100,000 monthly active users.
- **Note**: Has grown beyond individual scale but originated as an individual project.

---

## 7. Agent Orchestration by Individuals

### 7.1 OpenAgentsControl (darrenhinde/OpenAgentsControl)

- **URL**: https://github.com/darrenhinde/OpenAgentsControl
- **What makes it unique**: Plan-first development with approval-based execution. Agents propose plans; you approve before execution. Uses MVI (Minimal Viable Information) principle for 80% token reduction. Context-aware -- ContextScout discovers relevant patterns before code generation.
- **Key agents**: OpenCoder (complex coding), OpenAgent (universal coordinator with 6-stage workflow).
- **Gap filled**: The approval-gate pattern is under-served by vendors who optimize for speed over safety.

### 7.2 Langroid (langroid/langroid)

- **URL**: https://github.com/langroid/langroid
- **Origin**: CMU and UW-Madison researchers (small academic team)
- **Language**: Python
- **What makes it unique**: First Python framework explicitly designed with Agents as first-class citizens and Multi-Agent Programming as core design principle. Does NOT use LangChain. Clean abstraction: Agent (LLM + vector-store + tools) -> Task (wraps Agent with instructions) -> hierarchical recursive task-delegation.
- **Gap filled**: Academic rigor in a practical framework. Most vendor frameworks prioritize ease-of-use over principled design.

### 7.3 Linear Coding Agent Harness (coleam00/Linear-Coding-Agent-Harness)

- **URL**: https://github.com/coleam00/Linear-Coding-Agent-Harness
- **What makes it unique**: Minimal harness for long-running autonomous coding with Claude Agent SDK. Two-agent pattern (initializer + coding agent) with Linear as project management system.
- **Gap filled**: Integration of agent coding with project management tools is under-explored.

---

## 8. Developer Experience Focused Projects

### 8.1 VoltAgent

- **URL**: https://github.com/VoltAgent/voltagent
- **Language**: TypeScript
- **What makes it unique**: TypeScript-first framework with built-in observability and visual debugging (like n8n but for AI agents). Everything in the same codebase with same types, linters, deployment pipeline. Includes memory adapters, RAG, voice, guardrails, and workflow engine.
- **Launched**: April 2025
- **Gap filled**: The "middle ground" between no-code platforms and starting from scratch. Focuses on DX more than any vendor framework.

### 8.2 Agno (agno-agi/agno)

- **URL**: https://github.com/agno-agi/agno
- **Language**: Python
- **Stars**: 22K+
- **Previously**: Phidata (rebranded January 2025)
- **What makes it unique**: Stateless, horizontally scalable runtime. Modular design allows swapping LLMs, databases, or vector stores without rewriting code. Built-in state management, observability, and human-in-the-loop.
- **Note**: Has grown to VC-funded company stage but still maintains small-team feel.

### 8.3 Mastra (mastra-ai/mastra)

- **URL**: https://github.com/mastra-ai/mastra
- **Language**: TypeScript
- **Origin**: Team behind Gatsby (YC-backed)
- **Stars**: 50K+
- **What makes it unique**: TypeScript AI framework with agents, workflows, and RAG. 32%+ of web traffic from Japan, with Japanese documentation.
- **Note**: VC-funded but originated from Gatsby team's pivot. Relevant for understanding TypeScript agent DX patterns.

---

## 9. Japanese Developer Community

### 9.1 General Landscape

2025 was called "AI Agent Gannen" (AI Agent Year One) in Japan. The Japanese developer community is actively tracking and contributing to:

- **Mastra**: 32%+ of traffic from Japan; Japanese docs available
- **MoAI-ADK**: Korean project with Japanese developer interest
- **GitHub trending analysis**: Qiita articles tracking GitHub trends monthly (by nogataka)

### 9.2 Key Resources for Japanese Developers

- **Qiita**: Active discussion on agent frameworks comparison (zenn.dev, qiita.com)
- **note.com**: Individual developer blog posts about AI agent development
- **Zenn.dev**: Technical articles on agent framework comparisons and individual development experiences

### 9.3 Observation

While Japanese developers are actively using and writing about agent frameworks, there are fewer original Japanese-authored agent frameworks visible on GitHub. The community's strength appears to be in:
- High-quality technical analysis and comparison articles
- Rapid adoption and adaptation of international frameworks
- Domain-specific application of agent tools (especially in enterprise contexts)
- Documentation and localization efforts

---

## 10. Curated Lists (Meta-Resources)

| Repository | Stars | Focus |
|-----------|-------|-------|
| [e2b-dev/awesome-ai-agents](https://github.com/e2b-dev/awesome-ai-agents) | Large | General AI agents |
| [kyrolabs/awesome-agents](https://github.com/kyrolabs/awesome-agents) | Medium | Tools and products for building agents |
| [jim-schwoebel/awesome_ai_agents](https://github.com/jim-schwoebel/awesome_ai_agents) | Medium | 1,500+ resources |
| [ashishpatel26/500-AI-Agents-Projects](https://github.com/ashishpatel26/500-AI-Agents-Projects) | Medium | Industry use cases |
| [bradAGI/awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents) | Small | Terminal-native coding agents |
| [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | Medium | Claude Code ecosystem |
| [ComposioHQ/awesome-claude-plugins](https://github.com/ComposioHQ/awesome-claude-plugins) | Small | Claude Code plugins |
| [eltociear/awesome-AI-driven-development](https://github.com/eltociear/awesome-AI-driven-development) | Medium | AI-driven dev tools |

---

## 11. Analysis: Sweet Spots for Individual Contribution

### 11.1 Where Vendors Are Strong (Avoid Competing Directly)

- General-purpose agent loops (LangGraph, CrewAI, OpenAI Agents SDK)
- Enterprise integration (Microsoft Agent Framework, AWS Agent Squad)
- IDE integration (GitHub Copilot, Cursor, Windsurf)
- Cloud deployment and scaling

### 11.2 Where Individuals Thrive

| Niche | Why | Examples |
|-------|-----|----------|
| **Opinionated minimal harnesses** | Vendors bloat to serve everyone; individuals can stay lean | Pi, OpenCode (early days) |
| **Safety/guardrails layers** | Vendors focus on capability, not constraints | Superagent, Aegis, OpenGuardrails |
| **Constitutional governance patterns** | Highly project-specific; one-size-fits-all fails | Spec-Kit constitution, AGENTS.md standard |
| **TDD-agent integration** | Vendors optimize for speed, not discipline | tddGPT, AI-TDD, MoAI-ADK |
| **Claude Code ecosystem** | Anthropic provides hooks/plugins API; community builds on it | Claudekit, hooks collections, sub-agents |
| **Evaluation harnesses** | Vendors don't evaluate competitor agents | SanityHarness |
| **Workflow-specific orchestrators** | Too niche for vendors | Copilot Orchestra, Linear Agent Harness |
| **Agent rules/config standards** | Cross-vendor interop is no vendor's priority | AGENTS.md, agent-rules-mcp |
| **Domain-specific agents** | Vertical knowledge too specialized | Medical, legal, education agents |
| **Developer experience tooling** | Observability and debugging for agents | VoltAgent |

### 11.3 Emerging Patterns Vendors Haven't Adopted

1. **Constitutional Governance**: Immutable project principles that constrain agent behavior before any code is written. Only GitHub Spec Kit has partially adopted this; most vendor frameworks lack it entirely.

2. **Plan-First with Approval Gates**: Agents propose plans and wait for human approval before execution. OpenAgentsControl implements this; most vendor agents optimize for autonomous speed.

3. **TDD as Core Agent Workflow**: Making TDD the mandatory agent development pattern, not an optional feature. No major vendor enforces this.

4. **Minimal Viable Information (MVI)**: Loading only what's needed, when it's needed, to minimize token usage. An 80% token reduction is achievable but vendors don't optimize for this.

5. **Cross-Agent Interoperability**: Standards like AGENTS.md that work across Cursor, Claude Code, Copilot, etc. No vendor has incentive to support competitors.

6. **Self-Evaluating Agents**: Agents that assess their own performance and incorporate learnings (tddGPT's approach). Most vendor agents don't have built-in self-improvement.

---

## 12. Recommendations for This Project (Living Architect Model)

Based on this research, the Living Architect Model's approach aligns with several identified sweet spots:

1. **Constitutional governance** -- The project's `CLAUDE.md` and `.claude/rules/` structure mirrors the Spec-Kit constitutional pattern and AGENTS.md standard. This is a validated pattern.

2. **Phase-gated workflow** (PLANNING -> BUILDING -> AUDITING with approval gates) -- Similar to OpenAgentsControl's plan-first approach but more structured. This is under-served by vendors.

3. **TDD enforcement** -- The BUILDING phase's TDD requirement aligns with the gap identified in tddGPT and MoAI-ADK. Most frameworks don't enforce this.

4. **Three Agents Model** (Affirmative/Critical/Mediator) -- A unique decision-making pattern not found in any surveyed project. This is genuinely novel.

5. **Potential contributions to the ecosystem**:
   - The Living Architect Model could be published as a CLAUDE.md template/reference implementation
   - The phase-gated workflow pattern could be packaged as a Claude Code plugin
   - The Three Agents decision model could be formalized as a reusable pattern

---

## 13. Sources

### Blog Posts & Articles
- [What I learned building an opinionated and minimal coding agent](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) -- Mario Zechner
- [Agentic TDD and other Learnings from coding with CoPilot](https://samollason.github.io/ai/2025/07/24/using-copilot-agent-and-tdd.html)
- [Test-Driven Development | Agentic Coding Handbook](https://tweag.github.io/agentic-coding-handbook/WORKFLOW_TDD/)
- [Diving Into Spec-Driven Development With GitHub Spec Kit](https://developer.microsoft.com/blog/spec-driven-development-spec-kit)
- [10 Things Developers Want from their Agentic IDEs in 2025](https://redmonk.com/kholterhoff/2025/12/22/10-things-developers-want-from-their-agentic-ides-in-2025/)
- [Superagent: Open-source framework for guardrails around agentic AI](https://www.helpnetsecurity.com/2025/12/29/superagent-framework-guardrails-agentic-ai/)

### Japanese Sources
- [2025年AIエージェント元年の振り返りと、2026年エンジニアが歩むべき道](https://zenn.dev/aircloset/articles/72c3f985fae9b4)
- [GitHubトレンド月間Top10 -- AIエージェント一色の開発エコシステム](https://qiita.com/nogataka/items/c394ba63863cb2799d19)
- [主要エージェント開発フレームワーク徹底比較](https://zenn.dev/acntechjp/articles/b21f47492e9527)

### Curated Lists
- [awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents)
- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)
- [awesome-ai-agents (e2b-dev)](https://github.com/e2b-dev/awesome-ai-agents)
- [awesome-AI-driven-development](https://github.com/eltociear/awesome-AI-driven-development)
