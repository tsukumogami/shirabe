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
  share a common decision block format (HTML comment delimiters with markdown content),
  category-based confirmed/assumed status classification, a consolidated decisions
  file (replacing separate manifest and assumptions files), and a layered review
  surface (wip/ file, terminal summary, PR body section). 14 architectural decisions.
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

**Agent prompt**: for the Task agent path, the agent reads the decision skill's
SKILL.md and phase files directly rather than receiving a pre-compiled prompt.
This keeps the phase files as the single source of truth and avoids the
maintenance burden of a compiled template that must stay in sync with 7 phase
files. The parent provides the decision context (question, options, constraints,
background) and the agent navigates the skill autonomously.

#### Alternatives considered

- **Always agent**: simpler contract but adds unnecessary agent spawn overhead
  for explore's single-decision case, and loses explore's loaded context
- **Always inline**: can't parallelize design's 3-5 decisions; serial execution
  adds 3-5x wall-clock time
- **Compiled prompt template**: parent pre-compiles phases into a monolithic
  prompt. Avoids file navigation but creates a second source of truth that
  drifts from the phase files. Maintenance cost outweighs reliability gain.

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

Restarted decisions receive the conflicting decision's output as a constraint,
which steers away from new conflicts in most cases.

**Cleanup timing**: intermediate decision artifacts (research, alternatives,
bakeoff results) persist through cross-validation. Cleanup runs after cross-
validation completes, not after each individual decision. Only the final reports
are needed post-cross-validation.

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
typically obvious choices where the lightweight protocol or auto-selection in
--auto mode is appropriate.

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

### Decision 8: Agent prompt approach

How do decision skill agents receive their instructions when spawned by a parent?

#### Chosen: Agent reads SKILL.md directly with hierarchical agent spawning

The parent spawns one **decider agent** per decision question. The decider reads
the decision skill's SKILL.md and phase files, following progressive disclosure.

The decider itself spawns sub-agents as specified in issue #6:

```
Level 1: Orchestrator (design skill)
  └── Level 2: Decider agent (one per decision question)
        ├── Level 3: Research agent (Phase 1, disposable)
        ├── Level 3: Alternative agents (Phase 2, disposable)
        └── Level 3: Validator agents (Phase 3-5, persistent)
              ├── Phase 3: argue FOR their alternative (bakeoff)
              ├── Phase 4: receive peer findings, revise (SendMessage)
              └── Phase 5: cross-examine peers (SendMessage)
```

**Validator persistence is critical.** Validators are spawned in Phase 3 and
re-messaged via `SendMessage` in Phases 4 and 5. They retain their full
conversation history -- they need to remember their prior arguments to revise
and defend them. This is NOT the disposable single-task pattern from plan Phase 4.
Research and alternative agents are disposable (single task, then done).

**Fast path (Tier 3)** skips Phases 3-5. The decider runs Phases 0, 1, 2, 6
without spawning validators. No persistent agents needed.

Phase files are the single source of truth. Updating a phase file immediately
affects both standalone and agent-spawned invocations. No compiled template.

The parent's agent prompt is lightweight (~500-800 tokens): role statement,
decision context, prefix for wip/ artifacts, and instruction to read the
decision SKILL.md. Context budget for the decider: ~800-1100 lines of
instructions (SKILL.md + phase files loaded on demand via progressive
disclosure).

#### Alternatives considered

- **Monolithic compiled template**: parent pre-compiles all 7 phases into one
  prompt (~3-4K tokens). Avoids file navigation but creates a second source of
  truth. Every phase file change requires updating the template. Fast-path
  stripping (removing phases 3-5) adds fragility since cross-phase references
  break invisibly. Maintenance cost outweighs the reliability gain.
- **Phased template with header**: functionally identical to monolithic -- the
  agent sees the same content regardless of heading structure.

### Decision 9: Confirmed vs assumed status threshold

How should agents determine whether a decision is `confirmed` or `assumed`?

#### Chosen: Category-based with heuristic refinement

Map from the decision point's category:

