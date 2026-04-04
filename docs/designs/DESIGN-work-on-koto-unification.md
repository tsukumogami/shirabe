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

The script (`scripts/plan-queue.sh`) exposes four subcommands:
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
