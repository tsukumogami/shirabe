---
status: Proposed
problem: |
  Shirabe's workflow skills make decisions at 39 blocking points across 5 skills,
  using AskUserQuestion as the universal mechanism. Agents ask before researching,
  decisions aren't structurally recorded, and workflows can't run autonomously.
decision: |
  A three-layer decision system: a heavyweight decision skill (7-phase bakeoff for
  contested choices), a lightweight decision protocol (3-step micro-workflow for
  inline choices), and a non-interactive execution mode (--auto flag) that lets all
  workflows run end-to-end by making assumptions instead of blocking. All three layers
  share a common decision block format (HTML comment delimiters), assumption tracking,
  and a unified review surface.
rationale: |
  A single heavyweight framework is too expensive for the 49% of decisions that are
  routine judgment calls. A lightweight-only approach misses the value of adversarial
  evaluation for contested architectural choices. The three-layer system matches
  decision weight to evaluation depth while maintaining a single assumption-tracking
  mechanism that enables non-interactive execution across all skills.
---

# DESIGN: Decision Framework

## Status

Proposed

## Context and Problem Statement

Shirabe's 5 workflow skills (explore, design, prd, plan, work-on) block on user
input at 39 points. 28% are questions the agent could answer by researching first.
49% are judgment calls where the agent already computes a recommendation but waits
for confirmation. 26% are approval gates.

Issue #6 proposes a structured decision-making skill -- a 7-phase workflow (research,
alternatives, validation bakeoff, peer revision, cross-examination, synthesis, report)
that generalizes the design skill's advocate pattern into a reusable component.

The decision skill alone doesn't solve the full problem. Lightweight decisions
(decomposition strategy, loop exits, implicit architecture choices) need the same
assumption-tracking discipline without the overhead of 7 phases. And all skills need
a non-interactive mode where the agent exhausts research, makes assumptions, and
lets the user review at the end.

This design covers three tightly coupled components:

1. **The decision-making skill** (heavyweight, 7 phases)
2. **A lightweight decision protocol** (3-step micro-workflow)
3. **A non-interactive execution mode** (cross-cutting)

## Decision Drivers

- Decisions must be recorded structurally, not lost in conversation logs
- The same assumption-tracking pattern must work for both heavyweight and lightweight decisions
- Non-interactive mode must work across all skills without per-skill special-casing
- The decision skill must be invocable as a sub-operation (by design, explore) and standalone
- Multi-decision orchestration (design docs with 3-5 decision questions) needs parallel execution with cross-validation
- Phase files must stay focused and under 150 lines despite increased complexity
- The output of a decision must map directly into a design doc's Considered Options section with zero information loss

## Considered Options

### Decision 1: Decision block format

How should decision records be delimited and structured?

#### Chosen: HTML comment delimiters with markdown content

```markdown
<!-- decision:start id="cache-strategy" status="confirmed" -->
### Decision: Cache invalidation strategy

**Question:** Which cache invalidation strategy for the API layer?

**Evidence:** Current system uses TTL-based caching. Event bus exists but
adds 8ms latency. Consistency requirements are eventual (30s acceptable).

**Choice:** TTL-based with 30-second expiry

**Alternatives considered:**
- Event-driven: adds infrastructure dependency for marginal consistency gain

**Assumptions:**
- 30-second staleness is acceptable for all current API consumers
- Event bus latency won't improve enough to change the calculus

**Consequences:** Simpler to operate. Accepts brief staleness windows.
<!-- decision:end -->
```

HTML comments are machine-extractable via simple regex, invisible in rendered
markdown (block content renders normally, delimiters disappear), and support
metadata attributes (`id`, `status`) without inventing syntax. Agents reliably
produce them. The content between delimiters is standard markdown that agents
write naturally.

Required fields: Question, Choice, Assumptions. Evidence, Alternatives,
Consequences, and Reversibility included when non-trivial.