| Category | Status | Condition |
|----------|--------|-----------|
| Researchable | `confirmed` | Agent found the answer via research |
| Researchable | `assumed` | Agent couldn't find the answer, made best guess |
| Judgment call | `confirmed` | Skill's recommendation heuristic produced a clear winner AND no contradicting evidence found during gather |
| Judgment call | `assumed` | Heuristic was close, or contradicting evidence exists |
| Approval gate | `assumed` | Always -- auto-approval is inherently an assumption that the artifact meets the user's standards |

Expected distribution: ~50/50 between confirmed and assumed.

To prevent review fatigue, assumptions also carry a **review priority** (`high`
or `low`). High-priority assumptions surface in the terminal summary and PR body.
Low-priority ones are in the wip/ artifact only. Approval gates and contested
judgment calls are high. Clear heuristic wins and researchable-and-found are low.
This gives ~20/80 in the visible review surfaces while still recording everything.

#### Alternatives considered

- **Three-condition heuristic**: condition "would have asked the user" applies
  to all 39 points, making everything assumed
- **Confidence score (1-5)**: LLMs are poorly calibrated at self-assessing
  confidence; agents cluster around 3-4
- **Assumptions-exist = assumed**: creates incentive to omit assumptions to
  achieve confirmed status, directly undermining the framework's core value

### Decision 10: Auto-mode loop termination

How should `--auto` mode handle discover-converge loops across all skills?

#### Chosen: Per-skill round limits with --max-rounds override

Each skill gets a default ceiling tuned to its loop type:

| Skill | Loop type | Default max | Rationale |
|-------|-----------|-------------|-----------|
| explore | Discover-converge | 3 | Iterative broadening; first round is broad |
| prd | Discover loop-back | 2 | Gap-filling is targeted; 2 rounds failing suggests bad scoping |
| design | "None of these" | 1 | Corrective; repeated corrections mean re-scoping needed |

The cap is a ceiling, not a target. The recommendation heuristic still drives
early termination -- most runs finish in fewer rounds than the max.

When the cap forces termination, the agent records an Approach-level assumption
listing remaining gaps and suggesting re-run options.

`--max-rounds=N` overrides all skill defaults uniformly.

#### Alternatives considered

- **Universal limit**: conflates structurally different loops (broadening vs corrective)
- **Adaptive termination** (% new findings): too hard to measure reliably;
  still needs a hard cap as safety net
- **First-round-only in --auto**: sacrifices too much quality; the skills are
  designed for iterative deepening

### Decision 11: Format mapping ownership

How should the mapping between decision reports and consuming formats (Considered
Options, ADR) be specified and maintained?

#### Chosen: Single canonical format with consumer rendering sections

The decision report format spec includes "How to render as Considered Options"
and "How to render as ADR" sections, co-locating the format definition with all
consumer rendering rules in one file. When a field is added, one file changes.

Consumers (design skill's cross-validation phase, explore's produce-decision
phase) reference the rendering rules from the canonical spec rather than
maintaining their own adapters.

#### Alternatives considered

- **Dedicated format-mapping reference file**: achieves the same goal but adds
  indirection -- two files to update instead of one. Can migrate to this if
  rendering rules grow complex enough to warrant separation.
- **Inline in each consumer's phase file**: the current implicit approach and
  the direct cause of the 7-8 file change problem the maintainability review flagged.

### Decision 12: Tier classification signals

What concrete signals should an agent use to classify a decision into the
correct tier?

#### Chosen: Manifest-based pre-classification with checklist fallback

A **decision point manifest** (`references/decision-points.md`) catalogues all
39 known decision points with their location, category, and pre-assigned tier.
The agent reads this manifest at the start of execution. No per-file annotations
-- the manifest is the single source of truth.

**Emergent decisions** (discovered mid-execution, especially in design Phases
4-5) use a three-signal checklist in override order:

1. **Reversibility**: irreversible forces Tier 4
2. **Heuristic confidence**: decisive result = Tier 2, close result = Tier 3
3. **Phase primacy**: if this is the primary question the phase exists to
   answer, minimum Tier 3

Default stays Tier 2 when signals are ambiguous. Over-documenting with the
lightweight protocol is better than under-escalating.

