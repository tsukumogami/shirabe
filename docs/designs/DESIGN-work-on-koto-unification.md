---
status: Proposed
problem: |
  The work-on skill and the private /implement workflow serve overlapping
  purposes with different orchestration backends. work-on uses koto for
  single-issue execution; /implement uses a custom Go workflow-tool for
  multi-issue plan execution. Koto v0.6.0 introduced structured gate output
  and first-class overrides, requiring template migration. This design
  specifies how to unify both workflows into a single work-on entry point
  backed entirely by koto, handling free-form tasks, single issues, and
  full plan execution through shared components.
decision: |
  A single monolithic koto template with 3-way entry routing handles all
  modes. Per-issue koto workflows provide state machine enforcement. A
  hybrid orchestrator splits multi-issue queue management between a
  deterministic helper script (dependency graph, issue selection) and
  SKILL.md (context assembly, koto workflow management). All gates migrate
  to v0.6.0 strict mode with selective decomposition. Review panels use
  context-exists gates for persistence and evidence enums for routing.
rationale: |
  Each component operates at the abstraction level where it's most reliable:
  koto handles per-issue state enforcement, the skill layer handles
  judgment-intensive orchestration, and the helper script handles deterministic
  graph operations. The monolithic template works because per-issue workflows
  eliminate multi-issue complexity. Strict gate mode and the hybrid review
  panel approach both follow the same gate-plus-evidence pattern already
  established in the template.
---

# DESIGN: work-on-koto-unification

## Status

Proposed

## Context and Problem Statement

The shirabe plugin provides two implementation workflows that overlap in purpose
but diverge in architecture. The work-on skill handles single GitHub issues and
free-form tasks using koto for state management. The private /implement workflow
handles multi-issue plan execution using a custom Go-based workflow-tool that
provides dependency graph resolution, template-based directive generation,
per-issue state machines, and review/QA panels.

Koto v0.6.0 shipped breaking changes to gate declarations: gates now produce
structured JSON output injected into evidence maps, transitions route on
dot-path references (`gates.ci_check.exit_code`), overrides require mandatory
rationale, and compiler validation enforces the gate/transition/override
contract. The legacy gate format is supported via a transitory
`--allow-legacy-gates` flag.

The goal is a single `/work-on` entry point that:
- Handles free-form tasks, single issues, and plan document paths
- Uses koto for all orchestration (replacing workflow-tool)
- Migrates to v0.6.0 structured gate output
- Shares components (review panels, context management, PR creation) across
  all execution modes

Exploration identified a three-layer architecture:
1. **Koto per-issue state machine**: each issue gets its own koto workflow
2. **Skill-layer orchestrator**: manages the issue queue for multi-issue plans
3. **Shared components**: review panels, context assembly, entry routing

## Decision Drivers

- Koto's state machine is per-workflow by design; hierarchical states were
  explicitly deferred to "a later phase"
- The existing work-on template has 17 states and 8 gates that need v0.6.0
  migration
- workflow-tool's controller loop (dependency resolution, queue management,
  variable interpolation) has no koto equivalent today
- Review panels (3-agent scrutiny, 3-agent code review, QA) require multi-agent
  orchestration that koto gates can't express
- Cross-issue context must be bounded to prevent context window exhaustion on
  large plans (50+ issues)
- The v0.6.0 `--allow-legacy-gates` flag is transitory and will be removed

## Decisions Already Made

These choices were settled during exploration and should be treated as constraints:

- **Orchestrator lives in skill layer, not koto**: koto is per-workflow; multi-issue
  queue management is above its abstraction level
- **Per-issue koto workflows, not monolithic**: each issue gets its own state file;
  avoids koto's lack of sub-workflows/iteration
- **Review panels stay in skill markdown**: koto gates handle binary checks;
  multi-agent orchestration with feedback loops isn't expressible as gates
- **Gate migration proceeds independently**: mechanical refactoring not blocked by
  orchestrator design
- **External state tracking for orchestrator**: hybrid approach with koto context
  for content and a structured manifest for issue tracking

## Considered Options

### Decision 1: Unified koto template structure