Compact variant for simple decisions:

```markdown
<!-- decision:start id="branch-name" status="confirmed" -->
**Decision:** Branch `feat/parser` -- follows existing `feat/<component>`
convention. Assumes no parallel parser work.
<!-- decision:end -->
```

Status values: `confirmed` (evidence-based, high confidence), `assumed`
(best guess, pending review), `escalated` (lightweight upgraded to heavyweight).

#### Alternatives considered

- **YAML blocks**: constrain content to YAML-safe strings, agents produce
  them less reliably, and multiline content is awkward in YAML
- **Heading conventions** (e.g., `### Decision: ...` without delimiters):
  fragile extraction (heading levels conflict with document structure), no
  metadata attributes, can't distinguish decision blocks from regular headings

### Decision 2: Assumption review surface

Where do assumptions appear for end-of-workflow review?

#### Chosen: Three-layer review surface

1. **Source of truth**: `wip/<workflow>_<topic>_assumptions.md` -- written
   incrementally during execution. Each assumption has an ID, the decision it
   belongs to, confidence level, and a "if wrong" restart path.

2. **Terminal summary**: printed at workflow end. Lists all assumptions with
   confidence levels. Highlights `status="assumed"` decisions that need attention.

3. **PR body section**: when a PR is created, assumptions are added as a
   dedicated section. Reviewers see them alongside the code changes.

All three derive from the wip/ artifact. No dual-write -- the terminal summary
and PR body are read-only views.

#### Alternatives considered

- **Terminal only**: lost when the session ends; PR reviewers don't see assumptions
- **PR body only**: not available until PR creation; the user can't review
  mid-workflow
- **Separate artifact only**: not visible to PR reviewers without extra clicks

### Decision 3: Lightweight-to-heavyweight escalation

What happens when a lightweight decision turns out to need deeper evaluation?

#### Chosen: Partial block with status="escalated" feeds into decision skill

During Step 2 (gather) of the lightweight protocol, if the agent determines the
decision is Tier 3+, it:

1. Writes a partial decision block with Question and Evidence gathered so far
2. Marks it `status="escalated"`
3. Invokes the decision skill (via agent spawn)
4. The decision skill reads the partial block as seed context
5. The decision skill's report replaces the partial block in the manifest

This preserves all framing and evidence work. The decision skill's Phase 1
(research) can skip or abbreviate what the lightweight protocol already gathered.

#### Alternatives considered

- **Restart from scratch**: discards the lightweight framing and evidence work,
  violating the zero-information-loss constraint
- **Always complete lightweight first**: forces a potentially unsupported decision,
  then runs heavyweight separately, creating dual records for the same question

### Decision 4: Invocation model for multi-decision contexts

How does a parent skill invoke the decision skill?

#### Chosen: Hybrid with static dispatch

- **Design skill** always uses Task agents (parallel, one per decision question).
  Follows the proven plan Phase 4 pattern: fan-out with `run_in_background`,
  collect via TaskOutput, validate, retry on failure.
- **Explore skill** always uses inline execution (reads decision SKILL.md,
  follows phases in its own context). Avoids serialization overhead for a
  single decision.

Each parent knows at development time which mode to use. No runtime branching.

**Exception**: if explore escalates a lightweight decision to heavyweight
(Decision 3), it spawns a one-off agent. This breaks the "always inline" rule
but escalation is rare enough that the exception doesn't undermine the model.

**Agent prompt compilation**: for the Task agent path, the parent pre-compiles
the decision skill's phases into a single prompt (3-5K tokens). The agent
doesn't load phase files from disk -- it receives everything inline. This is
proven viable by plan Phase 4's 220-line agent prompts.

#### Alternatives considered

- **Always agent**: simpler contract but adds unnecessary agent spawn overhead
  for explore's single-decision case, and loses explore's loaded context
