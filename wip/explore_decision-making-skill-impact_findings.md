# Exploration Findings: Decision-Making Skill Impact

## Key Insights

### 1. The decision skill IS the design skill's Phase 1-2, generalized

The current design skill's advocate fan-out (Phase 1) and side-by-side comparison (Phase 2) map almost entirely to the decision skill's Phases 1-6. The decision skill adds two things the design skill lacks: **peer revision** (advocates see each other's work) and **cross-examination** (adversarial dialogue between advocates). The design skill would delegate its most complex internal logic to the decision skill and keep the orchestration: decision decomposition, multi-decision coordination, format adaptation, and all post-decision phases.

### 2. A canonical decision report structure bridges all consumers

The decision skill's output and the design doc's Considered Options share most fields but have two gaps: **Assumptions** (no home in design docs or ADRs today) and **per-decision Consequences** (exists in ADRs but not in decision skill output). A canonical structure — Context, Assumptions, Chosen, Rationale, Alternatives, Consequences — serves both standalone ADRs and embedded design doc sections. The decision skill produces at maximum detail; consumers compress.

### 3. Hybrid invocation: agents for parallel, inline for single

For multi-decision contexts (design skill running 3-5 decisions), use the Task agent pattern (proven in plan Phase 4). For single-decision contexts (explore crystallizing to Decision Record), read the SKILL.md inline. The working directory maps onto the flat wip/ convention using composite prefixes.

### 4. Multi-decision orchestration needs three new design-skill concerns

The design skill gains: (a) a decision decomposition step identifying independent decision questions, (b) a coordination manifest tracking parallel decisions, and (c) a cross-validation sub-phase checking assumptions across completed decisions. Cross-validation needs a termination bound (max 2 rounds) to prevent infinite oscillation.

### 5. Explore hands off, doesn't merge

Explore discovers THAT a decision is needed. The decision skill MAKES the decision. They're sequential, not overlapping. Explore's crystallize framework stays inline (mechanical scoring, not a substantive decision). When crystallize selects Decision Record, explore writes a decision brief and hands off to the decision skill — same pattern as /design and /prd handoffs.

### 6. Phase file discipline holds with a fast path

Individual decision phases estimate at 80-160 lines each — within the 150-line target if templates are extracted. The complexity breaks at 10+ serial user interactions without visible progress. A fast path (4 phases for simple decisions, all 7 for critical) keeps the proposal within budget at 2 nesting levels.

## Tensions

### Orchestration ownership
The decision skill must stay isolated (no parent awareness), but cross-validation requires knowledge of peer decisions. Resolution: the design skill owns cross-validation, not the decision skill. The decision skill takes a question, produces a report, knows nothing about siblings.

### Lightweight vs formal decisions
Design Phase 4 currently discovers implicit decisions during architecture writing. These are too lightweight for the 7-phase framework. Resolution: keep implicit decisions inline in the design skill (AskUserQuestion pattern). Reserve the decision skill for deliberate, multi-alternative decisions identified up front.

### Status tracking dual-write risk
If the design skill maintains a decisions.yaml tracker AND the decision skill writes artifacts, they can disagree. Resolution: derive status from artifact existence (check for report.md), don't maintain a separate status field.

## Round 2 Insights

### 7. Non-interactive mode reshapes all skills, not just decisions

39 blocking points across all 5 workflow skills. 28% are researchable (agent could find the answer), 49% are judgment calls (most already have recommendation heuristics), 26% are approval gates. In non-interactive mode, the agent follows its own recommendation, documents the choice as an assumption, and continues. Only genuine safety gates (CI failures) should halt.

### 8. A four-tier decision spectrum unifies lightweight and heavyweight

| Tier | Method | When |
|------|--------|------|
| Trivial | Just do it, no record | One reasonable option, instantly reversible |
| Lightweight | 3-step micro-protocol (frame, gather, decide) | 2-3 options, available context favors one |
| Standard | Decision skill fast path (4 phases) | 3+ contested options, needs targeted research |
| Critical | Decision skill full 7-phase | Irreversible, high-stakes, adversarial evaluation needed |

The lightweight micro-protocol IS the heavyweight framework with the middle compressed. Same assumption-tracking, same review surface, same manifest. Escalation from lightweight to heavyweight preserves context.

### 9. Structured decision blocks are the universal record format

HTML comment delimiters (`<!-- decision:start/end -->`) make blocks machine-extractable but invisible in rendered markdown. Required fields: Question, Choice, Assumptions. The same block format works inline in wip/ artifacts (lightweight) and as the core of decision reports (heavyweight). A decision manifest indexes all decisions for end-of-workflow review.

### 10. Non-interactive mode is signaled by `--auto` flag

Propagates naturally — sub-agents already run non-interactively. The flag controls whether the agent presents decisions for confirmation (interactive) or documents and continues (non-interactive). Approval gates auto-approve when validation passes, halt when the agent detects quality issues.

## Tensions (Round 2)

### Assumption review burden
In non-interactive mode with a complex design doc (5 decisions x multiple assumptions each), the review surface could be 20+ assumptions. Need to distinguish high-confidence assumptions (barely worth reviewing) from low-confidence ones (flagged with `status="assumed"`).

### Explore's conversational phases
Explore Phase 1 and PRD Phase 1 are inherently dialogic — the agent doesn't know what to investigate without user input. In non-interactive mode, these phases must derive scope entirely from `$ARGUMENTS`, issue bodies, and codebase analysis. This works when invoked with a specific topic but fails for genuinely open-ended exploration.

## Gaps (Updated)

### Decision brief format not standardized
Explore handoff, design agent spawning, and standalone invocation all need the same input contract. The lightweight decision block format could serve as the brief (it has Question, Evidence, Constraints) but this isn't confirmed.

### "Decision Record" vs "ADR" naming
Still unresolved. "Decision Record" is broader.

### Round limit for non-interactive explore loops
If explore runs in non-interactive mode and keeps finding gaps, it could loop indefinitely. Need a round limit (e.g., max 3 rounds before auto-crystallizing).

## Decision: Crystallize

Artifact type: Design Doc. Multiple technical decisions need considered options
(decision block format, invocation model, non-interactive mechanics, multi-decision
orchestration). The what-to-build is understood; the how needs architecture.
