# Research Memo: Trust-Based Supervision Level Adjustment

**Date**: 2026-02-23
**Topic**: How systems (robotic, software, AI) dynamically adjust the level of human oversight based on demonstrated trust, risk profile, and contextual factors
**Purpose**: Inform the design of a quality-gate + autonomous-harness hybrid architecture

---

## 1. Trust-Based Autonomy in Robotics and Autonomous Systems

### 1.1 Foundational Taxonomy: Sheridan & Verplank (1978)

The concept of levels of automation (LOA) originates with Sheridan and Verplank's seminal 10-level taxonomy for supervisory control. The key insight is that automation is not "all or nothing" but rather a spectrum of human-machine task allocation:

| Level | Description |
|-------|-------------|
| 1 | Human does everything |
| 2 | Computer offers alternatives |
| 3 | Computer narrows alternatives to a few |
| 4 | Computer suggests one alternative |
| 5 | Computer executes if human approves |
| 6 | Computer executes; human can veto |
| 7 | Computer executes; informs human |
| 8 | Computer executes; informs human only if asked |
| 9 | Computer executes; informs human only if it decides to |
| 10 | Computer acts entirely autonomously |

This was later refined by Parasuraman, Sheridan & Wickens (2000) into four generic information-processing functions: information acquisition, information analysis, decision selection, and action implementation -- each of which can be independently set to different LOA levels.