- **Always inline**: can't parallelize design's 3-5 decisions; serial execution
  adds 3-5x wall-clock time
- **Dynamic dispatch**: parent decides at runtime based on decision count;
  adds branching complexity for minimal gain over static dispatch

### Decision 5: Cross-validation loop termination

How does the design skill prevent infinite loops when decisions conflict?

#### Chosen: Single pass with bounded restart

Cross-validation runs once after all decisions complete:

1. Read all decision outputs and their assumptions
2. Check each assumption against peer decisions' choices
3. Flag conflicts
4. Restart conflicting decisions once with peer constraints injected
5. Accept remaining conflicts as assumptions with documented remediation paths

No second validation round. If a restarted decision creates a new conflict with
a third decision, the conflict is recorded as an assumption ("these two decisions
may tension; monitor during implementation").

This avoids the loop termination problem entirely. Restarted decisions receive
the conflicting decision's output as a constraint, which steers away from new
conflicts in most cases.

#### Alternatives considered

- **Fixed round limit (max 2)**: adds the complexity of a loop, convergence
  tracking, and a "what to do after 2 rounds" fallback -- all for handling
  a scenario (restart-creates-new-conflict) that's unlikely with constraint injection
- **Convergence detection**: requires tracking conflict identity across rounds;
  overengineered for the initial implementation

### Decision 6: Design skill phase restructuring

How should the design skill's phases change to accommodate decision delegation?

#### Chosen: 8 phases (0-7), cross-validation as its own phase

```
Phase 0: SETUP (unchanged)
Phase 1: DECISION DECOMPOSITION (new -- identify decision questions)
Phase 2: DECISION EXECUTION (new -- delegates to decision skill per question)
Phase 3: CROSS-VALIDATION (new -- check assumptions across decisions)
Phase 4: INVESTIGATION (slimmed -- implementation focus only, not approach validation)
Phase 5: ARCHITECTURE (was Phase 4)
Phase 6: SECURITY (was Phase 5, unchanged)
Phase 7: FINAL REVIEW (was Phase 6)
```

Decision Decomposition (Phase 1) reads the design doc skeleton's Context and
Decision Drivers sections and identifies independent decision questions using the
existing split criterion from considered-options-structure.md: "options for one
question don't affect options for another." Err toward fewer, broader decisions.

Decision Execution (Phase 2) invokes the decision skill per question via Task
agents. Independent decisions run in parallel. Coupled decisions run sequentially
with earlier results as context.

Cross-Validation (Phase 3) gets its own phase file rather than being a sub-step
of Phase 2. This avoids creating another 400+ line combined file and follows the
single-concern-per-phase pattern.

Investigation (Phase 4) is retained but narrowed: it no longer validates the
approach (the decision skill's bakeoff did that). It focuses on implementation-
level unknowns needed for architecture writing.

Implicit decisions discovered during Architecture (Phase 5) stay inline using
the lightweight micro-protocol. They don't invoke the decision skill -- they're
typically obvious choices where AskUserQuestion (or auto-selection in --auto mode)
is appropriate.

#### Alternatives considered

- **7 phases (merge cross-validation into Phase 2)**: Phase 2 becomes a 400+
  line file handling decision execution, collection, validation, cross-checking,
  restart, and Considered Options writing. Violates the 150-line phase target.
- **9 phases (separate Decision Integration)**: adds a phase between cross-
  validation and investigation for writing Considered Options. Unnecessary --
  Considered Options writing is a natural step within cross-validation completion.

### Decision 7: Non-interactive mode signaling

How is non-interactive mode activated and propagated?

#### Chosen: --auto flag with CLAUDE.md default

`--auto` flag on skill arguments forces non-interactive execution. `--interactive`
forces interactive. Without either flag, read CLAUDE.md `## Execution Mode:`
header (values: `auto` or `interactive`, default: `interactive`).

```
Effective Mode = --auto flag (if present) OR --interactive flag (if present) OR CLAUDE.md default OR interactive
```

This mirrors the existing pattern for scope flags (`--strategic`/`--tactical`
override CLAUDE.md `## Default Scope:`).

Sub-agents don't need the flag -- they inherently can't use AskUserQuestion.
The flag controls only the top-level orchestrator's behavior at decision points.

#### Alternatives considered

- **Environment variable**: invisible in skill arguments, harder to document,
  doesn't integrate with the existing flag-then-CLAUDE.md pattern
- **CLAUDE.md only**: no per-invocation control; can't run one command
  interactively in an otherwise auto project

## Decision Outcome

The three components compose into a unified system:

**At decision points**, the agent classifies the decision's complexity:
- Tier 1 (trivial): just do it, no record
- Tier 2 (lightweight): 3-step micro-protocol, decision block in the current artifact
- Tier 3 (standard): decision skill fast path (phases 0, 1, 2, 6)
- Tier 4 (critical): decision skill full 7-phase (adds validation bakeoff, peer revision, cross-examination)

**In interactive mode**, Tier 2+ decisions present the agent's recommendation
via AskUserQuestion for confirmation. The agent arrives with evidence, not
just a question.

**In non-interactive mode (--auto)**, the agent follows its own recommendation,
records the choice as a decision block with `status="assumed"`, and continues.
Assumptions surface in the review artifact, terminal summary, and PR body.

**For multi-decision contexts** (design docs), the design skill decomposes the
problem into decision questions, runs the decision skill per question in parallel
via agents, then cross-validates assumptions in a single pass.

## Solution Architecture

### Component 1: Decision-Making Skill

A new skill at `skills/decision/` with 7 phases:

| Phase | Purpose | Model Tier | Estimated Lines |
|-------|---------|-----------|-----------------|
| 0 | Context and framing | Fast | 80-100 |
| 1 | Research | Balanced | 120-140 |
| 2 | Alternative presentation | Balanced | 100-130 |
| 3 | Validation bakeoff | Reasoning | 120-150 |
| 4 | Peer revision | Balanced | 80-110 |
| 5 | Cross-examination | Reasoning | 100-130 |
| 6 | Synthesis and report | Fast | 130-160 |

Fast path (Tier 3): phases 0, 1, 2, 6 only (skip bakeoff, peer revision,
cross-examination). ~4 interaction points in interactive mode, 0 in --auto.

Full path (Tier 4): all 7 phases. ~7-10 interaction points in interactive
mode, 0 in --auto.

**Input contract:**

```yaml
decision_context:
  question: "Which cache invalidation strategy?"
  prefix: "design_foo_decision_1"     # wip/ file prefix
  options:                             # optional pre-identified alternatives
    - name: "TTL-based"
      description: "..."
  constraints:
    - "Must support < 100ms latency"
  background: |                        # relevant context from parent
    The system currently uses...
  complexity: "standard"               # standard | critical
```

**Output contract:**

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "TTL-based"
  confidence: "high"
  rationale: "..."
  assumptions:
    - "Redis cluster remains available"
  rejected:
    - name: "Event-driven"
      reason: "Adds infrastructure dependency for marginal gain"
  report_file: "wip/design_foo_decision_1_report.md"
```

The `assumptions` list enables cross-decision conflict detection.

**Output format:** The canonical decision report follows the decision block
format with full detail. When consumed by a design doc, the report maps to
Considered Options sections. When standalone, it serializes to
`docs/decisions/ADR-<topic>.md`.

### Component 2: Lightweight Decision Protocol

A 3-step micro-workflow invoked inline at any decision point:

1. **Frame**: state the question in one sentence
2. **Gather**: check available evidence from loaded context (codebase, prior
   decisions, constraints). Don't ask when you can look up.
3. **Decide and record**: write a decision block in the current artifact

Triggers when any of these hold:
- The decision affects downstream artifacts
- A reasonable person could have chosen differently
- The choice rests on a falsifiable assumption
- Reversing would require rework

Decision blocks are inline in their source artifacts. A decision manifest
(`wip/<workflow>_<topic>_decision-manifest.md`) indexes all blocks for review.

### Component 3: Non-Interactive Execution Mode

Signaled by `--auto` flag or CLAUDE.md `## Execution Mode: auto`.

Behavioral changes at decision points:

| Category | Interactive | Non-Interactive |
|----------|------------|-----------------|
| Researchable (28%) | Research first, then confirm | Research and proceed |
| Judgment calls (49%) | Present recommendation, user confirms | Follow recommendation, document assumption |
| Approval gates (26%) | Present artifact, user approves | Auto-approve if validation passes, document |
| Safety gates (CI failures) | Ask user | Halt execution (never auto-accept failures) |

Assumptions accumulate in `wip/<workflow>_<topic>_assumptions.md` during
execution, surface at the terminal at workflow end, and appear in the PR body.

### Component 4: Design Skill Changes

The design skill restructures from 7 to 8 phases:

```
Phase 0: SETUP
Phase 1: DECISION DECOMPOSITION
Phase 2: DECISION EXECUTION (via decision skill agents)
Phase 3: CROSS-VALIDATION (single pass, bounded restart)
Phase 4: INVESTIGATION (slimmed)
Phase 5: ARCHITECTURE
Phase 6: SECURITY
Phase 7: FINAL REVIEW
```

New artifacts:
- `wip/design_<topic>_decisions.json` -- coordination manifest
- `wip/design_<topic>_decision_<N>_report.md` -- per-question decision report

Cross-validation reads all decision reports, checks assumptions against peer
choices, restarts conflicting decisions once with constraints, then proceeds.

### Component 5: Explore Skill Changes

Minimal changes:
- When crystallize selects "Decision Record", write a decision brief and hand
  off to `/decision` (same pattern as /design and /prd handoffs)
- Move Decision Record from deferred types to supported types in the crystallize
  framework
- Add `phase-5-produce-decision.md` alongside other produce sub-files

### Component 6: All Skills -- Decision Protocol Integration

Every skill that currently uses AskUserQuestion at decision points switches to
the research-first pattern:

1. Gather evidence from loaded context
2. Form recommendation with rationale
3. In interactive mode: present via AskUserQuestion with evidence
4. In non-interactive mode: follow recommendation, write decision block
5. Record in manifest

The 39 blocking points reduce to ~2 genuine safety gates (CI failure handling
in work-on) that halt in both modes.

## Implementation Approach

### Phase 1: Foundation (lightweight protocol + non-interactive mode)

These affect all skills and can be implemented without the decision skill.
Changes to each skill's phase files to adopt research-first decision pattern
and `--auto` flag support.

Deliverables:
- Decision block format specification (reference file)
- Lightweight decision protocol specification (reference file)
- `--auto` flag handling in each SKILL.md
- Assumption tracking artifact format
- Review surface (terminal summary + PR body section)

### Phase 2: Decision skill

The new `skills/decision/` skill with 7 phases, fast path support, and both
standalone and sub-operation invocation.

Deliverables:
- SKILL.md with input/output contracts
- 7 phase files (each under 150 lines)
- Agent prompt template for compiled prompts
- Decision report format specification

### Phase 3: Design skill restructuring

Rewrite design Phases 1-3 to use decision decomposition, delegation, and
cross-validation. Slim Phase 4 (investigation).

Deliverables:
- Updated SKILL.md with 8-phase workflow
- New phase files: phase-1-decomposition.md, phase-2-execution.md, phase-3-cross-validation.md
- Updated phase-4-investigation.md (slimmed)
- Coordination manifest format

### Phase 4: Explore integration

Add decision skill handoff for Decision Record crystallize type.

Deliverables:
- phase-5-produce-decision.md
- Updated crystallize-framework.md (Decision Record as supported type)
- Decision brief format specification

## Security Considerations

**Decision blocks contain no secrets.** They record architectural choices, not
credentials or sensitive data. The wip/ artifacts follow the same lifecycle as
existing wip/ files -- committed to feature branches, cleaned before merge.

**Non-interactive mode auto-approves artifacts.** In --auto mode, design docs
and PRDs are auto-approved when validation passes. This means a human doesn't
review the artifact before it's committed to the branch. Mitigation: the PR
review process is the human review gate. Auto-approval commits to a feature
branch, not main.

**Agent-spawned decisions run with the same permissions.** Decision skill agents
inherit the parent's tool permissions. No privilege escalation.

**Assumption invalidation doesn't re-execute code.** When a human invalidates
an assumption, the agent re-evaluates decisions but doesn't re-run implementation.
No blast radius beyond the decision artifacts themselves.

## Consequences

### Positive

- Skills can run end-to-end without human input (--auto mode)
- All decisions are structurally recorded with assumptions
- The design skill gains peer revision and cross-examination (from the decision
  skill) that it currently lacks
- Decision quality improves through research-first discipline
- Assumption review surfaces are visible to PR reviewers

### Negative and mitigations

| Negative | Mitigation |
|----------|-----------|
| Context window pressure from decision blocks in wip/ artifacts | Decision blocks are compact (10-20 lines); lightweight protocol keeps most under 5 lines |
| Agent cost for parallel decisions (3-5 agents per design doc) | Fast path skips 3 phases; only critical decisions use full 7-phase |
| Complexity of 8-phase design workflow + nested decision phases | Phase files stay under 150 lines; static dispatch means no runtime branching |
| Non-interactive mode may make poor assumptions | Assumptions surface in 3 places (wip/, terminal, PR body); user reviews before merge |
| Escalation from lightweight to heavyweight breaks static dispatch in explore | Documented exception; escalation is rare in practice |

## Open Items From Self-Validation

This design was produced using the proposed framework itself (non-interactive,
decision decomposition into clusters, parallel agent execution, cross-validation).
Three refinements surfaced during the process:

### Agent prompt compilation needs a concrete template

The design says the parent "pre-compiles the decision skill's phases into a
single prompt" for Task agents. During self-validation, the agent prompts for
Clusters A and B were ad-hoc — each described what to decide and pointed at
research files, but didn't follow a reusable template. Implementation Phase 2
(decision skill) must produce a standard compiled-prompt template that any
parent can fill in. Without it, each parent will invent its own prompt format,
leading to inconsistent decision quality across invocation sites.

### Confirmed vs assumed status boundary is underspecified

The decision block format defines `status="confirmed"` and `status="assumed"`
but doesn't specify the threshold between them. During self-validation, every
decision felt "confirmed" because the research evidence was strong — but an
agent with less context might mark everything as "confirmed" to avoid flagging
assumptions for review, defeating the review surface.

The specification needs a concrete heuristic. Proposed: a decision is "assumed"
when ANY of these hold:
- Evidence was split (e.g., 60/40 between two options)
- The choice depends on a fact the agent couldn't verify (an assumption about
  external systems, stakeholder preferences, or future conditions)
- The agent would have asked the user in interactive mode

Otherwise it's "confirmed." This makes the boundary mechanical rather than
subjective.

### Non-interactive explore needs a round limit

Explore's discover-converge loop runs until the user says "ready to decide."
In --auto mode, the agent evaluates gaps and decides whether to loop. But
with no human to say "that's enough," the agent could loop indefinitely if
it keeps finding minor gaps.

The specification needs a round limit for --auto mode. Proposed: max 3
discover-converge rounds. After round 3, auto-crystallize with whatever
findings exist. The round limit should be configurable via the decision
context (some explorations warrant deeper investigation). Default: 3 rounds.
