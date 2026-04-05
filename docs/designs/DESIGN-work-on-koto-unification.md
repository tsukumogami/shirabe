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
  Two koto templates: a per-issue template (work-on.md, 3-way entry routing)
  and a plan orchestrator template (work-on-plan.md) that uses koto v0.7.0's
  hierarchical workflows to spawn and coordinate child workflows via
  children-complete gates. A dependency graph script handles inter-child
  ordering -- the one thing koto hierarchy doesn't express. All gates
  migrate to v0.6.0 strict mode with selective decomposition. Review panels
  use context-exists gates for persistence and evidence enums for routing.
rationale: |
  Koto v0.7.0's hierarchical workflows eliminate the manifest file and
  reconciliation protocol that the original design required. The parent
  template uses children-complete gates to wait for child workflows, and
  koto workflows --children provides state queries. The dependency graph
  script remains because koto can't express inter-child ordering, but it
  shrinks to a single subcommand. Koto is now the single source of truth
  for both per-issue and plan-level state.
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

Koto v0.7.0 added hierarchical multi-level workflows: parent workflows spawn
children via `koto init --parent`, wait for completion via `children-complete`
gates, and query child state via `koto workflows --children`. This eliminates
the need for an external manifest to track multi-issue progress.

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

- Koto v0.7.0 supports hierarchical workflows: parent-child links, children-complete
  gates, and hierarchy discovery -- but not inter-child dependency ordering
- The existing work-on template has 17 states and 8 gates that need v0.6.0
  migration
- workflow-tool's dependency resolution and queue selection have no koto equivalent;
  other controller capabilities (state tracking, status queries) are now covered by
  koto hierarchy
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
- **Koto hierarchy for plan-level state**: v0.7.0's parent-child workflows replace
  the external manifest; koto is the single source of truth for issue progress

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

*Revised after koto v0.7.0 shipped hierarchical workflow support.*

The /implement workflow's controller.go provides ~240 lines of orchestration:
dependency graph resolution, next-issue selection, auto-skip, variable
interpolation, directive generation. Koto v0.7.0 now handles parent-child
workflow links, state tracking across children, and completion gating via
`children-complete`. The remaining gap is inter-child dependency ordering --
koto can tell you when all children are done, but not which child to spawn next
based on a dependency graph.

The core tension is narrower than before: dependency graph resolution is the
only operation that needs external logic. Status tracking, child discovery,
and completion detection are all in koto now.

#### Chosen: Koto parent workflow + dependency script

A plan orchestrator template (`work-on-plan.md`) manages the plan-level
lifecycle as a koto workflow. The SKILL.md spawns child workflows via
`koto init issue-N --parent <plan-WF> --template work-on.md --var ISSUE_NUMBER=N`.
A lightweight dependency script determines spawn order.

The parent template has states:
- `parse_plan`: extract issue outlines and dependencies from PLAN doc
- `spawn_and_execute`: iterative state where the skill layer spawns ready
  children and runs them; self-loops until all children are spawned
- `await_completion`: `children-complete` gate waits for all children to
  reach terminal state
- `pr_coordination`: PR-level QA, finalization, CI monitoring
- `done` / `done_blocked`: terminal states

The dependency script (`scripts/plan-deps.sh`) reuses existing logic from
`skills/plan/scripts/build-dependency-graph.sh` and exposes one subcommand:
- `next-ready <plan-doc> <completed-json>`: given the PLAN doc's dependency
  graph and a JSON array of completed issue numbers, returns the next
  spawnable issues as JSON

The SKILL.md orchestration at `spawn_and_execute`:
1. Calls `koto workflows --children <plan-WF>` to get current child states
2. Builds the completed list from children in terminal states
3. Calls `plan-deps.sh next-ready` with the completed list
4. Spawns new children for returned issues
5. Runs each child via `koto next` until terminal or blocking
6. Self-loops until no more issues to spawn and all spawned children are terminal
7. Submits evidence to advance to `await_completion`

