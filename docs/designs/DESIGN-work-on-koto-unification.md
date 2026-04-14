---
status: Proposed
problem: |
  The work-on skill and the private /implement workflow serve overlapping
  purposes with different orchestration backends. work-on uses koto for
  single-issue execution; /implement uses a custom Go workflow-tool for
  multi-issue plan execution. Koto v0.6.0 introduced structured gate output
  and first-class overrides, and koto v0.8.0 added declarative batch child
  spawning with dependency ordering. This design specifies how to unify both
  workflows into a single work-on entry point backed entirely by koto,
  handling free-form tasks, single issues, and full plan execution through
  shared components.
decision: |
  Two koto templates: a per-issue template (work-on.md, 3-way entry routing)
  and a plan orchestrator template (work-on-plan.md) whose batched state
  declares a materialize_children hook over a tasks-typed evidence field.
  The skill layer composes tasks.json once from the PLAN doc and submits it
  via koto next --with-data @tasks.json; koto's scheduler owns DAG
  resolution, ready-dispatch, retry, and terminal observability. All gates
  migrate to v0.6.0 strict mode with selective decomposition. Review panels
  use context-exists gates for persistence and evidence enums for routing.
rationale: |
  Koto v0.8.0's declarative batch spawning collapses the orchestrator to a
  single state with materialize_children, accepts: tasks, and a
  children-complete gate co-located per the E10 single-state fan-out rule.
  The dependency script the previous revision carried is deleted -- koto's
  scheduler handles DAG resolution, runtime reclassification, and retry with
  typed error envelopes. Koto is the single source of truth for all state
  across per-issue and plan-level execution; no shell scripts participate in
  orchestration.
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
gates, and query child state via `koto workflows --children`. This eliminated
the need for an external manifest to track multi-issue progress.