The work-on template currently has a dual-path topology: issue-backed and free-form
modes branch at the entry state, follow mode-specific pre-analysis chains, then
converge at an analysis state and share all subsequent phases. Adding plan-backed
execution requires a third entry path. The question is whether to keep a single
monolithic template, split into multiple templates, or delegate mode-specific logic
to the skill layer.

The per-issue koto workflow architecture (one state file per issue) is a key
constraint. Since each plan issue gets its own koto workflow, the template doesn't
need to represent multi-issue iteration -- it only needs to route a third mode
through pre-analysis to the shared backbone.

#### Chosen: Single monolithic template with 3 entry branches

Add `plan_backed` to the entry state's mode enum alongside `issue_backed` and
`free_form`. Create a short pre-analysis chain for plan-backed mode (plan context
injection, plan validation, setup) that converges at the existing analysis state.
The template grows from 17 to approximately 23 states (including review panel states
from Decision 4).

The entry state becomes:
```yaml
entry:
  accepts:
    mode:
      type: enum
      values: [issue_backed, free_form, plan_backed]
  transitions:
    - target: context_injection
      when: { mode: issue_backed }
    - target: task_validation
      when: { mode: free_form }
    - target: plan_context_injection
      when: { mode: plan_backed }
```

All post-analysis states remain shared. The skill-layer orchestrator handles
sequencing across issues by initializing separate koto workflows, not by adding
states to the template.

This preserves compile-time path validation (koto checks mutual exclusivity and
reachability across all three branches), full resume reliability (koto state files
capture exact position), and single-file maintainability.

#### Alternatives Considered

**Template composition with base + overlays**: Reusable shared states with
per-mode overlay files. Rejected because koto has no include or composition
mechanism -- templates are monolithic YAML. Would require a custom pre-processor
for no structural benefit.

**Three separate templates**: One per mode, selected at init time. Rejected
because it duplicates the shared backbone (7+ states) across three files. Changes
to shared states must be applied three times, and decision logs split across
templates.

**Single template + skill-layer delegation**: Moves pre-analysis to the skill
layer, reducing koto's visibility. Originally recommended during exploration
because it avoided multi-issue orchestration in the state machine. With per-issue
workflows decided, the multi-issue concern is resolved, and the trade-off (less
visibility, partial resume) is no longer worth making.

### Decision 2: Multi-issue orchestrator architecture

The /implement workflow's controller.go provides ~240 lines of orchestration:
dependency graph resolution, next-issue selection, auto-skip, variable
interpolation, directive generation. Koto replaces per-issue state advancement
but has no dependency graph, queue management, or multi-workflow coordination.
The orchestrator must live in the skill layer. The question is what form it takes.

The core tension: dependency graph operations are deterministic and must be
reliable at scale (10+ issues with complex dependency chains). Context assembly
(deciding what prior summaries to include, what decisions to carry forward) is
flexible and benefits from agent judgment. These have different reliability
requirements.

#### Chosen: Hybrid orchestrator (script for graph, SKILL.md for context)

Split responsibilities along the deterministic/flexible boundary. A queue
management script handles dependency graph computation, issue selection, auto-skip,
and status tracking. The SKILL.md handles PLAN doc parsing, cross-issue context
assembly, koto workflow management, and PR-level coordination.

The script (`scripts/plan-queue.sh`) reuses the existing dependency graph logic
from `skills/plan/scripts/build-dependency-graph.sh` and exposes four subcommands:
- `next-issue <manifest>`: computes dependency graph, returns next ready issue as JSON
- `mark-complete <manifest> <N>`: marks issue completed, checks for newly unblocked issues
- `mark-skipped <manifest> <N> <reason>`: marks issue skipped, auto-skips transitive dependents
- `status <manifest>`: returns aggregate state (counts by status, blocked issues, progress)

The SKILL.md orchestration handles PLAN doc parsing into the manifest, per-issue
koto init with issue-specific variables, cross-issue context assembly from koto
context keys, the koto execution loop per issue, and resume via manifest + koto
workflow state reconciliation.

Single-issue mode bypasses the script entirely -- the SKILL.md detects single-issue
vs plan mode and uses the existing koto-only loop for single issues.

#### Alternatives Considered

**SKILL.md-embedded orchestrator**: All logic in prose instructions. Rejected
because dependency graph operations in natural language are unreliable for >5
issues. The agent may miss transitive blocks, fail to auto-skip, or select blocked
issues. Not testable in CI.