The `children-complete` gate at `await_completion` confirms all children reached
terminal state. Its structured output (`total`, `completed`, `all_complete`,
per-child state array) provides the parent's transition routing.

Cross-issue context: the SKILL.md reads completed child context via
`koto context get <child-WF> summary.md` to assemble snapshots for the
next child. Koto's hierarchical context means parents can read child
outputs directly -- no shared manifest needed.

Single-issue and free-form modes don't create a parent workflow -- they run
the per-issue template directly, same as today.

#### Alternatives Considered

**Hybrid orchestrator with external manifest** (original Decision 2): Script
manages a manifest JSON with issue statuses, dependency graph, and queue
selection. SKILL.md manages context assembly and koto workflow init. Was the
best option before v0.7.0. Rejected now because koto hierarchy eliminates the
manifest, the reconciliation protocol, and 3 of the script's 4 subcommands.
Two sources of truth become one.

**SKILL.md-only orchestrator**: All logic in prose, including dependency
resolution. Still rejected -- dependency graph operations in natural language
are unreliable for >5 issues and not testable in CI. The script remains
necessary for this specific operation.

**Full koto orchestration (no script)**: Parent template handles everything
including dependency ordering. Rejected because koto v0.7.0 has no declarative
inter-child dependency mechanism. The `children-complete` gate checks
completion, not ordering. A future koto release could add dependency-aware
child spawning, which would eliminate the script entirely.

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

**Chosen: Two templates + Koto hierarchy + Dependency script + Strict gates + Context/evidence review panels**

### Summary

The unified work-on workflow uses two koto templates: a per-issue template
(`work-on.md`, ~23 states, 3-way entry routing) and a plan orchestrator template
(`work-on-plan.md`) that uses koto v0.7.0's hierarchical workflows to manage
multi-issue execution. Single issues and free-form tasks use `work-on.md` directly.
Plan-backed execution creates a parent workflow from `work-on-plan.md`, which
spawns child workflows from `work-on.md` via `koto init --parent`.

The per-issue template routes issue-backed, free-form, and plan-backed modes through
mode-specific pre-analysis chains before converging at a shared analysis state.
Post-analysis, it flows through implementation, three review states (scrutiny, review,
qa_validation), finalization, PR creation, and CI monitoring.

The plan orchestrator template manages the plan lifecycle: parse the PLAN doc, spawn
and execute child workflows respecting dependency order, wait for all children via
a `children-complete` gate, then coordinate PR-level QA and finalization. A
lightweight dependency script (`scripts/plan-deps.sh`) handles the one thing koto
hierarchy doesn't -- inter-child dependency ordering. The script exposes a single
subcommand (`next-ready`) that takes the dependency graph and completed issue list
and returns which issues can be spawned next.

Koto is the single source of truth for all state. The parent workflow tracks plan
progress. Each child workflow tracks per-issue progress. `koto workflows --children`
provides hierarchy discovery. Cross-issue context flows via `koto context get
<child-WF> summary.md` -- parents read child outputs directly. No manifest file or
reconciliation protocol needed.

All gates migrate to v0.6.0 strict mode with structured output routing. The
`code_committed` gate decomposes into three atomic gates so agents can distinguish
failure types. Review panels write results to koto context for persistence, then the
skill layer submits evidence enums for transition routing. Koto's override mechanism
provides formal review skipping with mandatory rationale.

### Rationale

Koto v0.7.0's hierarchical workflows collapse the original three-layer architecture
(koto + skill orchestrator + manifest/script) into a cleaner two-layer design
(koto for all state + script for dependency ordering). The parent-child link
(`koto init --parent`) and `children-complete` gate replace the manifest JSON,
the reconciliation protocol, and three of the original script's four subcommands.
Koto's event log becomes the single source of truth for both per-issue and
plan-level state, eliminating the two-source desynchronization risk.