#### Alternatives considered

- **Phase-file annotations** (`<!-- decision-tier: N -->`): creates 39+1
  representations of the same data (annotations + manifest) with no sync
  mechanism. Mirrors the compiled-prompt-drift problem D8 solved.
- **Checklist alone**: adds classification overhead to every decision including
  the predictable majority
- **Pre-classification alone**: can't handle emergent decisions during
  architecture and investigation phases

### Decision 13: Decision count scaling

What upper bound should be set on decisions per design doc?

#### Chosen: Tiered guidance with hard ceiling at 10

Phase 1 (Decision Decomposition) applies escalating friction based on the count
of **independent decision questions after merging coupled decisions**. The
independence criterion ("options for one don't affect options for another") is
applied first; coupled questions are merged before counting.

| Count | Interactive | --auto |
|-------|------------|--------|
| 1-5 | Proceed normally | Proceed normally |
| 6-7 | Warn, proceed with confirmation | Proceed, record high-priority assumption |
| 8-9 | Present split proposal, require confirmation | Proceed as one doc, record high-priority assumption suggesting split |
| 10+ | Refuse, require splitting | Refuse, halt with error |

In --auto mode, the 8-9 band does NOT auto-execute the split. Auto-splitting
violates user expectations (they asked for one doc) and the split mechanics
(branch strategy, resume, sibling doc naming) are undefined. Instead, the agent
proceeds and flags the count as a high-priority assumption for review.

The binding constraint is document readability, not cross-validation cost.

**Scope note:** this ceiling applies to the design skill's runtime Considered
Options output, not to architectural design records or specification documents
generally.

#### Alternatives considered

- **Hard cap at 8**: too rigid for 8-9 orthogonal decisions that legitimately
  occur together
- **Soft guidance only**: users always override suggestions; no protection
  against the degenerate case
- **Hierarchical decomposition**: introduces a new document type and two-level
  cross-validation for a problem that rarely arises
- **No limit, optimize cross-validation**: misses the readability constraint

### Decision 14: Decision and assumption artifact consolidation

Should assumptions and decision manifests be separate files or consolidated?

#### Chosen: Single consolidated file per workflow invocation

`wip/<workflow>_<topic>_decisions.md` contains both the decision index (table
at top) and detailed assumption entries (below). One extra file per invocation
instead of two.

Structure:
- **Index table**: all decisions with ID, tier, status, location
- **Assumption details**: entries for `status="assumed"` decisions with
  confidence, evidence summary, and "if wrong" restart path

Confirmed decisions appear only in the index. Assumed decisions get both an
index row and a detailed entry. The file is append-only during execution and
serves as the source of truth for the terminal summary and PR body section.

#### Alternatives considered

- **Two separate files** (original design): clear separation but doubles the
  per-invocation file overhead; heavy overlap since every assumed decision
  appears in both
- **No new files (derive at review time)**: destroys the persistent review
  surface and breaks assumption invalidation via stable IDs
- **Split by decision weight**: functionally identical to consolidated for
  review purposes but adds branching logic

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
High-priority assumptions surface in the terminal summary and PR body.
Low-priority ones are recorded in the wip/ artifact for detailed review.

**For multi-decision contexts** (design docs), the design skill decomposes the
problem into decision questions, runs the decision skill per question in parallel
via agents, then cross-validates assumptions in a single pass.

**Progress feedback** in --auto mode: the orchestrator emits a one-line status
after each phase transition (e.g., "Phase 2: executing decision 3/5...") so
the user can monitor progress during long autonomous runs.

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
cross-examination). No persistent sub-agents -- the decider handles all phases.

Full path (Tier 4): all 7 phases. The decider spawns validator agents in Phase 3
(one per alternative) and re-messages them via `SendMessage` in Phases 4-5.
Validators retain context across phases to revise and defend their positions.

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

**Output format:** The canonical decision report includes consumer rendering
rules (Decision 11): "How to render as Considered Options" and "How to render
as ADR" are co-located in the format spec. One file to update for format changes.
When consumed by a design doc, the report maps to Considered Options sections.
When standalone, it serializes to `docs/decisions/ADR-<topic>.md`.