**Full script orchestrator**: Script handles everything including context assembly.
Rejected because context assembly requires reading koto state, assembling summaries,
and making judgment calls about what context matters -- capabilities a script handles
poorly without significant complexity.

**Koto meta-workflow**: A second koto template manages the queue. Rejected because
koto provides no dependency graph support, nested workflows are untested, and the
implementation cost is too high. Koto's roadmap includes "hierarchical states in a
later phase" -- revisit when that ships.

### Decision 3: Gate migration patterns for v0.6.0

The 8 gates need migration from legacy boolean blocking to v0.6.0 structured output.
Context-exists gates have straightforward schemas (`{exists, error}`). Command gates
range from simple branch checks to complex multi-clause shells. The most complex is
`code_committed`, which chains branch check, commit count, and test suite into one
command -- making failures opaque.

The key sub-decisions: validation mode (strict vs permissive), whether to decompose
compound command gates, and how to handle mixed routing (gates + agent evidence in
the same when clause).

#### Chosen: Strict mode with selective decomposition

Compile in strict mode (no `--allow-legacy-gates`). Add `gates.*` when clauses to
every gated state using mixed routing. Decompose `code_committed` into three atomic
gates; keep all other gates intact.

Context-exists gates (4): direct migration with `gates.NAME.exists: true` in when
clauses. Built-in override defaults suffice.

Simple command gates (2: `on_feature_branch`, `staleness_fresh`): direct migration
with `gates.NAME.exit_code: 0`. Built-in defaults suffice.

Decomposed `code_committed` becomes 3 gates on the implementation state:
- `on_feature_branch_impl`: branch check
- `has_commits`: commit count check
- `tests_passing`: test suite

Preserved compound `ci_passing`: stays as-is. CI failure remediation is uniform
regardless of which check failed -- the agent reads CI output regardless.
Decomposition would add complexity without changing agent behavior.

Mixed routing combines gate conditions with agent evidence:
```yaml
transitions:
  - target: scrutiny
    when:
      gates.on_feature_branch_impl.exit_code: 0
      gates.has_commits.exit_code: 0
      gates.tests_passing.exit_code: 0
      implementation_status: complete
  - target: implementation
    when:
      implementation_status: partial_tests_failing_retry
```

#### Alternatives Considered

**Full decomposition**: Decompose both `code_committed` and `ci_passing`. Rejected
because `ci_passing` decomposition adds complexity without changing agent behavior --
the response to any CI failure is the same: investigate and fix or escalate.

**Preserve all compound gates**: Keep all 8 gates as-is. Rejected because
`code_committed` failures are the most common pain point, and agents waste cycles
investigating which clause failed when the exit code is opaque.

**Permissive incremental migration**: Use `--allow-legacy-gates` for phased
migration. Rejected because it creates dependency on a deprecated flag and means
two rounds of template changes instead of one.

### Decision 4: Review panel integration with koto state

Review panels (3-agent scrutiny, 3-agent code review, QA) run between
implementation and PR creation. They're orchestrated in skill markdown since koto
gates can't express multi-agent coordination with feedback loops. The question is
how panel results connect to koto state transitions.

The existing template combines gates with evidence in every substantive state: a
context-exists gate confirms an artifact was produced, plus an evidence enum for
transition routing. This two-layer pattern separates structural guarantees from
control flow.

#### Chosen: Hybrid -- context for persistence, evidence for transitions

New template states (`scrutiny`, `review`, `qa_validation`) sit between
`implementation` and `finalization`. Each has a context-exists gate checking for
panel results plus an evidence enum for routing.

Panels write aggregated results to koto context (`scrutiny_results.json`,
`review_results.json`, `qa_results.json`). The skill layer runs panels within the
state directive, writes results to context, then submits evidence
(`passed | blocking_retry | blocking_escalate`).

```yaml
scrutiny:
  gates:
    scrutiny_results:
      type: context-exists
      key: scrutiny_results.json
  accepts:
    scrutiny_outcome:
      type: enum
      values: [passed, blocking_retry, blocking_escalate]
  transitions:
    - target: review
      when: { scrutiny_outcome: passed }
    - target: implementation
      when: { scrutiny_outcome: blocking_retry }
    - target: done_blocked
      when: { scrutiny_outcome: blocking_escalate }
```