The dependency script remains because koto v0.7.0 treats children as unordered --
it can tell you when they're all done, but not which to spawn next. This is a
narrow, testable responsibility. A future koto release adding dependency-aware
child spawning would eliminate the script entirely.

The per-issue template, gate migration, and review panel decisions are unchanged
from the original design -- they operate at the per-issue level where koto
hierarchy has no effect.

## Solution Architecture

### Overview

The unified work-on system uses two koto templates and a dependency script. For
single-issue and free-form tasks, the per-issue template runs directly. For
plan-backed execution, a parent workflow (plan orchestrator template) spawns child
workflows (per-issue template) using koto v0.7.0's hierarchy. The SKILL.md
coordinates mode detection, child spawning with dependency ordering, and
cross-issue context assembly.

### Components

```
/work-on (user entry point)
    |
    v
SKILL.md (coordinator)
    |
    +-- Mode detection (issue / free-form / plan)
    |
    +-- [single-issue / free-form]
    |       |
    |       +-- koto init <WF> --template work-on.md --var ISSUE_NUMBER=N
    |       +-- koto next <WF> (loop until terminal)
    |
    +-- [plan mode]
    |       |
    |       +-- koto init <plan-WF> --template work-on-plan.md
    |       |
    |       +-- At spawn_and_execute state:
    |       |     +-- koto workflows --children <plan-WF> (get child states)
    |       |     +-- scripts/plan-deps.sh next-ready (dependency ordering)
    |       |     +-- koto init issue-N --parent <plan-WF> --template work-on.md
    |       |     +-- koto next issue-N (run child until terminal)
    |       |     +-- koto context get issue-N summary.md (read child output)
    |       |     +-- [loop: spawn next ready children]
    |       |
    |       +-- At await_completion state:
    |             +-- children-complete gate (all children terminal)
    |
    +-- Review panel orchestration (shared, runs within per-issue template)
            |
            +-- Scrutiny (3 agents parallel)
            +-- Code review (3 agents parallel)
            +-- QA validation (tester agent)
```

### Key Interfaces

**Per-issue template** (`koto-templates/work-on.md`):
- Entry state: `mode` enum `[issue_backed, free_form, plan_backed]`
- Per-issue variables: `ISSUE_NUMBER`, `ARTIFACT_PREFIX`, `PLAN_DOC` (plan mode)
- Terminal states: `done`, `done_blocked`, `validation_exit`
- ~23 states, ~10 gates (after decomposition)

**Plan orchestrator template** (`koto-templates/work-on-plan.md`):
- States: `parse_plan` -> `spawn_and_execute` -> `await_completion` ->
  `pr_coordination` -> `done` / `done_blocked`
- Gate at `await_completion`:
  ```yaml
  gates:
    children_done:
      type: children-complete
      completion: "terminal"
  transitions:
    - target: pr_coordination
      when:
        gates.children_done.all_complete: true
  ```
- Structured output: `{total, completed, pending, all_complete, children: [{name, state, complete}]}`

**Dependency script** (`scripts/plan-deps.sh`):
- Reuses `skills/plan/scripts/build-dependency-graph.sh`
- Single subcommand: `next-ready <plan-doc> <completed-json>`
- Input: PLAN doc path + JSON array of completed issue numbers
- Output: `[{"number": N, "title": "...", "agent_type": "coder"}]`

**Review panel interface** (unchanged):
- Input: koto directive at scrutiny/review/qa_validation state
- Output: aggregated JSON to koto context (`scrutiny_results.json`, etc.)
- Evidence: `passed | blocking_retry | blocking_escalate`

**Cross-issue context protocol**:
- Parent reads child outputs: `koto context get <child-WF> summary.md`
- SKILL.md assembles snapshot from 2 most recent completed children's summaries
  plus cumulative files changed, writes to current child's context as
  `current-context.md` before starting it
- Sliding window: children older than the 2 most recent are represented as
  one-line entries (number, title, status) rather than full summaries

### Data Flow