### Component 2: Lightweight Decision Protocol

A 3-step micro-workflow invoked inline at any decision point. Defined in a
shared reference file (`references/decision-protocol.md`) that all skills
point to -- not duplicated across 39 phase files.

1. **Frame**: state the question in one sentence
2. **Gather**: check available evidence from loaded context (codebase, prior
   decisions, constraints). Don't ask when you can look up.
3. **Decide and record**: write a decision block in the current artifact

Triggers when any of these hold:
- The decision affects downstream artifacts
- A reasonable person could have chosen differently
- The choice rests on a falsifiable assumption
- Reversing would require rework

Decision blocks are inline in their source artifacts. A consolidated decisions
file (`wip/<workflow>_<topic>_decisions.md`) indexes all blocks and tracks
assumptions in one place (Decision 14).

Known decision points are pre-classified in the decision point manifest
(`references/decision-points.md`) so the agent doesn't classify at runtime
(Decision 12). Emergent decisions use a three-signal checklist: reversibility,
heuristic confidence, phase primacy.

The consolidated decisions file (`wip/<workflow>_<topic>_decisions.md`) is the
source of truth for review. Inline decision blocks in wip/ artifacts are
write-time snapshots -- if an assumption is invalidated, the consolidated file
is updated; inline blocks are not retroactively modified.

### Component 3: Non-Interactive Execution Mode

Signaled by `--auto` flag or CLAUDE.md `## Execution Mode: auto`.

Behavioral changes at decision points:

| Category | Interactive | Non-Interactive |
|----------|------------|-----------------|
| Researchable (28%) | Research first, then confirm | Research and proceed |
| Judgment calls (49%) | Present recommendation, user confirms | Follow recommendation, document assumption |
| Approval gates (26%) | Present artifact, user approves | Auto-approve if validation passes, document |
| Safety gates (CI failures) | Ask user | Halt execution (never auto-accept failures) |

Loop termination in --auto: per-skill round limits (explore: 3, prd: 2,
design: 1) with `--max-rounds=N` override.

Assumptions accumulate in the consolidated `wip/<workflow>_<topic>_decisions.md`
file during execution. High-priority assumptions surface at the terminal and
in the PR body.

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

Decision Decomposition (Phase 1) applies the scaling heuristic (Decision 13):
1-5 decisions proceed normally, 6-7 warn, 8-9 require split confirmation,
10+ refuse and require splitting.

New artifacts:
- `wip/design_<topic>_coordination.json` -- coordination manifest
- `wip/design_<topic>_decision_<N>_report.md` -- per-question decision report
- `wip/design_<topic>_decisions.md` -- consolidated decision index + assumptions

Cross-validation reads all decision reports, checks assumptions against peer
choices, restarts conflicting decisions once with constraints, then cleans up
intermediate artifacts. Only final reports persist post-cross-validation.

### Component 5: Explore Skill Changes

- When crystallize selects "Decision Record", write a decision brief and hand
  off to `/decision` (same pattern as /design and /prd handoffs)
- Move Decision Record from deferred types to supported types in the crystallize
  framework
- Add `phase-5-produce-decision.md` alongside other produce sub-files

### Component 6: PRD Skill Integration

PRD uses the lightweight decision protocol for all decision points. No
heavyweight decisions -- prd's choices (scope boundaries, requirement
prioritization) are Tier 2 at most. The jury review (Phase 4) stays as-is:
it's quality assurance on the document, not a decision between alternatives.

If a PRD has genuinely contested requirements where stakeholders disagree on
what to build, the user should run /explore first to resolve the contention
before starting /prd.

### Component 7: All Skills -- Protocol Integration

Every skill adopts the research-first pattern at decision points by referencing
the shared `references/decision-protocol.md`:

1. Gather evidence from loaded context
2. Form recommendation with rationale
3. In interactive mode: present via AskUserQuestion with evidence
4. In non-interactive mode: follow recommendation, write decision block
5. Record in manifest