Koto v0.8.0 (tsukumogami/koto#130, released 2026-04-14) added declarative batch
child spawning. Parent templates declare a state-level `materialize_children`
hook pointing at a `tasks`-typed evidence field. A CLI-level scheduler builds
the DAG, classifies tasks against on-disk state, and spawns ready children
atomically. The scheduler exposes `ready_to_drive` dispatch gating,
`retry_failed` evidence for rewinding failed chains, runtime reclassification
of stale skip markers, and `batch_final_view` on terminal responses. This
removes the last external operation the orchestrator needed.

The goal is a single `/work-on` entry point that:
- Handles free-form tasks, single issues, and plan document paths
- Uses koto for all orchestration (replacing workflow-tool)
- Migrates to v0.6.0 structured gate output
- Shares components (review panels, context assembly, entry routing) across
  all execution modes

Exploration identified a three-layer architecture that, after the v0.8.0
revision, collapses to two layers:
1. **Koto per-issue state machine**: each issue gets its own koto workflow
2. **Koto parent workflow**: declares the batch via `materialize_children`;
   the SKILL.md composes the task list but performs no scheduling

## Decision Drivers

- Koto v0.8.0 handles batch child spawning end-to-end: parent-child links,
  dependency-aware scheduling, ready-dispatch gating, retry with typed error
  envelopes, and terminal observability via `batch_final_view`
- Koto v0.8.0 enforces single-state fan-out (E10): `materialize_children` and
  `children-complete` must live on the same state
- Koto v0.8.0 requires batch-eligible child templates to have `failure: true`
  on failure terminals, a `skipped_marker: true` terminal state (F5), and
  `failure_reason` written to context on escalation (W5)
- The existing work-on template has 17 states and 8 gates that need v0.6.0
  migration
- Review panels (3-agent scrutiny, 3-agent code review, QA) require multi-agent
  orchestration that koto gates can't express
- Cross-issue context must be bounded to prevent context window exhaustion on
  large plans (50+ issues)
- The v0.6.0 `--allow-legacy-gates` flag is transitory and will be removed

## Decisions Already Made

These choices were settled during exploration and should be treated as constraints:

- **Orchestrator lives in koto, not the skill layer**: koto v0.8.0 absorbs the
  last piece (dependency scheduling) that the skill layer owned; SKILL.md
  composes input (`tasks.json`) but performs no scheduling
- **Per-issue koto workflows, not monolithic**: each issue gets its own state
  file; avoids koto's lack of sub-workflows/iteration
- **Review panels stay in skill markdown**: koto gates handle binary checks;
  multi-agent orchestration with feedback loops isn't expressible as gates
- **Gate migration proceeds independently**: mechanical refactoring not blocked
  by orchestrator design
- **Koto hierarchy + batch for plan-level state**: v0.7.0's parent-child and
  v0.8.0's batch scheduler replace the external manifest and the dependency
  script; koto is the single source of truth for all state

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
The template grows from 17 to approximately 24 states (including review panel
states from Decision 4 and the `skipped_marker` terminal required by koto v0.8.0).

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

All post-analysis states remain shared. The parent workflow (Decision 2) handles
sequencing across issues by declaring a batch over the task list; this template
runs unchanged as the child template for each task.

Three additive changes make the template batch-eligible under koto v0.8.0:
- `failure: true` on the `done_blocked` terminal state so the batch view
  reports `outcome: failure` rather than counting a blocked issue as success
- A new `skipped_marker: true` terminal state (required by F5) that the
  scheduler routes children into when a dependency fails
- `failure_reason` written to context on paths to `done_blocked` (required
  by W5) so the batch view's per-child `reason` field is informative

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

*Re-evaluated after koto v0.8.0 (tsukumogami/koto#130) shipped declarative
batch child spawning.*

The /implement workflow's controller.go provides ~240 lines of orchestration:
dependency graph resolution, next-issue selection, auto-skip, variable
interpolation, directive generation. Koto v0.7.0 delivered parent-child links,
state tracking across children, and completion gating. Koto v0.8.0 closes the
remaining gap: the CLI-level scheduler builds the DAG from a submitted task
list, classifies tasks against on-disk state, spawns ready children atomically,
reclassifies stale skip markers at runtime, and surfaces typed errors through
`action: "error"` envelopes.

With v0.8.0 shipped, every operation the orchestrator needs lives in koto.
The question is whether that warrants a skill-layer shim (preflight validation,
status rendering, resume diagnostics) or a direct handoff to koto.

#### Chosen: Pure koto orchestration via `materialize_children`

The plan orchestrator template (`work-on-plan.md`) declares a single batched
state that accepts a `tasks` evidence field, materializes children via
`materialize_children`, and holds until `children-complete` reports the batch
done. The SKILL.md composes the task list once from the PLAN doc and submits
it via `koto next <plan-WF> --with-data @tasks.json`. No orchestration script
exists in the repo.

The batched state follows koto's mandatory single-state fan-out pattern (E10):
`materialize_children`, `accepts: tasks`, and `children-complete` gate all live
on the same state, which the advance loop parks at until completion.

```yaml
spawn_and_await:
  directive: |
    If you have not submitted a task list, parse the PLAN doc and submit
    via `koto next <WF> --with-data @tasks.json`. Each task entry shape:
    {name, vars, waits_on}. The response carries item_schema; validate
    before submission.
    If the batch is already running, invoke `koto next <WF>` with no data
    to drive the next ready child.
  accepts:
    tasks:
      type: tasks
      required: true
  materialize_children:
    from_field: tasks
    failure_policy: skip_dependents
    default_template: work-on.md
  gates:
    batch_done:
      type: children-complete
  transitions:
    - target: pr_coordination
      when:
        gates.batch_done.all_success: true
    - target: escalate
      when:
        gates.batch_done.needs_attention: true
```

The plan orchestrator's full state sequence:

1. `parse_plan` -- SKILL.md extracts issue outlines and dependencies into
   `tasks.json`. Simple transition forward.
2. `spawn_and_await` -- batched state per the YAML above. Handles first-time
   submission, resume (re-submitting is a no-op under koto's union-by-name
   rules), and retry (agent submits `retry_failed` evidence to rewind failed
   children).
3. `pr_coordination` -- reached on `all_success`. Runs plan-level PR QA,
   assembles the PR description from `batch_final_view`, handles CI.
4. `escalate` -- reached on `needs_attention`. Directive instructs the agent
   to inspect failed children via the batch view's `reason`/`reason_source`
   fields and decide between `retry_failed` (return to `spawn_and_await`) or
   human escalation (transition to `done_blocked`).
5. `done` / `done_blocked` -- terminal states.

Each task entry:
```json
{
  "name": "issue-47",
  "vars": {
    "ISSUE_NUMBER": "47",
    "ARTIFACT_PREFIX": "wip/issue_47",
    "PLAN_DOC": "docs/plans/PLAN-foo.md",
    "ISSUE_SOURCE": "github"
  },
  "waits_on": ["issue-45", "issue-46"]
}
```

`template` is omitted -- the hook's `default_template: work-on.md` applies.
Mixed populations work transparently: outline-only items set
`ISSUE_SOURCE: "plan_outline"` and use a sanitized name like
`outline-<slug>`; the per-issue template's 3-way entry routing handles both.

Single-issue and free-form modes are unaffected. They run the per-issue
template directly with no parent workflow.

#### Alternatives Considered

**Hybrid orchestrator with thin preflight script** (script validates
`tasks.json` shape before submission; koto handles scheduling). Rejected
because koto's R0-R9 validators run pre-append on submission with typed
`InvalidBatchReason` errors -- the typed envelope is richer than any shape
check a shell script would perform, and errors surface via the same
`action: "error"` response the rest of the workflow uses. A preflight script
would be a weaker duplicate.

**Retain the script, use it only for resume diagnostics**
(`plan-deps.sh status` reads koto's output and renders a human summary).
Rejected because `koto workflows --children <parent>` and `koto status` already
render the same view with `batch.phase`, `synthetic`, `skipped_because_chain`,
and `reason_source` fields. A second renderer would lag koto's evolution.

**Two-state orchestrator (`spawn` + `await`) with a no-op transition**.
Rejected: E10 makes this a compile error (`materialize_children` without a
co-located `children-complete` gate). Working around E10 by splitting
submission and waiting would defeat the rule's purpose -- the scheduler tick
runs on the state the advance loop parks at, not a state it passes through.

**SKILL.md-only orchestrator (no parent template)** with the agent driving
per-issue koto workflows in a prose loop and coordinating via `wip/` state.
Rejected because it loses koto-enforced invariants (E10, W4, F5), loses
`retry_failed` / `batch_final_view` / runtime reclassification, and
re-introduces a second source of truth for batch progress. These are the
exact problems koto v0.8.0 solves; opting out defeats the migration.

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

The `blocking_escalate` path routes to `done_blocked`, which carries
`failure: true` (per Decision 1's koto v0.8.0 additions). In plan-backed mode,
this surfaces through the parent's batch view as `outcome: failure`, keeping
`all_success` accurate. The escalation path writes `failure_reason` to
context so the batch view's per-child `reason` field is informative.

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

**Chosen: Two templates + Pure koto orchestration + Strict gates + Context/evidence review panels**

### Summary

The unified work-on workflow uses two koto templates: a per-issue template
(`work-on.md`, ~24 states, 3-way entry routing) and a plan orchestrator
template (`work-on-plan.md`, ~5 states). Single issues and free-form tasks use
`work-on.md` directly. Plan-backed execution creates a parent workflow from
`work-on-plan.md`, whose batched `spawn_and_await` state declares
`materialize_children` over a `tasks`-typed evidence field. Koto's scheduler
owns DAG resolution, ready-dispatch, retry, and terminal observability --
there are no orchestration scripts in this design.

The per-issue template routes issue-backed, free-form, and plan-backed modes
through mode-specific pre-analysis chains before converging at a shared
analysis state. Post-analysis, it flows through implementation, three review
states (scrutiny, review, qa_validation), finalization, PR creation, and CI
monitoring. Three additions make it batch-eligible: `failure: true` on
`done_blocked`, a `skipped_marker: true` terminal state, and `failure_reason`
written to context on escalation.

The plan orchestrator template has five states: `parse_plan` (SKILL.md
assembles `tasks.json`), `spawn_and_await` (batched; `materialize_children`,
`accepts: tasks`, and `children-complete` gate co-located per E10),
`pr_coordination` (reached on `all_success`; renders PR description from
`batch_final_view`), `escalate` (reached on `needs_attention`; agent decides
between `retry_failed` or human escalation), and `done` / `done_blocked`
terminals. Resume is mechanical: re-submitting the same `tasks.json` is a
no-op under koto's union-by-name rules.

All gates migrate to v0.6.0 strict mode. The `code_committed` gate decomposes
into three atomic gates so agents can distinguish failure types. Review
panels write results to koto context for persistence; the skill layer submits
evidence enums for transition routing. Koto's override mechanism provides
formal review skipping with mandatory rationale.

Cross-issue context flows via `koto context get <child-WF> summary.md`
between ticks; the SKILL.md assembles a sliding-window snapshot (2 most
recent full summaries + one-line entries for older children) and writes it
to the next child's context before driving it.

### Rationale

Koto v0.8.0's batch surface collapses the two-layer orchestrator (koto +
dependency script) of the v0.7.0 revision into a single koto layer. Every
operation the script provided -- dependency resolution, ready selection,
auto-skip, status queries -- lives in koto's scheduler with typed error
envelopes and compile-time enforcement (E10, W4, F5). Keeping a shim script
would duplicate koto's behavior at lower fidelity and create two sources of
truth.

The per-issue template, gate migration, and review panel decisions compose
cleanly with pure koto orchestration. Decision 1's 3-way entry routing
runs unchanged as the child template; Decision 3's gate migration happens
per-issue and is independent; Decision 4's review panels remain in skill
prose with their state-level audit trail. Decision 1 absorbs three small
additions (`failure: true`, `skipped_marker`, `failure_reason`) required for
koto v0.8.0 batch eligibility -- these are additive to the template shape,
not contradictory.

Compile-time invariants replace runtime checks the orchestrator would have
had to enforce: W4 prevents silent success routing when children fail, F5
requires a reachable `skipped_marker` state, W5 warns when a failure
terminal doesn't write `failure_reason`. The template compiler is now the
primary correctness check for the batch contract.

## Solution Architecture

### Overview

The unified work-on system uses two koto templates and no orchestration
scripts. For single-issue and free-form tasks, the per-issue template runs
directly. For plan-backed execution, a parent workflow (plan orchestrator
template) declares a batch over a submitted task list; koto's scheduler
spawns children (per-issue template instances) and drives them to completion.
The SKILL.md coordinates mode detection, task-list composition, cross-issue
context assembly, and retry decisions.

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
    |       |       --var PLAN_DOC=<path>
    |       |
    |       +-- At parse_plan state:
    |       |     +-- SKILL.md reads PLAN doc
    |       |     +-- Composes tasks.json (name, vars, waits_on per item)
    |       |     +-- submits trivial evidence to advance
    |       |
    |       +-- At spawn_and_await state:
    |       |     +-- first tick: koto next <plan-WF> --with-data @tasks.json
    |       |     +-- koto scheduler materializes ready children atomically
    |       |     +-- subsequent ticks: koto next <plan-WF> (no data)
    |       |         drives next ready child via ready_to_drive gate
    |       |     +-- SKILL.md reads koto context get <child> summary.md
    |       |         for cross-issue context assembly
    |       |     +-- children-complete gate transitions to
    |       |         pr_coordination (all_success) or escalate (needs_attention)
    |       |
    |       +-- At escalate state (if reached):
    |       |     +-- agent inspects batch_final_view per-child reason
    |       |     +-- submits retry_failed evidence -> returns to spawn_and_await
    |       |     +-- OR transitions to done_blocked with failure_reason
    |       |
    |       +-- At pr_coordination state:
    |             +-- PR description rendered from batch_final_view
    |             +-- plan-level PR QA
    |             +-- CI monitoring
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
- Per-issue variables:
  - `ISSUE_NUMBER` (issue_backed, and plan_backed when `ISSUE_SOURCE=github`)
  - `ARTIFACT_PREFIX` (all modes)
  - `PLAN_DOC` (plan_backed)
  - `ISSUE_SOURCE` enum `[github, plan_outline]` (plan_backed only) --
    determines whether the plan-backed pre-analysis reads from GitHub via
    `gh issue view` or extracts the item section from the PLAN doc
- Terminal states: `done`, `done_blocked` (`failure: true`),
  `skipped_due_to_dep_failure` (`skipped_marker: true`), `validation_exit`
- Failure-reason writes: on paths to `done_blocked`, the state's directive
  writes a short reason string to koto context key `failure_reason` so it
  surfaces in the parent's batch view
- ~24 states, ~10 gates (after decomposition)

**Plan orchestrator template** (`koto-templates/work-on-plan.md`):
- States: `parse_plan` -> `spawn_and_await` -> `pr_coordination` | `escalate`
  -> `done` / `done_blocked`
- `spawn_and_await` state (single-state fan-out per E10):
  ```yaml
  spawn_and_await:
    accepts:
      tasks:
        type: tasks
        required: true
    materialize_children:
      from_field: tasks
      failure_policy: skip_dependents
      default_template: work-on.md
    gates:
      batch_done:
        type: children-complete
    transitions:
      - target: pr_coordination
        when:
          gates.batch_done.all_success: true
      - target: escalate
        when:
          gates.batch_done.needs_attention: true
  ```
- `batch_done` gate output: `{total, completed, pending, success, failed,
  skipped, blocked, all_complete, all_success, any_failed, any_skipped,
  any_spawn_failed, needs_attention, children: [...]}`

**Task entry schema** (koto v0.8.0):

| Field | Type | Source |
|-------|------|--------|
| `name` | string matching `^[A-Za-z0-9_-]+$`, 1-64 chars | `"issue-<N>"` for GH issues, `"outline-<slug>"` for outline items |
| `vars` | object string->string | `{ISSUE_NUMBER, ARTIFACT_PREFIX, PLAN_DOC, ISSUE_SOURCE}` |
| `waits_on` | array of string | sibling task names from PLAN doc dependencies |
| `template` | string (optional) | omitted; hook's `default_template` applies |

Submission via `koto next <plan-WF> --with-data @tasks.json` (1 MB payload
cap; plans well below this in practice).

**Review panel interface** (unchanged):
- Input: koto directive at scrutiny/review/qa_validation state
- Output: aggregated JSON to koto context (`scrutiny_results.json`, etc.)
- Evidence: `passed | blocking_retry | blocking_escalate`

**Cross-issue context protocol**:
- Parent reads child outputs: `koto context get <child-WF> summary.md`
- SKILL.md assembles snapshot from 2 most recent completed children's
  summaries plus cumulative files changed, writes to current child's context
  as `current-context.md` before the scheduler dispatches it
- Sliding window: children older than the 2 most recent are represented as
  one-line entries (number, title, status) rather than full summaries
- `batch_final_view` on the parent's terminal `done` response provides the
  full batch snapshot (per-child `name`, `state`, `outcome`, `reason`,
  `reason_source`) for PR description assembly

### Data Flow

**Single-issue mode:**
```
SKILL.md detects mode -> koto init (one workflow) -> koto next loop ->
review panels at scrutiny/review/qa states -> done
```

**Plan mode:**
```
SKILL.md detects plan -> koto init plan-WF ->
  parse_plan state: SKILL.md reads PLAN doc, composes tasks.json ->
    submits trivial evidence to advance ->
  spawn_and_await state:
    first tick: koto next --with-data @tasks.json
      -> scheduler validates (R0-R9), materializes ready children ->
    subsequent ticks: koto next (no data)
      -> scheduler dispatches children with ready_to_drive: true ->
      -> SKILL.md assembles cross-issue context before each child ->
      -> SKILL.md drives each child's koto next loop until terminal ->
      -> scheduler reclassifies on each tick (stale skip markers refresh) ->
    children-complete gate evaluates all_success / needs_attention ->
  [all_success] pr_coordination: PR description from batch_final_view,
    plan-level QA, CI monitoring -> done
  [needs_attention] escalate: agent inspects failed children,
    submits retry_failed (returns to spawn_and_await) or
    transitions to done_blocked with failure_reason
```

**Resume:**
```
SKILL.md calls koto next on parent -> parent is at spawn_and_await ->
  if tasks.json not yet submitted: re-submit (same payload is a no-op under
    union-by-name rules)
  if already submitted: koto next drives the next ready child via scheduler ->
    scheduler returns existing child states from disk; SKILL.md resumes
    child-level koto next loops for non-terminal children
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

### Phase 3: Plan-backed entry path and batch-eligibility changes

Add the plan_backed mode to the per-issue entry state and create the pre-analysis
chain (plan_context_injection, plan_validation, setup_plan_backed). The
`plan_context_injection` state routes on `ISSUE_SOURCE`: when `github`, it runs
`gh issue view <ISSUE_NUMBER>` and the existing staleness check; when
`plan_outline`, it extracts the item's section from `PLAN_DOC` and skips
staleness (no GitHub issue to check against).

Apply the three koto v0.8.0 batch-eligibility changes to the per-issue template:
`failure: true` on `done_blocked`, a new `skipped_marker: true` terminal state,
and `failure_reason` context writes on escalation paths.

Deliverables:
- Updated entry state with 3-way mode enum
- Plan-backed pre-analysis states in per-issue template
- `failure: true` on `done_blocked`
- New `skipped_due_to_dep_failure` terminal state with `skipped_marker: true`
- Directive updates to write `failure_reason` on paths to `done_blocked`
- SKILL.md mode detection logic for plan document paths

### Phase 4: Plan orchestrator template

Author the parent workflow template. No scripts -- the plan orchestrator is a
5-state template plus `tasks.json` composition in SKILL.md prose.

Deliverables:
- `koto-templates/work-on-plan.md` with `parse_plan`, `spawn_and_await`
  (single-state fan-out), `pr_coordination`, `escalate`, `done` / `done_blocked`
- `materialize_children` hook pointing at `tasks` evidence field with
  `default_template: work-on.md` and `failure_policy: skip_dependents`
- `children-complete` gate co-located on `spawn_and_await` (E10)
- Transitions on `all_success` and `needs_attention` (W4 compliance)
- Strict-mode compilation passing

### Phase 5: SKILL.md plan orchestration

Wire the plan-mode orchestration into SKILL.md: parent workflow init, PLAN doc
parsing into `tasks.json`, cross-issue context assembly, and retry handling.

Deliverables:
- SKILL.md plan-mode section using `koto init` for the parent and
  `koto next --with-data @tasks.json` for batch submission
- PLAN doc parser in SKILL.md prose producing `tasks.json` (name
  sanitization, var assembly, deps extraction)
- Cross-issue context assembly via `koto context get <child> summary.md`
  with sliding window (2 most recent full, older as one-liners)
- Escalate-state directive guiding inspection of `batch_final_view` and the
  retry decision
- PR-level coordination: description from `batch_final_view`, single branch,
  single PR

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
- **Task-list submission**: `koto next --with-data @tasks.json` reads a local
  file authored by the same user driving the skill. Koto's R0-R9 validators
  reject malformed payloads pre-append with typed `InvalidBatchReason` errors
  (cycle, dangling ref, duplicate name, limit overflow, name regex violation,
  reserved name collision). No shell interpretation of submitted content.
- **Template variable interpolation**: koto substitutes `vars` entries into
  gate command strings before shell execution. `ISSUE_NUMBER` must be validated
  as numeric, `PLAN_DOC` as a valid file path, and `ISSUE_SOURCE` against its
  enum values at `koto init` time (or at task-list composition for batch
  children) to prevent shell injection via crafted variable values. Task-entry
  names additionally pass koto's regex `^[A-Za-z0-9_-]+$` (R9).
- **Context store**: koto context keys store workflow artifacts (summaries,
  review results, failure reasons). No credentials or secrets are stored in
  context.
- **Child spawn path resolution**: koto v0.8.0 resolves `default_template`
  relative to the parent template's source directory first, then the
  submitter's cwd (Decision 4 in koto#130). Since both templates live in
  `koto-templates/` in this repo, the primary base always wins and there is
  no ambiguity.

## Consequences

### Positive

- Single `/work-on` entry point replaces three workflows (work-on, /implement,
  /implement-doc) with a unified skill.
- Koto is the single source of truth for all state -- no manifest file, no
  reconciliation protocol, no dependency script, no two-source
  desynchronization risk.
- Zero shell scripts participate in plan orchestration. Testing is integration
  testing against koto, not unit testing a dependency-graph implementation.
- Koto hierarchy plus batch scheduling provides resume for free --
  re-submitting `tasks.json` is a no-op under union-by-name rules; the
  scheduler picks up from on-disk child state.
- Retry is declarative. A failed child chain recovers via `retry_failed`
  evidence without manual `koto init` calls.
- Gate migration to v0.6.0 enables structured error routing (agents can
  distinguish branch vs commit vs test failures).
- Review panel results persist in koto context beyond wip/ cleanup, providing
  audit trails.
- Koto's override system formalizes review skipping with mandatory rationale.
- Single-issue mode has zero orchestrator overhead -- the parent template is
  only used for plan-backed execution.
- Compile-time invariants (E10, W4, F5, W5) enforce correctness that the
  previous design had to promise by hand.
- `batch_final_view` on the terminal `done` response gives PR-description
  assembly a single source for per-child outcomes and reasons.

### Negative

- Two templates to maintain (`work-on.md` and `work-on-plan.md`) instead of
  one.
- Per-issue template grows from 17 to ~24 states (including review panel
  states and the new `skipped_marker` terminal), increasing cognitive load
  for contributors modifying the workflow.
- PLAN doc parsing in SKILL.md is prose-based and may fail on unusual
  formats.
- Pinned koto version is now load-bearing. The workflow requires koto v0.8.0
  or later.
- Task-name sanitization for outline-only items (not GitHub-issue-backed)
  lives in SKILL.md prose and needs care for edge cases (slug collisions,
  regex violations).
- The per-issue template must preserve three additive requirements
  (`failure: true`, `skipped_marker` state, `failure_reason` writes) to
  remain batch-eligible. Contributors modifying `work-on.md` need to know
  this; the F5/W5 warnings fire at compile time to catch regressions.

### Mitigations

- Template separation: the plan orchestrator template is small (~5 states)
  and changes rarely; the per-issue template is where most workflow
  evolution happens.
- Template complexity: states follow a consistent gate-plus-evidence
  pattern; new contributors learn one pattern, not 24 unique ones.
- PLAN format: standardized PLAN templates with schema validation reduce
  parsing failures. The koto `tasks` schema validation (R0-R9) catches
  bad compositions before they hit state.
- Koto pinning: the workspace's koto installation is controlled by tsuku, so
  the version floor is a tsuku recipe concern. Shirabe's CI should assert
  the minimum koto version as part of template compilation.
- Name sanitization: a small helper function in SKILL.md (documented with
  examples) produces compliant names from outline titles. Regex violations
  fail fast at submission with typed `InvalidBatchReason::NameRegex`.
- Batch-eligibility requirements: the three per-issue template additions are
  small and localized. F5 fires at compile time if `skipped_marker` is
  missing; W5 fires if `failure_reason` is not written on a failure terminal;
  Decision 5.1's `failure` field defaults to `false` so forgetting it
  silently downgrades batch accuracy -- a CI assertion on the compiled
  template should check that `done_blocked.failure == true`.