Feedback loops transition back to `implementation`. On re-entry to `scrutiny`,
the gate fails (stale results), the skill layer re-runs the panel, overwrites
the context key, and submits fresh evidence. Each review round produces a clean
result set.

Koto's override system enables formal review skipping with rationale (e.g.,
trivial docs fix), replacing ad-hoc skip logic.

#### Alternatives Considered

**Context-exists gates as sole checkpoints**: Gates check existence but can't
route on blocking_count. The skill layer would still need evidence for routing,
making the gate redundant ceremony. Rejected.

**Direct evidence submission only**: No gates, no context writes. Panel results
live only in wip/ (cleaned pre-merge). Resume requires fragile skill-layer
detection of prior completion. Rejected because it loses the audit trail and
clean resume semantics.

## Decision Outcome

**Chosen: Monolithic template + Hybrid orchestrator + Strict gates + Context/evidence review panels**

### Summary

The unified work-on workflow uses a single koto template with a 3-way entry branch
that routes issue-backed, free-form, and plan-backed modes through mode-specific
pre-analysis chains before converging at a shared analysis state. Post-analysis,
the template flows through implementation, three new review states (scrutiny, review,
qa_validation), finalization, PR creation, and CI monitoring. The template grows from
17 to approximately 23 states.

For single issues and free-form tasks, the workflow runs exactly as today -- one koto
workflow, linear state progression, no orchestrator overhead. For plan-backed
execution, a skill-layer orchestrator manages the issue queue: a helper script
(`scripts/plan-queue.sh`) handles dependency graph computation and issue selection
deterministically, while the SKILL.md handles PLAN doc parsing, per-issue koto
workflow initialization (`koto init` with issue-specific variables), cross-issue
context assembly from koto context keys, and PR-level coordination. Each plan issue
gets its own koto workflow with its own state file.

All gates migrate to v0.6.0 strict mode with structured output routing. The
`code_committed` gate decomposes into three atomic gates (`on_feature_branch_impl`,
`has_commits`, `tests_passing`) so agents can distinguish failure types. Every
gated state uses mixed routing -- `gates.*` conditions combined with agent evidence
enums in when clauses.

Review panels write results to koto context for persistence and audit trail, then
the skill layer submits evidence enums for transition routing. Feedback loops
transition back to implementation; on re-entry to a review state, the gate fails
(stale results), triggering a fresh panel run. Koto's override mechanism provides
formal review skipping with mandatory rationale.

### Rationale

The decisions reinforce each other through a consistent layering principle: koto
handles per-issue state machine enforcement (gates, transitions, resume), the skill
layer handles judgment-intensive orchestration (context assembly, panel evaluation,
mode detection), and a helper script handles deterministic graph operations
(dependency resolution, auto-skip). Each component operates at the abstraction level
where it's most reliable.

The monolithic template works because per-issue workflows eliminate the complexity
that originally motivated template splitting. Strict gate mode works because mixed
routing preserves the existing agent evidence flow while adding structured gate
conditions. The hybrid review panel approach works because it follows the same
gate-plus-evidence pattern already used throughout the template. The hybrid
orchestrator works because it decomposes controller.go along a natural boundary:
~100 lines of graph logic to a testable script, ~60 lines of context logic to
flexible SKILL.md, and template extraction to koto itself.

## Solution Architecture

### Overview

The unified work-on system has three layers: a koto template (per-issue state
machine), a skill layer (SKILL.md + helper script for orchestration), and shared
components (review panels, context assembly, entry routing). For single-issue and
free-form tasks, only the koto template and SKILL.md are active. For plan-backed
execution, the helper script manages the issue queue while the SKILL.md coordinates
per-issue koto workflows.

### Components