**Single-issue mode:**
```
SKILL.md detects mode -> koto init (one workflow) -> koto next loop ->
review panels at scrutiny/review/qa states -> done
```

**Plan mode:**
```
SKILL.md detects plan -> koto init plan-WF (parent) ->
  parse_plan state: SKILL.md extracts issues from PLAN doc ->
  spawn_and_execute state:
    plan-deps.sh next-ready -> spawn ready children via koto init --parent ->
    run each child via koto next loop -> child reaches terminal ->
    read child context (summary) -> plan-deps.sh next-ready (repeat) ->
    all children spawned and running ->
  await_completion state: children-complete gate passes ->
  pr_coordination: PR-level QA -> done
```

**Resume:**
```
SKILL.md calls koto next on parent -> parent is at spawn_and_execute ->
koto workflows --children shows existing children and their states ->
plan-deps.sh next-ready with completed children -> resume or spawn next
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

Add the plan_backed mode to the per-issue entry state and create the pre-analysis
chain (plan_context_injection, plan_validation, setup_plan_backed).

Deliverables:
- Updated entry state with 3-way mode enum
- Plan-backed pre-analysis states in per-issue template
- SKILL.md mode detection logic for plan document paths

### Phase 4: Plan orchestrator template and dependency script

Create the parent workflow template and the dependency ordering script.

Deliverables:
- `koto-templates/work-on-plan.md` with plan lifecycle states and
  `children-complete` gate
- `scripts/plan-deps.sh` with `next-ready` subcommand
- Reuse of `build-dependency-graph.sh` for graph computation
- Unit tests for dependency resolution logic

### Phase 5: SKILL.md plan orchestration

Wire the plan-mode orchestration into SKILL.md: parent workflow init, child
spawning loop, cross-issue context assembly, and resume.

Deliverables:
- SKILL.md plan-mode section using `koto init --parent` for child creation
- Spawn loop using `koto workflows --children` + `plan-deps.sh next-ready`
- Cross-issue context assembly via `koto context get <child> summary.md`
- Resume logic via parent workflow state + child discovery
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
- **Script execution**: `plan-deps.sh` reads the PLAN doc and a JSON array of
  completed issue numbers. It doesn't execute arbitrary commands or process
  untrusted input beyond PLAN doc content authored by the same user.
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
- Koto is the single source of truth for all state -- no manifest file, no
  reconciliation protocol, no two-source desynchronization risk
- Koto hierarchy provides resume for free -- `koto next` on the parent discovers
  existing children and their states without external tracking
- Gate migration to v0.6.0 enables structured error routing (agents can
  distinguish branch vs commit vs test failures)
- Review panel results persist in koto context beyond wip/ cleanup, providing
  audit trails
- Koto's override system formalizes review skipping with mandatory rationale
- Single-issue mode has zero orchestrator overhead -- the parent template and
  dependency script are only used for plan-backed execution
- The dependency script is small (~1 subcommand) and testable in CI

### Negative

- Two templates to maintain (`work-on.md` and `work-on-plan.md`) instead of one.
- Per-issue template grows from 17 to ~23 states, increasing cognitive load for
  contributors modifying the workflow.
- PLAN doc parsing in SKILL.md is prose-based and may fail on unusual formats.
- The dependency script adds a shell + jq dependency for plan-backed execution.
- Koto v0.7.0 hierarchy is new -- less battle-tested than the v0.6.0 features.

### Mitigations

- Template separation: the plan orchestrator template is small (~5 states) and
  changes rarely; the per-issue template is where most workflow evolution happens.
- Template complexity: states follow a consistent gate-plus-evidence pattern;
  new contributors learn one pattern, not 23 unique ones.
- PLAN format: standardized PLAN templates with schema validation reduce
  parsing failures.
- Dependency: jq is widely available and already used in the workspace for other
  scripts.
- Hierarchy maturity: the `children-complete` gate is conceptually simple
  (scan children, check terminal state). Early adoption helps surface issues
  before more complex hierarchies are built.