The 39 blocking points reduce to ~2 genuine safety gates (CI failure handling
in work-on) that halt in both modes.

## Implementation Approach

### Phase 1a: Protocol and Format Specifications

Define the framework's shared artifacts before touching existing skill files.

Deliverables:
- `references/decision-protocol.md` -- shared lightweight protocol specification
  with decision block format (HTML comment delimiters), status threshold rules
  (Decision 9), and tier classification signals (Decision 12)
- `references/decision-points.md` -- manifest cataloguing all 39 known decision
  points with location, category, pre-classified tier, and expected behavior
  in interactive and --auto modes
- Decision report format specification with consumer rendering sections for
  Considered Options and ADR (Decision 11)
- Consolidated decisions file format (`wip/<workflow>_<topic>_decisions.md`)
  with index table + assumption details and review priority (Decision 14)
- Review surface templates: terminal summary printer + PR body section (Decision 2)
- Progress feedback protocol for --auto mode (one-line status per phase transition)

### Phase 1b: Integration into Existing Skills

Apply the protocol to all 5 workflow skills. Depends on Phase 1a specs being stable.

Deliverables:
- `--auto` flag handling in each SKILL.md (Decision 7)
- `--max-rounds=N` flag handling with per-skill defaults (Decision 10)
- Research-first pattern applied at all 39 decision points (referencing the
  shared protocol, not duplicating it)
- Consolidated decisions file creation in each skill's workflow

### Phase 2: Decision skill

The new `skills/decision/` skill with 7 phases, fast path support, and both
standalone and sub-operation invocation.

Deliverables:
- SKILL.md with input/output contracts and sub-operation interface section
- 7 phase files (each under 150 lines)
- Decision report format specification with consumer rendering sections for
  Considered Options and ADR formats (Decision 11)
- Cleanup policy: intermediate artifacts deleted after report is written;
  only the final report persists

### Phase 3: Design skill restructuring

Rewrite design Phases 1-3 to use decision decomposition, delegation, and
cross-validation. Slim Phase 4 (investigation).

Deliverables:
- Updated SKILL.md with 8-phase workflow
- New phase files: phase-1-decomposition.md, phase-2-execution.md,
  phase-3-cross-validation.md
- Updated phase-4-investigation.md (slimmed, implementation-focused only)
- Coordination manifest format (`wip/design_<topic>_coordination.json`)
- Decision count scaling heuristic in phase-1-decomposition.md (Decision 13)
- Cross-validation cleanup: intermediate artifacts persist through cross-
  validation, cleaned after it completes

### Phase 4: Explore integration

Add decision skill handoff for Decision Record crystallize type.

Deliverables:
- phase-5-produce-decision.md (handoff to decision skill)
- Updated crystallize-framework.md (Decision Record as supported type)
- Decision brief format specification
- Escalation path: lightweight to heavyweight via `status="escalated"` block

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
- Shared decision protocol reference avoids 39-file duplication

### Negative and mitigations

| Negative | Mitigation |
|----------|-----------|
| Context window pressure from decision blocks in wip/ artifacts | Decision blocks are compact (10-20 lines); lightweight protocol keeps most under 5 lines |
| Agent cost for parallel decisions (3-5 agents per design doc) | Fast path skips 3 phases; only critical decisions use full 7-phase |
| Complexity of 8-phase design workflow + nested decision phases | Phase files stay under 150 lines; static dispatch means no runtime branching |
| Non-interactive mode may make poor assumptions | High-priority assumptions surface in terminal + PR body; low-priority in wip/ only; ~20/80 visible split prevents review fatigue |
| Escalation from lightweight to heavyweight breaks static dispatch in explore | Documented exception; escalation is rare in practice |
| Decision skill agents navigate files rather than receiving compiled prompts | Phase files are the single source of truth; no compiled template to drift. If agent file navigation proves unreliable, a compiled template can be added later as an optimization |
| Three-level agent hierarchy (orchestrator > decider > validators) increases spawn complexity | Fast path avoids sub-agents entirely; full path only spawns validators for Tier 4 decisions; validators use SendMessage (continuation) not fresh spawns for Phases 4-5 |