```
/work-on (user entry point)
    |
    v
SKILL.md (orchestrator)
    |
    +-- Mode detection (issue / free-form / plan)
    |
    +-- [plan mode only] scripts/plan-queue.sh
    |       |
    |       +-- next-issue: dependency graph -> next ready issue
    |       +-- mark-complete: update manifest, check unblocked
    |       +-- mark-skipped: skip + transitive dependents
    |       +-- status: aggregate progress report
    |
    +-- Per-issue koto workflow
    |       |
    |       +-- koto init <WF> --template work-on.md --var ISSUE_NUMBER=N
    |       +-- koto next <WF> (loop until terminal)
    |       +-- koto context set/get (cross-issue context)
    |       +-- koto overrides record (gate bypasses with rationale)
    |
    +-- Review panel orchestration
            |
            +-- Scrutiny (3 agents parallel)
            +-- Code review (3 agents parallel)
            +-- QA validation (tester agent)
```

### Key Interfaces

**Koto template** (`koto-templates/work-on.md`):
- Entry state: `mode` enum `[issue_backed, free_form, plan_backed]`
- Per-issue variables: `ISSUE_NUMBER`, `ARTIFACT_PREFIX`, `PLAN_DOC` (plan mode)
- Terminal states: `done`, `done_blocked`, `validation_exit`
- ~23 states, ~10 gates (after decomposition)

**Queue script** (`scripts/plan-queue.sh`):
- Input: manifest JSON file path
- `next-issue` output: `{"issue_number": N, "title": "...", "agent_type": "coder", "dependencies_met": true}`
- `mark-complete` output: `{"newly_unblocked": [N, ...], "remaining": M}`
- `mark-skipped` output: `{"transitively_skipped": [N, ...], "reason": "..."}`
- `status` output: `{"pending": N, "completed": N, "skipped": N, "blocked": N, "in_progress": N}`

**Manifest schema** (`wip/work-on-plan_<topic>_manifest.json`):
```json
{
  "plan_doc": "path/to/PLAN.md",
  "branch": "impl/<topic>",
  "pr_number": null,
  "issues": [
    {
      "number": 1,
      "title": "...",
      "status": "pending|in_progress|completed|skipped",
      "dependencies": [2, 3],
      "agent_type": "coder|webdev|techwriter",
      "koto_workflow": "work-on-issue-1"
    }
  ]
}
```

**Review panel interface**:
- Input: koto directive at scrutiny/review/qa_validation state
- Output: aggregated JSON to koto context (`scrutiny_results.json`, etc.)
- Evidence: `passed | blocking_retry | blocking_escalate`

**Cross-issue context protocol**:
- Per-issue context keys: `issue-<N>/summary.md`, `issue-<N>/plan.md`
- Script-generated snapshot: `current-context.md` assembled before each issue
- Contents: current issue info, previous 2 issue summaries, cumulative files
  changed, key decisions
- Assembly rules: SKILL.md reads the 2 most recent completed issues' summaries
  via `koto context get <session> issue-<N>/summary.md`, computes cumulative
  files changed from all completed summaries, and writes the snapshot to context
  as `current-context.md` before calling `koto next` for the new issue
- Sliding window: issues older than the 2 most recent are represented as a
  one-line entry (number, title, status) rather than full summaries

**Manifest-koto reconciliation protocol**:
- On each orchestrator loop iteration: verify the manifest's status for the
  active issue matches koto's current state (`koto query <WF> --field state`)
- On resume: call `plan-queue.sh status` to find any `in_progress` issue, then
  verify the corresponding koto workflow exists and is not in a terminal state
- On mismatch: log the divergence, trust koto's state (source of truth for
  per-issue progress), and update the manifest to match

### Data Flow

**Single-issue mode:**
```
SKILL.md detects mode -> koto init (one workflow) -> koto next loop ->
review panels at scrutiny/review/qa states -> done
```

**Plan mode:**
```
SKILL.md parses PLAN -> creates manifest -> plan-queue.sh next-issue ->
koto init (per-issue) -> koto next loop -> review panels ->
koto context set (issue summary) -> plan-queue.sh mark-complete ->
plan-queue.sh next-issue -> [repeat] -> all issues done ->
PR-level QA -> done
```

**Resume:**
```
SKILL.md reads manifest via plan-queue.sh status ->
finds in_progress issue -> koto next --state <existing> ->
continues from koto's persisted state
```

## Implementation Approach

### Phase 1: Gate migration

Migrate the existing work-on koto template to v0.6.0 structured output. This is
independent of all other phases and unblocks strict-mode compilation.