**Sources**:
- [Sheridan & Verplank LOA Diagram (ResearchGate)](https://www.researchgate.net/figure/Sheridan-and-Verplanks-original-levels-of-automation-2_tbl1_337253476)
- [LOA Literature Review (HAL/INRIA)](https://inria.hal.science/hal-03630916/document)

### 1.2 SAE J3016: Autonomous Vehicles as a Reference Model

The SAE J3016 standard defines six levels (0-5) of driving automation. The critical architectural insight is the **sharp boundary at Level 3** where the system, not the human, performs the entire dynamic driving task within its operational design domain (ODD):

- **Levels 0-2**: The human performs part or all of the driving task. The system assists but the human must supervise.
- **Level 3**: The system performs the full task within its ODD but the human must be ready to intervene on request ("fallback-ready user").
- **Level 4**: The system handles the full task within its ODD, including fallback. No human intervention required within the ODD.
- **Level 5**: Full autonomy in all conditions.

The key design pattern is **operational design domain (ODD) scoping**: a system can be fully autonomous within a defined boundary while requiring human oversight outside it. This is directly analogous to defining "safe zones" in software where automation can operate freely.

**Sources**:
- [SAE J3016 Visual Chart (SAE International)](https://legacy.sae.org/binaries//content/assets/cm/content/blog/sae-j3016-visual-chart_5.3.21.pdf)
- [SAE J3016 User Guide (CMU)](https://users.ece.cmu.edu/~koopman/j3016/index.html)
- [SAE J3016 Update Announcement](https://www.sae.org/blog/sae-j3016-update)

### 1.3 Variable Autonomy in Robotics

Research on human-robot interaction (HRI) has developed the concept of **variable autonomy** -- a paradigm where the level of control can change dynamically during task execution. Beer et al. propose a framework for levels of robot autonomy (LORA) based on a 10-point taxonomy.

Key findings from swarm robotics research at CMU:
- Operators switch the degree of autonomy when their trust in the system drops
- Trust is modeled computationally and correlates with observed system performance
- "Mixed-initiative" control (where either human or robot can initiate autonomy changes) outperforms fixed-level approaches

A related concept is **event-triggered robot self-assessment**: the robot monitors its own performance and signals when it believes its autonomy level should be adjusted, rather than relying solely on the human operator's judgment.

**Sources**:
- [Framework for Levels of Robot Autonomy in HRI (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5656240/)
- [Models of Trust in Human Control of Swarms (IEEE)](https://ieeexplore.ieee.org/document/8651317/)
- [Event-Triggered Robot Self-Assessment (Frontiers)](https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2023.1294533/full)
- [Trust of Humans in Supervisory Control of Swarm Robots (CMU)](https://www.ri.cmu.edu/publications/trust-of-humans-in-supervisory-control-of-swarm-robots-with-varied-levels-of-autonomy/)

---

## 2. Software Engineering Parallels

### 2.1 Progressive Delivery as a Trust-Building Pattern

Progressive delivery in CI/CD is a direct implementation of graduated autonomy applied to software deployment:

1. **Canary release** -- deploy to a small subset (e.g., 1-5% of traffic)
2. **Monitor** -- observe error rates, latency, user feedback
3. **Expand** -- if metrics are healthy, increase to 10%, 25%, 50%, 100%
4. **Rollback** -- if metrics degrade, instantly revert to 0%

This mirrors the trust calibration formula: confidence increases through demonstrated success, and a single failure triggers immediate intervention. Feature flag platforms (LaunchDarkly, Unleash, Flagsmith) provide the infrastructure for percentage-based rollouts with automated monitoring.

The progressive delivery philosophy is: "make the smallest change possible that builds shared knowledge and trust." Each successful deployment at a given percentage builds confidence to increase the percentage further.

**Key pattern**: The rollout percentage is a direct numeric encoding of trust. 5% = low trust (initial canary). 100% = full trust (general availability).

**Sources**:
- [What is Progressive Delivery? (Harness)](https://www.harness.io/harness-devops-academy/progressive-delivery)
- [Canary Deployment Strategy (OpsMx)](https://www.opsmx.com/blog/what-is-canary-deployment/)
- [Feature Flag Progressive Rollouts (Unleash)](https://www.getunleash.io/feature-flag-use-cases-progressive-or-gradual-rollouts)
- [Percentage Rollouts (LaunchDarkly)](https://launchdarkly.com/docs/home/releases/percentage-rollouts)
- [Feature Flag Progressive Rollouts from CI/CD (OneUptime)](https://oneuptime.com/blog/post/2026-02-09-feature-flag-progressive-rollouts-cicd/view)

### 2.2 Code Review Escalation Patterns

Modern code review workflows implement risk-based routing that parallels trust-based autonomy:

| Change Category | Review Path | Trust Level |
|----------------|-------------|-------------|
| Documentation-only, passing automated checks | Auto-approve | High |
| Formatting, style-only changes | Single peer review | Medium-High |
| Standard feature code from senior devs | Standard peer review | Medium |
| Code from junior developers, high complexity | Senior engineer review | Medium-Low |
| Security-sensitive paths | Senior security review | Low |
| Cross-service, architectural changes | Architectural review + checklist | Minimal |

The pattern is: **AI handles the routine, humans handle the exceptional**. AI tools police style, flag boilerplate risks, and generate baseline tests. Humans focus on architectural decisions, business logic, and trade-offs. Trust in automation is built through a pipeline that exercises changes in context (agentic test generation) rather than just static analysis.

**Sources**:
- [Code Review Best Practices 2026 (CodeAnt)](https://www.codeant.ai/blogs/good-code-review-practices-guide)
- [When to Use Manual Code Review Over Automation (Augment Code)](https://www.augmentcode.com/guides/when-to-use-manual-code-review-over-automation)
- [Code Review Automation: 5 Key Capabilities (CodeSee)](https://www.codesee.io/learning-center/code-review-automation)

### 2.3 CI/CD as a Trust Pipeline

The CI/CD pipeline itself is a graduated trust mechanism:

```
Commit -> Lint -> Unit Test -> Integration Test -> Staging -> Canary -> Production
```

Each gate represents a trust checkpoint. Passing each gate increases confidence that the change is safe. Failure at any gate halts progression. The pipeline encodes organizational trust policy as executable infrastructure.

---

## 3. AI Safety Research on Oversight

### 3.1 Scalable Oversight

Anthropic identifies scalable oversight as one of the central challenges in AI safety. The core problem: humans cannot provide sufficient high-quality feedback to train and supervise AI systems at scale. The proposed solutions involve using AI to amplify human oversight capacity:

- **Constitutional AI (CAI)**: AI systems generate potentially problematic inputs, evaluate their own responses against a constitution, and train themselves toward improved behavior. This is automated self-supervision with human-defined values.
- **AI-AI Debate**: Multiple AI systems argue opposing positions; a human judge evaluates the arguments. This amplifies human ability to evaluate complex outputs.
- **Model-Generated Evaluations**: AI systems create evaluation benchmarks and red-team themselves.
- **Process-Oriented Training**: Training systems to follow transparent, justifiable processes rather than rewarding opaque successful outcomes. This ensures human experts can understand the individual steps the AI follows.

Anthropic's research agenda includes "extensions of CAI, variants of human-assisted supervision, versions of AI-AI debate, red teaming via multi-agent RL, and the creation of model-generated evaluations."

**Sources**:
- [Core Views on AI Safety (Anthropic)](https://www.anthropic.com/news/core-views-on-ai-safety)
- [Claude's Constitution (Anthropic)](https://www.anthropic.com/news/claudes-constitution)
- [Human-AI Complementarity: A Goal for Amplified Oversight (DeepMind Safety Research)](https://deepmindsafetyresearch.medium.com/human-ai-complementarity-a-goal-for-amplified-oversight-0ad8a44cae0a)
- [Scalable Oversight in AI: Beyond Human Supervision (Medium)](https://medium.com/@prdeepak.babu/scalable-oversight-in-ai-beyond-human-supervision-d258b50dbf62)

### 3.2 Constitutional AI as a Form of Harness

Constitutional AI demonstrates a pattern where:
1. A **constitution** (set of principles) defines acceptable behavior -- this is the **quality gate**
2. The model **self-evaluates** against the constitution during training -- this is the **harness**
3. Human involvement is limited to defining the constitution and reviewing aggregate results -- this is **scalable oversight**

This is directly analogous to the guardrail + harness architecture: the constitution is the guardrail, the self-evaluation loop is the harness, and the reduced human involvement is the earned autonomy.

### 3.3 "Trust But Verify" in Practice

California's SB 53 legislation codifies a "trust, but verify" approach to AI governance:
- Largest AI companies must publicly disclose safety protocols
- They must report critical safety incidents
- Whistleblower protections are mandated

This mirrors software engineering's approach: organizations trust their automation (CI/CD, auto-merge) but maintain verification mechanisms (monitoring, alerting, audit logs, rollback capabilities).

**Source**:
- [California AI Law SB 53 (Senator Wiener)](https://sd11.senate.ca.gov/news/governor-newsom-signs-senator-wieners-landmark-ai-law-set-commonsense-guardrails-boost)

---

## 4. Earned Autonomy: Implementations and Evidence

### 4.1 Anthropic's Empirical Evidence from Claude Code

Anthropic's research on Claude Code usage provides the strongest empirical evidence for earned autonomy in AI agent systems (published February 2026):

**Trust accumulates gradually**:
- New users (<50 sessions): full auto-approve in ~20% of sessions
- Experienced users (~750 sessions): full auto-approve in ~40%+ of sessions
- The increase is smooth, not stepped, suggesting continuous trust building

**Oversight strategy evolves, not disappears**:
- Interrupt rate actually *increases* with experience (5% for new users, ~9% for experienced users)
- Experienced users shift from approving individual actions to monitoring and intervening when needed
- This mirrors the Sheridan-Verplank shift from Level 5 (execute if human approves) to Level 7 (execute, inform human)

**Session duration grows with trust**:
- 99.9th percentile turn duration nearly doubled from <25 minutes to >45 minutes (Oct 2025 - Jan 2026)
- Growth is smooth across model releases, indicating user trust, not just model capability

**Self-limiting behavior**:
- The agent asks clarification questions more than twice as often on difficult tasks
- 80% of tool calls involve at least one safety mechanism
- 73% have human involvement
- Autonomy is co-constructed by model, user, and product

**Key recommendation**: Oversight requirements that prescribe specific interaction patterns (e.g., approving every action) create friction without safety benefits. Effective oversight positions humans to monitor and redirect rather than approve each step.

**Sources**:
- [Measuring AI Agent Autonomy in Practice (Anthropic)](https://www.anthropic.com/research/measuring-agent-autonomy)
- [AI Agent Autonomy Rises as Users Gain Trust (Digital Watch)](https://dig.watch/updates/ai-agent-autonomy-rises-as-users-gain-trust-in-anthropics-claude-code)
- [Anthropic Study: AI Agents Run 45 Minutes Autonomously as Trust Builds (Blockchain News)](https://blockchain.news/news/anthropic-ai-agent-autonomy-study-claude-code)

### 4.2 Staged Autonomy in Enterprise AI

The enterprise pattern for earned autonomy follows a staged approach:

1. **Sandbox / Read-Only Mode**: AI operates in a contained environment. Outputs are observed but not acted upon. This builds initial trust.
2. **Low-Risk Automation**: Automate well-understood, easily verifiable tasks. AI earns its initial "miles."
3. **Graduated Permission Expansion**: Progressive permission levels based on demonstrated reliability.
4. **Continuous Monitoring with Adaptive Governance**: Governance frameworks adapt based on operational experience.

The principle is: "Full autonomy is not achieved by skipping steps, but rather by demonstrating safety at every stage."

**Sources**:
- [How to Scale Agentic AI Safely (Nemko Digital)](https://digital.nemko.com/insights/how-to-scale-agentic-ai-safely-build-trust-in-autonomous-systems)
- [How to Build Trust in AI-Powered Security Remediation (Tamnoon)](https://tamnoon.io/blog/building-trust-in-automated-remediation/)
- [Agentic AI Governance: An Enterprise Guide (Writer)](https://writer.com/guides/agentic-ai-governance/)

---

## 5. Human-AI Collaboration Models

### 5.1 The Five-Level Framework for AI Agent Autonomy (Knight/Columbia, 2025)

Feng & McDonald propose a framework defining five levels of AI agent autonomy characterized by the *role the user takes*:

| Level | User Role | Description |
|-------|-----------|-------------|
| L1 | **Operator** | User directs and decides. Agent provides on-demand support. |
| L2 | **Collaborator** | User and agent plan, delegate, and execute together. |
| L3 | **Consultant** | Agent leads planning and execution; consults user for expertise. |
| L4 | **Approver** | Agent engages user only in risky/failure/pre-specified scenarios. |
| L5 | **Observer** | Agent operates with full autonomy. User monitors with emergency off-switch. |

A crucial design principle: **autonomy is a design choice, not a technical inevitability**. A highly capable agent can still operate at L1 if designed to consult its user before every action. Capability and autonomy are independent dimensions.

**Sources**:
- [Levels of Autonomy for AI Agents (Knight First Amendment Institute)](https://knightcolumbia.org/content/levels-of-autonomy-for-ai-agents-1)
- [Levels of Autonomy for AI Agents (arXiv)](https://arxiv.org/abs/2506.12469)
- [Why AI Agent Autonomy Should Be a Design Choice (Ken Priore)](https://kenpriore.com/why-ai-agent-autonomy-should-be-a-design-choice-not-a-technical-inevitability/)

### 5.2 Unified Trust-Autonomy Framework (SOC Domain)

A 2025 paper by researchers working on SOC (Security Operations Center) operations provides a mathematically formalized framework for trust-based autonomy allocation:

**Autonomy equation**:
```
A = 1 - (lambda_1 * C + lambda_2 * R) * (1 - T)
```
Where:
- `A` = autonomy level (0 to 1)
- `C` = task complexity (0 to 1)
- `R` = task risk (0 to 1)
- `T` = trust level (0 to 1)
- `lambda_1, lambda_2` = weighting parameters

**Trust calibration equation**:
```
T = alpha_1 * E + alpha_2 * P + alpha_3 * (1 - U)
```
Where:
- `E` = explainability (how interpretable are the agent's actions)
- `P` = performance history (track record of correct decisions)
- `U` = uncertainty (agent's self-reported confidence)
- `alpha_1 + alpha_2 + alpha_3 = 1`

**Human-in-the-loop is inverse of autonomy**:
```
H = 1 - A
```

This gives concrete decision rules:
| Scenario | Autonomy | Trust Required | HITL Role |
|----------|----------|----------------|-----------|
| Novel, high-stakes tasks | 0.1 - 0.3 | Low | Full human control |
| Moderate complexity | 0.4 - 0.7 | Medium | Balanced supervision |
| Routine, low-risk tasks | 0.8 - 1.0 | High | Minimal oversight |

**Source**:
- [A Unified Framework for Human-AI Collaboration in SOC with Trusted Autonomy (arXiv)](https://arxiv.org/abs/2505.23397)

### 5.3 Six Paradigms of Human-AI Interaction

Research identifies six paradigms for human involvement:

1. **Human-in-the-Loop (HITL)**: Active, direct human intervention in every decision cycle
2. **Human-on-the-Loop (HOTL)**: Human monitors and can intervene but AI acts autonomously by default
3. **Human-out-of-the-Loop (HOOTL)**: Full AI autonomy; human receives reports only
4. **Automated**: AI acts alone on routine tasks
5. **Augmented**: AI enhances human decision-making
6. **Collaborative**: Iterative, reciprocal partnership with dynamic handoff

The selection depends on a **decision matrix** evaluating task complexity, urgency, and risk level. The modern trend is shifting from "human as supervisor, AI as tool" toward "adaptive, reciprocal partnership."

**Sources**:
- [Human-AI Collaboration Framework (Emergent Mind)](https://www.emergentmind.com/topics/human-ai-collaboration-framework)
- [Human-AI Collaboration (The Decision Lab)](https://thedecisionlab.com/reference-guide/computer-science/human-ai-collaboration)
- [Beyond Human-in-the-Loop (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S2666188825007166)

### 5.4 AWS Agentic AI Security Scoping Matrix

AWS proposes a security framework with four architectural scopes for agentic AI, graduated by autonomy level:
- Organizations should start with lower autonomy implementations
- Gradually advance through the scopes as organizational confidence and security capabilities mature
- Each scope introduces new capabilities and corresponding security requirements
- This approach minimizes risk while building operational experience

**Source**:
- [The Agentic AI Security Scoping Matrix (AWS)](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/)

---

## 6. Synthesis: Patterns for a Guardrail + Harness Architecture

### 6.1 Cross-Domain Convergence

Across robotics, software engineering, and AI safety, the same fundamental pattern recurs:

```
Define Boundary -> Start Constrained -> Demonstrate Success -> Earn Expansion -> Monitor Continuously
```

| Domain | Boundary Definition | Trust Signal | Expansion Mechanism | Monitoring |
|--------|-------------------|--------------|---------------------|------------|
| Autonomous Vehicles | ODD (Operational Design Domain) | Miles driven without incident | Expand ODD boundaries | Telemetry, disengagement reports |
| CI/CD | Canary percentage | Error rates, latency | Increase rollout % | Metrics dashboards, auto-rollback |
| Code Review | Risk classification | Historical accuracy | Auto-merge for proven categories | Audit logs, regression tracking |
| AI Agents | Permission scope | Task completion, user satisfaction | Grant broader tool access | Interrupt rates, safety mechanism triggers |
| Constitutional AI | Constitution (principles) | Alignment evaluations | Reduce human review frequency | Red teaming, model evaluations |

### 6.2 Key Design Principles

1. **Autonomy is a continuous spectrum, not a binary**. Systems should support fine-grained trust levels (Sheridan-Verplank 1-10, SAE 0-5, canary 0-100%).

2. **Trust is multi-dimensional**. It depends on explainability, performance history, and uncertainty (the SOC trust formula). A system may be trusted for routine tasks but not for novel ones.

3. **Oversight evolves, it does not disappear**. Anthropic's data shows experienced users interrupt *more* often but approve *less* often. The nature of oversight shifts from gatekeeping to monitoring.

4. **Self-assessment enables earned autonomy**. The most effective systems (Constitutional AI, event-triggered robot self-assessment) recognize their own limitations and escalate proactively.

5. **Operational Design Domain scoping is critical**. Full autonomy within a defined boundary, mandatory escalation outside it. The boundary expands as trust grows.

6. **Rollback must be instant and cheap**. Progressive delivery and feature flags work because reverting is trivial. Earned autonomy requires a safety net.

7. **Capability and autonomy are independent axes**. A highly capable system can be run at low autonomy (Knight/Columbia L1). Autonomy is a design choice, not a technical inevitability.

### 6.3 Proposed Trust-Based Supervision Model

Drawing from all sources, a concrete model for the guardrail + harness architecture:

```
Trust Score = w1 * PerformanceHistory + w2 * TaskFamiliarity + w3 * (1 - Risk) + w4 * Explainability

Supervision Level = f(Trust Score, Task Risk, Context Novelty)

If Supervision Level == HIGH:
    Mode = HITL (human approves every action)

If Supervision Level == MEDIUM:
    Mode = HOTL (human monitors, agent acts, escalate on uncertainty)

If Supervision Level == LOW:
    Mode = HOOTL (agent acts autonomously, periodic audit)

Trust Score updates after every task cycle:
    If task succeeded: Trust += delta (small positive increment)
    If task failed:    Trust -= Delta (large negative decrement, asymmetric)
    If agent self-escalated correctly: Trust += bonus
```

This model captures:
- **Asymmetric trust dynamics**: Trust is slow to build, fast to lose (like canary deployments)
- **Self-escalation bonus**: Agents that recognize their limitations earn trust faster
- **Continuous recalibration**: Trust is not static but constantly updated based on evidence
- **Risk-modulated autonomy**: High trust + low risk = high autonomy; high trust + high risk = medium autonomy

---

## 7. Implications for Project Design

1. **Phase gates (PLANNING/BUILDING/AUDITING) map to ODD boundaries**: Each phase defines the operational domain where certain actions are permitted. Crossing phase boundaries requires explicit human approval, analogous to leaving an ODD.

2. **The Three Agents Model is a form of AI-AI debate**: The Affirmative/Critical/Mediator pattern mirrors Anthropic's scalable oversight research on using multiple AI perspectives to improve decision quality.

3. **Progressive delivery applies to feature development**: New features should start with restricted scope (canary), expand through demonstrated success, and have instant rollback capability.

4. **The security command allow/deny list is a trust boundary**: Commands on the allow list are within the ODD (autonomous execution). Deny list commands require human escalation. Over time, well-tested operations could be promoted from deny to allow.

5. **Constitutional AI provides a model for self-supervision**: The CLAUDE.md constitution defines values and principles. The agent's self-assessment against these principles is a form of constitutional AI applied to development workflow.

---

## References (Complete List)

### Robotics & Autonomous Systems
- Sheridan & Verplank (1978): [LOA Taxonomy](https://www.researchgate.net/figure/Sheridan-and-Verplanks-original-levels-of-automation-2_tbl1_337253476)
- SAE J3016: [Visual Chart](https://legacy.sae.org/binaries//content/assets/cm/content/blog/sae-j3016-visual-chart_5.3.21.pdf) | [User Guide](https://users.ece.cmu.edu/~koopman/j3016/index.html)
- Beer et al.: [Framework for LORA in HRI](https://pmc.ncbi.nlm.nih.gov/articles/PMC5656240/)
- IEEE: [Trust in Human Control of Swarms](https://ieeexplore.ieee.org/document/8651317/)
- Frontiers: [Event-Triggered Robot Self-Assessment](https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2023.1294533/full)

### Software Engineering
- Harness: [Progressive Delivery](https://www.harness.io/harness-devops-academy/progressive-delivery)
- LaunchDarkly: [Percentage Rollouts](https://launchdarkly.com/docs/home/releases/percentage-rollouts)
- Unleash: [Feature Flag Progressive Rollouts](https://www.getunleash.io/feature-flag-use-cases-progressive-or-gradual-rollouts)
- OneUptime: [Feature Flag Progressive Rollouts from CI/CD](https://oneuptime.com/blog/post/2026-02-09-feature-flag-progressive-rollouts-cicd/view)
- CodeAnt: [Code Review Best Practices 2026](https://www.codeant.ai/blogs/good-code-review-practices-guide)
- Augment Code: [Manual vs Automated Code Review](https://www.augmentcode.com/guides/when-to-use-manual-code-review-over-automation)

### AI Safety & Oversight
- Anthropic: [Core Views on AI Safety](https://www.anthropic.com/news/core-views-on-ai-safety)
- Anthropic: [Claude's Constitution](https://www.anthropic.com/news/claudes-constitution)
- Anthropic: [Measuring AI Agent Autonomy](https://www.anthropic.com/research/measuring-agent-autonomy)
- DeepMind: [Human-AI Complementarity for Amplified Oversight](https://deepmindsafetyresearch.medium.com/human-ai-complementarity-a-goal-for-amplified-oversight-0ad8a44cae0a)
- California SB 53: [Trust But Verify AI Legislation](https://sd11.senate.ca.gov/news/governor-newsom-signs-senator-wieners-landmark-ai-law-set-commonsense-guardrails-boost)

### Earned Autonomy & Trust Building
- Nemko Digital: [Scaling Agentic AI Safely](https://digital.nemko.com/insights/how-to-scale-agentic-ai-safely-build-trust-in-autonomous-systems)
- Tamnoon: [Trust in AI-Powered Remediation](https://tamnoon.io/blog/building-trust-in-automated-remediation/)
- Writer: [Agentic AI Governance Guide](https://writer.com/guides/agentic-ai-governance/)

### Human-AI Collaboration
- Feng & McDonald: [Levels of Autonomy for AI Agents (Knight/Columbia)](https://knightcolumbia.org/content/levels-of-autonomy-for-ai-agents-1) | [arXiv](https://arxiv.org/abs/2506.12469)
- SOC Framework: [Unified Framework for Human-AI Collaboration with Trusted Autonomy](https://arxiv.org/abs/2505.23397)
- AWS: [Agentic AI Security Scoping Matrix](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/)
- The Decision Lab: [Human-AI Collaboration](https://thedecisionlab.com/reference-guide/computer-science/human-ai-collaboration)
- Ken Priore: [AI Agent Autonomy as Design Choice](https://kenpriore.com/why-ai-agent-autonomy-should-be-a-design-choice-not-a-technical-inevitability/)
