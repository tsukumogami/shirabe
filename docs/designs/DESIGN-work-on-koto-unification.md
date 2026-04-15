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
  A parser script owned by /plan (plan-to-tasks.sh) transforms PLAN.md into
  the tasks JSON; /work-on pipes its stdout directly into koto via
  --with-data, so no intermediate file touches the repo tree. Koto's
  scheduler owns DAG resolution, ready-dispatch, retry, and terminal
  observability; koto's context store owns the tasks payload after
  submission. All gates migrate to v0.6.0 strict mode with selective
  decomposition. Review panels use context-exists gates for persistence
  and evidence enums for routing.
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
- Cross-issue context should stay below typical agent context windows;
  shirabe plans of 3-15 issues fit comfortably with no special handling
- The v0.6.0 `--allow-legacy-gates` flag is transitory and will be removed

## Koto v0.8.0 Reference

This design references several koto v0.8.0 mechanics by short ID. The
canonical specification is the koto repository (tsukumogami/koto) and the
batch-spawning design at `docs/designs/current/DESIGN-batch-child-spawning.md`
in that repo (shipped via tsukumogami/koto#130). Quick gloss:

| ID | Kind | Meaning |
|----|------|---------|
| `materialize_children` | Template hook | State-level block declaring a `from_field` (a `tasks`-typed evidence field), `failure_policy`, and `default_template`. Drives the scheduler. |
| `children-complete` | Gate type | Per-state gate that aggregates child workflow states into derived booleans (`all_complete`, `all_success`, `any_failed`, `needs_attention`, etc.) |
| `ready_to_drive` | Gate flag | Per-child boolean: `true` when child is non-terminal and all its `waits_on` ancestors are terminal-success. Workers only dispatch on children with this `true`. |
| `retry_failed` | Reserved evidence | Submitting `retry_failed` rewinds and respawns failed children. Deferred to a future revision in this design. |
| `batch_final_view` | Terminal field | Frozen snapshot on the parent's `done` response containing per-child `name`, `state`, `outcome`, `reason`, `reason_source`, etc. |
| `failure: true` | State field | Marks a terminal state as a failure so the batch view reports `outcome: failure` instead of `success` |
| `skipped_marker: true` | State field | Marks a terminal state as the routing target for children whose dependencies failed. Required by F5 if the template is batch-eligible. |
| `failure_reason` | Context key | Per-child context key written on the path to a failure terminal; surfaces in the batch view's per-child `reason` field |
| `union-by-name` | Submission rule | Re-submitting a `tasks` payload merges by `name`: spawned entries are locked (R8 immutability), un-spawned are last-write-wins |
| `E10` | Compile error | `materialize_children` and `children-complete` must be co-located on the same state (single-state fan-out) |
| `W4` | Compile warning | A materialized state routing only on `all_complete` without handling `any_failed` / `needs_attention` -- silent failure-swallowing |
| `W5` | Compile warning | A `failure: true` terminal with no path that writes `failure_reason` to context |
| `F5` | Compile warning | A batch-eligible child template missing a reachable `skipped_marker: true` state. Treated as enforcing here -- shirabe CI asserts no F5 warnings on `work-on.md` since batch eligibility is required. |
| `R0`-`R9` | Runtime rules | Pre-append validators on `tasks` submissions: non-empty list, name regex, DAG, dangling refs, name uniqueness, limit caps, immutability, etc. |
| `InvalidBatchReason` | Error envelope | Typed enum returned via `action: "error"` when R0-R9 reject a submission (e.g., `Cycle`, `NameRegex`, `SpawnedTaskMutated`) |

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

Three additive changes make the template batch-eligible under koto v0.8.0.
These are bundled here as a checklist for contributors editing
`work-on.md`; each is enforced by a koto compile-time warning, so missing
one fails template compilation, not a runtime test:

| Required addition | Compile guard | Where |
|-------------------|---------------|-------|
| `failure: true` on `done_blocked` terminal | (no warning -- defaults to false; CI assertion required) | Terminal state declaration |
| New `skipped_marker: true` terminal state, reachable from initial state | F5 | Add `skipped_due_to_dep_failure` terminal |
| `failure_reason` written to context on every path to `done_blocked` | W5 | Each failure-routing state writes it (see convention below) |

`failure_reason` write convention: each state that can route to
`done_blocked` writes `failure_reason` as part of the same evidence
submission that selects the `done_blocked` transition. This co-locates
the reason with the routing decision (each state knows why it's
escalating) and avoids the alternative of reconstructing a reason from
earlier evidence at the terminal. The pattern, applied uniformly:

```yaml
implementation:
  accepts:
    implementation_status:
      type: enum
      values: [complete, partial_tests_failing_retry, blocked]
    failure_reason:
      type: string
      required_when: { implementation_status: blocked }
  transitions:
    - target: scrutiny
      when: { implementation_status: complete }
    - target: done_blocked
      when: { implementation_status: blocked }
      context_assignments:
        failure_reason: ${evidence.failure_reason}
```

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
done. A parser script owned by /plan (`skills/plan/scripts/plan-to-tasks.sh`;
see Decision 5 below) transforms PLAN.md into the task-entry JSON on
stdout; /work-on pipes its output directly into
`koto next --with-data @-` (or a `mktemp` sandwich cleaned in the same
expression if koto rejects stdin). No JSON file persists in the repo tree
or in `wip/`; after submission, koto's context store owns the payload.
No orchestration script exists in the repo.

The batched state follows koto's mandatory single-state fan-out pattern (E10):
`materialize_children`, `accepts: tasks`, and `children-complete` gate all live
on the same state, which the advance loop parks at until completion.

```yaml
spawn_and_await:
  initial: true
  directive: |
    If tasks have not been submitted yet (koto context get $WF tasks
    returns no entry), regenerate them via:
      bash ${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh \
        $PLAN_DOC | koto next $WF --with-data @-
    (Or `mktemp`-sandwich if koto rejects stdin.) The response carries
    item_schema; the script's output already matches it.
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

1. `spawn_and_await` -- initial state. Batched per the YAML above. On first
   tick, the directive invokes the parser script (Decision 5) and pipes
   its stdout into `koto next --with-data @-`. Handles resume
   (re-submitting is a no-op under koto's union-by-name rules) without
   special handling.
2. `pr_coordination` -- reached on `all_success`. Runs plan-level PR QA,
   assembles the PR description from `batch_final_view`, handles CI.
3. `escalate` -- reached on `needs_attention`. Directive instructs the
   agent to inspect failed children via the batch view's `reason` and
   `reason_source` fields, write a human-readable failure summary, then
   transition to `done_blocked`. The `retry_failed` evidence path is
   deferred to a future revision: in v1, plan-level failures escalate
   to a human rather than retrying automatically. This keeps the agent
   in the loop for unexpected failures while leaving room to add
   retry semantics once a real recurrent-failure pattern emerges.
4. `done` / `done_blocked` -- terminal states.

A previous draft included a `parse_plan` precursor state. Decision 5
moved task assembly to a parser script invoked from `spawn_and_await`'s
directive, which made `parse_plan` vestigial; it was removed.

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

The parser script is the sole producer of this shape. It reads PLAN.md's
Implementation Issues table and dependency graph (or Issue Outlines in
single-pr mode) and emits deterministic JSON. PLAN schema changes and
parser changes travel together in /plan's PR, giving the format and its
reader a single authority. On resume or on a fresh clone of a merged
PLAN, re-running the script yields identical output -- no "rebuild mode"
ceremony is needed.

Single-issue and free-form modes are unaffected. They run the per-issue
template directly with no parent workflow.

#### Alternatives Considered

**Hybrid orchestrator with thin preflight script** (script validates
`tasks.json` shape before submission; koto handles scheduling). Rejected
because koto's R0-R9 validators run pre-append on submission with typed
`InvalidBatchReason` errors -- the typed envelope is richer than any shape
check a shell script would perform, and errors surface via the same
`action: "error"` response the rest of the workflow uses. A preflight script
would be a weaker duplicate. (Note: this rejection is about *orchestration*
and validation scripts, not about the PLAN parser script -- which is a
distinct concern covered separately and sits with /plan as the format
authority.)

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

### Decision 5: How /work-on obtains koto tasks evidence from a PLAN doc

The plan orchestrator template's `spawn_and_await` state needs a tasks JSON
payload submitted via `koto next --with-data`. The question is how /work-on
produces that payload from a PLAN doc.

Three constraints bound the answer. PLAN.md is the only artifact that
should land in main -- multi-pr plans routinely merge, and any JSON sidecar
committed alongside would accumulate in main's history. /work-on's current
convention is koto-native: the skill uses koto's context store as the
primary state path, with `wip/` only as a degradation fallback when koto
is unreachable (the `work-on.md` template has no `wip/` references).
Format authority: /plan writes PLAN.md and owns its `schema: plan/v1`, so
parsing logic should co-locate with the authority that controls format
evolution.

#### Chosen: Parser script owned by /plan, piped to koto by /work-on

Add `skills/plan/scripts/plan-to-tasks.sh` (bash + jq, following the
existing `build-dependency-graph.sh` pattern). The script takes a PLAN.md
path as argument and emits tasks JSON on stdout matching koto's task-entry
schema (array of `{name, vars, waits_on}` with `template` omitted so the
hook's `default_template` applies). Name sanitization for outline-only
items lives in the script with fixture coverage; collision handling is
deterministic.

The plan-orchestrator template's `spawn_and_await` directive invokes the
script and pipes directly into koto:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh" "$PLAN_DOC" \
  | koto next "$WF" --with-data @-
```

If koto rejects stdin, the fallback is a `mktemp` sandwich cleaned in the
same shell expression -- the tempfile lives in `$TMPDIR`, exists for
microseconds, and never reaches the repo tree. After submission, koto's
context owns the payload (key: `tasks`, retrievable via `koto context get
<plan-WF> tasks`); re-submission is a no-op under koto's union-by-name
rule. No JSON file persists anywhere in the repo.

The script is the sole producer of the task shape. PLAN schema changes
and parser changes travel together in /plan's PR with CI validating both.
Rerunning from a merged PLAN (fresh clone, only `docs/plans/PLAN-foo.md`
present) requires nothing new: the script regenerates JSON deterministically.

#### Alternatives Considered

**Inline prose parsing in /work-on**: SKILL.md prose reads PLAN.md and
composes tasks JSON inline. Rejected because 10-15k tokens per parse
(doubled across resume cycles) is material and LLM extraction is
probabilistic on edge cases (struck-through rows, child reference rows,
multi-line descriptions, Mermaid graph edges) -- a wrong dep edge routes
the wrong issue first and looks correct. No CI testability.

**Parser script owned by /work-on**: Same runtime mechanics as the chosen
option but with the script in `skills/work-on/scripts/`. Rejected on
format authority grounds: PLAN schema lives with /plan's writer, so the
reader belongs there too. Otherwise schema changes require coordinated
updates across skills with no CI bridge.

**Sidecar JSON in `docs/plans/`**: /plan emits a `.tasks.json` file
alongside PLAN.md. Rejected because it pollutes main on multi-pr merges.

**Sidecar JSON in `wip/`**: /plan or /work-on stages tasks JSON in `wip/`.
Rejected because /work-on no longer uses `wip/` for workflow state -- the
current skill is koto-context-first, and the template has no `wip/`
references. A new wip/ artifact would violate that invariant.

**Machine-readable block embedded in PLAN.md**: Extend frontmatter or add
a fenced `koto-tasks` block carrying task data inline. Rejected because
it duplicates the Implementation Issues table content within the same
file (no auto-sync, editor drift risk) and forces a `plan/v1` -> `v2`
schema migration for marginal benefit.

**Hybrid (prose driven, script for hard bits)**: SKILL.md prose with
targeted script invocation for graph extraction. Rejected as worst-of-both:
still pays inline parsing's token cost while requiring the script's CI
test surface, with ambiguous responsibility boundaries.

## Decision Outcome

**Chosen: Two templates + Pure koto orchestration + Strict gates + Context/evidence review panels**

### Summary

The unified work-on workflow uses two koto templates: a per-issue template
(`work-on.md`, ~24 states, 3-way entry routing) and a plan orchestrator
template (`work-on-plan.md`, 4 states). Single issues and free-form tasks use
`work-on.md` directly. Plan-backed execution creates a parent workflow from
`work-on-plan.md`, whose batched `spawn_and_await` state declares
`materialize_children` over a `tasks`-typed evidence field. Koto's scheduler
owns DAG resolution, ready-dispatch, retry, and terminal observability --
there are no orchestration scripts in this design. A single parser script
owned by /plan (`plan-to-tasks.sh`) transforms PLAN.md into the tasks JSON
on stdout; /work-on pipes it straight into `koto next --with-data`, so no
intermediate JSON file lives in the repo tree or in `wip/`.

The per-issue template routes issue-backed, free-form, and plan-backed modes
through mode-specific pre-analysis chains before converging at a shared
analysis state. Post-analysis, it flows through implementation, three review
states (scrutiny, review, qa_validation), finalization, PR creation, and CI
monitoring. Three additions make it batch-eligible: `failure: true` on
`done_blocked`, a `skipped_marker: true` terminal state, and `failure_reason`
written to context on escalation.

The plan orchestrator template has four states: `spawn_and_await`
(initial, batched; `materialize_children`, `accepts: tasks`, and
`children-complete` gate co-located per E10), `pr_coordination` (reached
on `all_success`; renders PR description from `batch_final_view`),
`escalate` (reached on `needs_attention`; agent inspects failures, writes
failure_reason summary, transitions to done_blocked), and `done` /
`done_blocked` terminals. Resume is mechanical: re-submitting the same
tasks JSON is a no-op under koto's union-by-name rules.

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

The unified work-on system uses two koto templates and one parser script
(owned by /plan). For single-issue and free-form tasks, the per-issue
template runs directly. For plan-backed execution, a parent workflow (plan
orchestrator template) declares a batch over a submitted task list; koto's
scheduler spawns children (per-issue template instances) and drives them to
completion. The SKILL.md coordinates mode detection, invokes /plan's parser
script to produce the tasks JSON, pipes it into koto, assembles cross-issue
context, and makes retry decisions.

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
    |       +-- At spawn_and_await state (initial):
    |       |     +-- first tick (if tasks not yet in koto context):
    |       |         bash ${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/
    |       |              plan-to-tasks.sh $PLAN_DOC |
    |       |         koto next <plan-WF> --with-data @-
    |       |     +-- koto validates (R0-R9), stores in context, materializes
    |       |         ready children atomically
    |       |     +-- subsequent ticks: koto next <plan-WF> (no data)
    |       |         drives next ready child via ready_to_drive gate
    |       |     +-- SKILL.md reads koto context get <child> summary.md
    |       |         for cross-issue context assembly
    |       |     +-- children-complete gate transitions to
    |       |         pr_coordination (all_success) or escalate (needs_attention)
    |       |
    |       +-- At escalate state (if reached):
    |       |     +-- agent inspects batch_final_view per-child reason
    |       |     +-- writes failure_reason summary to context
    |       |     +-- transitions to done_blocked
    |       |     (retry_failed deferred to future revision; v1 escalates to human)
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
- States: `spawn_and_await` (initial) -> `pr_coordination` | `escalate`
  -> `done` / `done_blocked` (4 states total)
- The `done` and `done_blocked` terminal names are reused by both
  templates. They live in separate workflows (parent and per-issue child),
  so koto treats them as distinct -- but readers should keep the context
  in mind: a child reaching `done_blocked` raises `failed` in the parent's
  batch view, while the parent's own `done_blocked` is the terminal for
  unrecoverable plan-level failure.
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

**Parser script** (`skills/plan/scripts/plan-to-tasks.sh`):
- Input: PLAN.md path as argument
- Output: JSON array of task entries (matching the schema above) on stdout
- Exit codes: 0 success, 1 malformed input, 2 PLAN schema mismatch
- Unit-tested via `plan-to-tasks_test.sh` with fixture PLANs covering
  multi-pr mode, single-pr mode, struck-through rows, child reference rows,
  and diamond dependency patterns

Submission flow: the script's stdout is piped directly into
`koto next <plan-WF> --with-data @-` (or a `mktemp` sandwich if koto rejects
stdin). The 1 MB payload cap is well above real plan sizes. No JSON file
persists in the repo tree or in `wip/`.

**Review panel interface** (unchanged):
- Input: koto directive at scrutiny/review/qa_validation state
- Output: aggregated JSON to koto context (`scrutiny_results.json`, etc.)
- Evidence: `passed | blocking_retry | blocking_escalate`

**Cross-issue context protocol**:
- Parent reads child outputs: `koto context get <child-WF> summary.md`
- SKILL.md assembles a snapshot from all completed children's summaries
  and writes it to the current child's context as `current-context.md`
  before the scheduler dispatches it
- Context size: typical shirabe plans are 3-15 issues, so a flat "include
  everything completed so far" approach stays within context budgets. A
  sliding window (most-recent-N full + older as one-liners) is deferred
  until a real plan demonstrates a budget problem; adding it later is a
  prose-only change in SKILL.md
- `batch_final_view` on the parent's terminal `done` response provides
  the full batch snapshot for PR description assembly. The
  `pr_coordination` directive consumes these per-child fields:
  - `name` -- the task name (e.g., `issue-47`); used for issue links
  - `outcome` -- `success | failure | skipped | spawn_failed`
  - `reason` -- failure reason (from context's `failure_reason` key on
    failed children, or auto-derived for skipped/spawn_failed)
  - `reason_source` -- `failure_reason | state_name | skipped | not_spawned`
    (for diagnostic clarity in the PR body)
  - `skipped_because_chain` -- present on skipped children; lists the
    upstream failure path

**Koto context store conventions**:
- The submitted `tasks` payload lives at koto context key `tasks` on the
  parent workflow after submission. Read it with
  `koto context get <plan-WF> tasks`
- Re-submitting an identical (or schema-compatible) `tasks` payload is a
  no-op per koto's union-by-name rule; submitting a schema-incompatible
  payload returns `action: "error"` with a typed `InvalidBatchReason`
  envelope (see Koto v0.8.0 reference below)
- Per-child summaries are written by the per-issue template at the
  `finalization` state directive to the child's context key `summary.md`;
  the parent reads them via `koto context get <child-WF> summary.md`
- Review panel results (`scrutiny_results.json`, `review_results.json`,
  `qa_results.json`) live in the per-issue child's context, written by
  the panel orchestration directives

### Data Flow

**Single-issue mode:**
```
SKILL.md detects mode -> koto init (one workflow) -> koto next loop ->
review panels at scrutiny/review/qa states -> done
```

**Plan mode:**
```
SKILL.md detects plan -> koto init plan-WF (initial: spawn_and_await) ->
  spawn_and_await state:
    first tick (no tasks in koto context yet):
      bash plan-to-tasks.sh $PLAN_DOC | koto next --with-data @-
      -> scheduler validates (R0-R9), stores tasks in koto context,
         materializes ready children ->
    subsequent ticks: koto next (no data)
      -> scheduler dispatches children with ready_to_drive: true ->
      -> SKILL.md assembles cross-issue context before each child ->
      -> SKILL.md drives each child's koto next loop until terminal ->
      -> scheduler reclassifies on each tick (stale skip markers refresh) ->
    children-complete gate evaluates all_success / needs_attention ->
  [all_success] pr_coordination: PR description from batch_final_view,
    plan-level QA, CI monitoring -> done
  [needs_attention] escalate: agent inspects failed children,
    writes failure_reason summary, transitions to done_blocked
```

**Resume:**
```
SKILL.md calls koto next on parent -> parent is at spawn_and_await ->
  if tasks already in koto context: koto next drives the next ready child
    via scheduler; scheduler returns existing child states from disk;
    SKILL.md resumes child-level koto next loops for non-terminal children
  if tasks not in koto context (fresh clone of merged PLAN): re-run
    `plan-to-tasks.sh | koto next --with-data @-`; deterministic output
    reproduces the same submission; union-by-name rules make re-submission
    a no-op for any already-spawned children
```

## Implementation Approach

The phases below are roughly sequential, but **Phases 1 and 2 are
independently shippable**. Gate migration (Phase 1) is a mechanical
template refactor with no dependencies on the rest of the design. Review
panel states (Phase 2) build on Phase 1 but stand alone -- they're
useful in single-issue and free-form modes today, before any plan-mode
work lands. A reasonable sequencing is two short PRs (Phase 1, then
Phase 2) before the larger plan-orchestrator work begins, to derisk
strict-mode compilation and panel state authoring against the existing
template before adding new templates and a parser script.

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

Author the parent workflow template. The template is 4 states plus a
reference to /plan's parser script for first-tick tasks submission.

Deliverables:
- `koto-templates/work-on-plan.md` with `spawn_and_await` (initial,
  single-state fan-out), `pr_coordination`, `escalate`, and the
  `done` / `done_blocked` terminal pair
- `materialize_children` hook pointing at `tasks` evidence field with
  `default_template: work-on.md` and `failure_policy: skip_dependents`
- `children-complete` gate co-located on `spawn_and_await` (E10)
- Transitions on `all_success` and `needs_attention` (W4 compliance)
- `spawn_and_await` directive referencing `skills/plan/scripts/plan-to-tasks.sh`
  by path, with the pipe-to-koto invocation pattern
- Strict-mode compilation passing

### Phase 4b: /plan parser script (prerequisite for Phase 4 template)

Add the PLAN-to-tasks parser script owned by /plan. This is a prerequisite
for Phase 4 because the template directive references it by path.

Deliverables:
- `skills/plan/scripts/plan-to-tasks.sh` (bash + jq):
  - Input: PLAN.md path as argument
  - Output: tasks JSON array on stdout matching koto's task-entry schema
  - Handles both multi-pr mode (Implementation Issues table) and
    single-pr mode (Issue Outlines)
  - Owns task-name generation including sanitization for outline-only
    items (`outline-<slug>` with deterministic collision handling)
  - Exit codes: 0 success, 1 malformed input, 2 PLAN schema mismatch
- `skills/plan/scripts/plan-to-tasks_test.sh` with three starter
  fixtures: one multi-pr plan, one single-pr plan, one diamond
  dependency graph. Add fixtures bug-driven as edge cases (struck-through
  rows, child reference rows, etc.) actually break against real PLANs.
- Add `plan-to-tasks.sh` as a "stable sub-operation" in /plan's SKILL.md
  reference table, alongside `create-issue.sh` and
  `create-issues-batch.sh`. This is the cross-skill contract pin
- A short contract reference (`skills/plan/references/plan-to-tasks-contract.md`)
  documenting the CLI shape, JSON output schema, and name-sanitization
  rules so /work-on's template directive stays grounded

### Phase 5: SKILL.md plan orchestration

Wire the plan-mode orchestration into SKILL.md: parent workflow init,
script-to-koto pipe at first tick, cross-issue context assembly, and
retry handling.

Deliverables:
- SKILL.md plan-mode section using `koto init` for the parent and
  `plan-to-tasks.sh | koto next --with-data @-` for first-tick submission
  (fall back to `mktemp` sandwich if koto rejects stdin; verify at
  implementation time)
- No prose-level PLAN parsing in SKILL.md; parsing is delegated to the
  script entirely
- Cross-issue context assembly via `koto context get <child> summary.md`
  for all completed children (windowing deferred until a real plan
  demonstrates a context budget problem)
- Escalate-state directive: agent inspects `batch_final_view`, writes a
  `failure_reason` summary, transitions to `done_blocked`. The
  `retry_failed` evidence path is deferred to a future revision.
- PR-level coordination: description from `batch_final_view`, single
  branch, single PR

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
- **Task-list submission**: `plan-to-tasks.sh` reads a local PLAN.md
  authored by the same user driving the skill and emits JSON on stdout,
  which /work-on pipes into `koto next --with-data @-`. Koto's R0-R9
  validators reject malformed payloads pre-append with typed
  `InvalidBatchReason` errors (cycle, dangling ref, duplicate name, limit
  overflow, name regex violation, reserved name collision). No shell
  interpretation of submitted content. The script itself is bash + jq
  with fixture-driven tests; it reads the PLAN path argument as a file
  (no shell eval) and treats PLAN content as data, not code.
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
- Zero orchestration scripts. The only script is /plan's PLAN-to-tasks
  parser, which is input translation (format authority stays with /plan)
  rather than workflow orchestration.
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
- Cross-skill coupling: /work-on's plan-orchestrator template directive
  references `skills/plan/scripts/plan-to-tasks.sh` by path. The contract
  is narrow (one CLI signature, one stdout format) but it is a contract.
- PLAN parser maintenance: bash + jq parsing of a markdown table has edge
  cases (embedded pipes in titles, struck-through rows, child reference
  rows, multi-line descriptions) that fixture tests must cover.
- Pinned koto version is now load-bearing. The workflow requires koto v0.8.0
  or later.
- Task-name sanitization for outline-only items lives in the parser
  script with fixture coverage; collision handling is deterministic but
  needs upkeep if PLAN outline titles ever produce non-trivial collisions.
- The per-issue template must preserve three additive requirements
  (`failure: true`, `skipped_marker` state, `failure_reason` writes) to
  remain batch-eligible. Contributors modifying `work-on.md` need to know
  this; the F5/W5 warnings fire at compile time to catch regressions.

### Mitigations

- Template separation: the plan orchestrator template is small (4 states)
  and changes rarely; the per-issue template is where most workflow
  evolution happens.
- Template complexity: states follow a consistent gate-plus-evidence
  pattern; new contributors learn one pattern, not 24 unique ones.
- PLAN format: the parser script lives with /plan, so PLAN schema changes
  and parser changes travel in one PR with CI validation on both sides.
  The koto `tasks` schema validation (R0-R9) catches bad compositions
  before they hit state.
- Cross-skill contract: a short contract reference document
  (`skills/plan/references/plan-to-tasks-contract.md`) pins the CLI
  signature and stdout format so future /work-on contributors can rely
  on a stable interface.
- Koto pinning: the workspace's koto installation is controlled by tsuku, so
  the version floor is a tsuku recipe concern. Shirabe's CI should assert
  the minimum koto version as part of template compilation.
- Name sanitization: lives in `plan-to-tasks.sh` with deterministic
  collision handling and fixture coverage. Regex violations fail fast at
  submission with typed `InvalidBatchReason::NameRegex` -- the script's
  output is validated by koto's R9 before any state changes.
- Batch-eligibility requirements: the three per-issue template additions are
  small and localized. F5 fires at compile time if `skipped_marker` is
  missing; W5 fires if `failure_reason` is not written on a failure terminal;
  Decision 5.1's `failure` field defaults to `false` so forgetting it
  silently downgrades batch accuracy -- a CI assertion on the compiled
  template should check that `done_blocked.failure == true`.