Deliverables:
- Updated `koto-templates/work-on.md` with `gates.*` when clauses on all states
- Decomposed `code_committed` into 3 atomic gates
- Mixed routing on all gated states
- Strict-mode compilation passing (`koto template compile`)

### Phase 2: Review panel states and orchestration

Add scrutiny, review, and qa_validation states to the template between
implementation and finalization. Wire up the gate-plus-evidence pattern. Write
the panel orchestration instructions in SKILL.md phase references at the same
time -- the template states and orchestration instructions are co-dependent and
must be authored together.

Deliverables:
- Three new states in `koto-templates/work-on.md`
- Panel orchestration instructions in SKILL.md phase references (agent prompts,
  result aggregation, feedback loop logic)
- Panel result context key conventions documented
- Override defaults for review gates (enabling formal skip with rationale)

### Phase 3: Plan-backed entry path

Add the plan_backed mode to the entry state and create the pre-analysis chain
(plan_context_injection, plan_validation, setup_plan_backed).

Deliverables:
- Updated entry state with 3-way mode enum
- Plan-backed pre-analysis states in template
- SKILL.md mode detection logic for plan document paths

### Phase 4: Queue management script

Build the helper script for multi-issue orchestration.

Deliverables:
- `scripts/plan-queue.sh` with next-issue, mark-complete, mark-skipped, status
- Manifest schema and initialization from PLAN doc
- Unit tests for dependency resolution and auto-skip logic

### Phase 5: SKILL.md orchestrator

Wire the orchestrator loop into the SKILL.md for plan-backed execution.

Deliverables:
- SKILL.md orchestration section for plan mode
- Per-issue koto workflow init with variables
- Cross-issue context assembly logic
- Resume reconciliation (manifest + koto state)
- PR-level coordination (single branch, single PR)

### Phase 6: Shared component extraction

Extract review panel instructions, context assembly, and common phase references
into shared files that all three modes reference.

Deliverables:
- Shared review panel orchestration instructions
- Shared context assembly helpers
- Updated SKILL.md referencing shared components

## Security Considerations

This design changes workflow orchestration, not application code. No new attack
surfaces are introduced. The primary security-relevant aspects:

- **Gate overrides**: koto's override mechanism requires rationale. This design
  doesn't weaken that -- all overrides remain auditable via `koto overrides list`.
- **Script execution**: `plan-queue.sh` reads and writes a manifest JSON file.
  It doesn't execute arbitrary commands or process untrusted input beyond PLAN
  doc content authored by the same user.
- **Template variable interpolation**: koto substitutes `--var` values into gate
  command strings before shell execution. `ISSUE_NUMBER` must be validated as
  numeric and `PLAN_DOC` as a valid file path at `koto init` time to prevent
  shell injection via crafted variable values.
- **Context store**: koto context keys store workflow artifacts (summaries, review
  results). No credentials or secrets are stored in context.

## Consequences

### Positive

- Single `/work-on` entry point replaces three workflows (work-on, /implement,
  /implement-doc) with a unified skill
- Gate migration to v0.6.0 enables structured error routing (agents can
  distinguish branch vs commit vs test failures)
- Review panel results persist in koto context beyond wip/ cleanup, providing
  audit trails
- Koto's override system formalizes review skipping with mandatory rationale
- Single-issue mode has zero orchestrator overhead -- the queue script is only
  invoked for plan-backed execution
- The queue script is testable in CI, unlike prose-based orchestration

### Negative

- Two state sources for plan mode: manifest tracks issue status, koto tracks
  workflow state. Desynchronization is possible.
- Template grows from 17 to ~23 states, increasing cognitive load for
  contributors modifying the workflow.
- PLAN doc parsing in SKILL.md is prose-based and may fail on unusual formats.
- The queue script adds a shell + jq dependency for plan-backed execution.
- Contributors must understand both the script interface and SKILL.md
  orchestration to modify multi-issue behavior.

### Mitigations

- Reconciliation check: SKILL.md verifies manifest status matches koto workflow
  state on each loop iteration and on resume.
- Template complexity: states follow a consistent gate-plus-evidence pattern;
  new contributors learn one pattern, not 23 unique ones.
- PLAN format: standardized PLAN templates with schema validation reduce
  parsing failures.
- Dependency: jq is widely available and already used in the workspace for other
  scripts.
