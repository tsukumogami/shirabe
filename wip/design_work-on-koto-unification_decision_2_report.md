<!-- decision:start id="multi-issue-orchestrator" status="assumed" -->
### Decision: Multi-Issue Orchestrator Architecture

**Context**

The work-on skill unification absorbs the /implement workflow's multi-issue
execution capability. The original /implement controller provided dependency
graph resolution, ready-issue selection, auto-skip of blocked dependents,
variable interpolation, and per-issue directive generation.

Koto v0.7.0 shipped hierarchical workflows (parent/child, children-complete
gate) which eliminated the need for an external manifest. The design previously
landed on a two-layer split: koto owned state, and a single-purpose
`plan-deps.sh next-ready` script owned dependency ordering -- the one piece
koto couldn't express.

Koto v0.8.0 (tsukumogami/koto#130, released 2026-04-14) shipped declarative
batch child spawning. Parent templates now declare a state-level
`materialize_children` hook pointing at a `tasks`-typed evidence field. On
submission, a CLI-level scheduler builds the DAG, classifies tasks against
on-disk state, and spawns ready children atomically. The scheduler exposes
`ready_to_drive` dispatch gating, `retry_failed` evidence for rewinding failed
chains, runtime reclassification of stale skip markers, and `batch_final_view`
on terminal responses. This removes the last external operation the orchestrator
needed.

The question is whether this shifts the responsibility boundary far enough to
drop the script entirely, or whether the script retains value (e.g. for input
validation, preflight, resume diagnostics).

**Assumptions**

- Koto v0.8.0 is available in the workspace's pinned koto version at the time
  this design is implemented
- Plan sizes fit koto's batch limits (R6): ≤1000 tasks, ≤10 `waits_on` per
  task, DAG node-depth ≤50 -- shirabe plans are typically 3-30 issues, so this
  is not a binding constraint
- Task names generated from issue data satisfy koto's name regex
  (`^[A-Za-z0-9_-]+$`, 1-64 chars, not in reserved set
  `{retry_failed, cancel_tasks}`) after straightforward sanitization
- Child template path resolution (koto Decision 4 in #130) using parent
  template source directory as the primary base works for shirabe's layout
  where both templates live in `koto-templates/`
- The per-issue template can adopt the three small additions koto v0.8.0
  requires of batch-eligible children: `failure: true` on the failure
  terminal, a `skipped_marker: true` state, and `failure_reason` written to
  context on escalation

**Chosen: Pure koto orchestration via `materialize_children`**

The plan orchestrator template (`work-on-plan.md`) declares a
single batched state that accepts a `tasks` evidence field, materializes
children via `materialize_children`, and holds until `children-complete`
reports the batch done. The SKILL.md composes the task list once from the
PLAN doc and submits it as a file via `koto next <parent-WF> --with-data
@tasks.json`. The script is deleted.

The batched state follows koto's mandatory single-state fan-out pattern (E10):
`materialize_children`, `accepts: tasks`, and `children-complete` gate all
live on the same state, which the advance loop parks at until completion.

```yaml
spawn_and_await:
  directive: |
    If you have not submitted a task list, parse the PLAN doc and submit
    via `koto next <WF> --with-data @tasks.json`. The tasks field accepts
    an array of {name, vars, waits_on} entries. Use the item_schema in the
    response to validate shape before submitting.
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

The plan orchestrator's full state sequence becomes:

1. `parse_plan` -- SKILL.md extracts issue outlines and dependencies into
   `tasks.json`. No batch operations yet. Simple transition forward.
2. `spawn_and_await` -- batched state per the YAML above. Handles first-time
   submission, resume (re-entering with the same submitted payload is a no-op
   under koto's union-by-name rules), and retry (agent submits `retry_failed`
   evidence to rewind failed children).
3. `pr_coordination` -- reached on `all_success`. Runs plan-level PR QA,
   assembles the PR description from `batch_final_view`, handles CI.
4. `escalate` -- reached on `needs_attention`. Directive instructs the agent
   to inspect failed children via the batch view's `reason`/`reason_source`
   fields and decide between `retry_failed` (go back to `spawn_and_await`) or
   human escalation (transition to `done_blocked`).
5. `done` / `done_blocked` -- terminal states.

The task entry each item produces:
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
`ISSUE_SOURCE: "plan_outline"` and drop the GitHub-issue-number dependency;
the per-issue template's existing 3-way entry routing handles both.

The per-issue template (`work-on.md`) absorbs three compile requirements from
koto v0.8.0:

- `failure: true` on `done_blocked` (koto Decision 5.1) so the batch view
  reports `outcome: failure` and increments the `failed` counter rather than
  counting a blocked issue as success
- A `skipped_marker: true` terminal state (koto F5) so the scheduler can
  delete-and-respawn children whose dependencies fail. The state is
  vacuously terminal; it only exists for the scheduler to route into.
- `failure_reason` written to context on the path to `done_blocked` (koto W5)
  so the batch view's per-child `reason` field is informative

Single-issue and free-form modes are unaffected. They run the per-issue
template directly with no parent workflow -- koto v0.8.0 doesn't touch
non-batched workflows.

**Rationale**

The previous hybrid (script + parent workflow) was the best available shape
under koto v0.7.0. The script existed for one reason: computing which issues
were ready to spawn given a dependency graph and a set of completed children.
Koto v0.8.0 moved that computation into the scheduler with richer
semantics than the script had -- per-task spawn error classification,
runtime reclassification of stale skip markers, atomic-per-tick commits
under retry, precedence-ordered rejection. Keeping a shim script to duplicate
a subset of that logic would be strictly worse: more surface area, two sources
of truth about task readiness, inevitable drift from koto's canonical
behavior.

Dropping the script also collapses two states (`spawn_and_execute` +
`await_completion`) into one. Koto's E10 rule -- `materialize_children` and
`children-complete` must live on the same state -- makes this collapse
mandatory, not stylistic. The advance loop parks at the batched state until
children are terminal; the scheduler tick on each `koto next` call drives
progress. There is no separate "spawn" and "wait" phase from the template's
perspective, because the scheduler is a property of the state, not a state
itself.

Koto's compile-time rules additionally enforce correctness the design
previously had to promise by hand. W4 (a materialized state routing only on
`all_complete: true` without handling `any_failed`/`needs_attention` is a
compile warning) directly rejects the failure-swallowing scenario the
original Decision 2 worried about. F5 (batch-eligible child templates must
declare a reachable `skipped_marker` state) prevents the cross-template
routing problem the design's skip handling would otherwise have hit.

Cross-issue context assembly moves unchanged: SKILL.md still reads
`koto context get <child-WF> summary.md` between ticks to build context for
the next child. The batched state's directive is the coordination point
where the agent assembles context before driving the next child. Koto's
`batch_final_view` on the terminal `done` response replaces an earlier plan
to reconstruct plan summaries by scanning children -- one JSON field delivers
the full snapshot.

**Alternatives Considered**

- **Hybrid orchestrator with thin preflight script** (script validates
  `tasks.json` shape before submission; koto handles scheduling). Rejected
  because koto's R0-R9 validators run pre-append on submission with typed
  `InvalidBatchReason` errors -- the typed envelope is richer than any shape
  check a shell script would perform, and errors surface via the same
  `action: "error"` response the rest of the workflow uses. A preflight
  script would be a weaker duplicate.

- **Retain the script, use it only for resume diagnostics**
  (`plan-deps.sh status` reads koto's output and renders a human summary).
  Rejected because `koto workflows --children <parent>` and `koto status`
  already render the same view with koto's `batch.phase`, `synthetic`,
  `skipped_because_chain`, and `reason_source` fields. A second renderer
  would lag koto's evolution.

- **Two-state orchestrator (`spawn` + `await`) with a no-op transition**.
  Rejected: E10 makes this a compile error (`materialize_children` without
  a co-located `children-complete` gate). Working around E10 by splitting
  submission and waiting would defeat the rule's purpose -- the scheduler
  tick runs on the state the advance loop parks at, not a state it passes
  through.

- **SKILL.md-only orchestrator (no parent template)** with the agent driving
  per-issue koto workflows in a prose loop and coordinating via `wip/` state.
  Rejected because it loses koto-enforced invariants (E10, W4, F5),
  loses `retry_failed` / `batch_final_view` / runtime reclassification, and
  re-introduces a second source of truth for batch progress. These are the
  exact problems koto v0.8.0 solves; opting out defeats the migration.

**Consequences**

What becomes easier:

- Zero shell scripts for plan-mode orchestration. Testing becomes integration
  testing against koto, not unit testing a dependency-graph script.
- Retry is declarative. A failed child chain recovers via `retry_failed`
  evidence without manual `koto init` calls or state-file manipulation.
- Resume is mechanical. Re-submitting the same `tasks.json` on resume is a
  no-op under koto's union-by-name rules; the scheduler picks up where it
  left off using on-disk child state.
- Failure semantics are first-class. `done_blocked` with `failure: true`
  propagates through the batch view, increments `failed`, and prevents
  `all_success` from being true. The compile rules (W4, W5) enforce
  correctness at template-authoring time.
- PR assembly has a single source. `batch_final_view` on the terminal `done`
  response carries per-child name, state, outcome, and `reason` -- the PR
  description can render directly from it.
- The plan orchestrator template is small (~5 states) and rarely changes.
  Per-plan complexity now lives in the `tasks.json` the agent assembles, not
  in orchestrator code.

What becomes harder:

- Task name generation needs discipline. Issue numbers fit the regex, but
  outline-only items need a sanitizer (e.g., `outline-<slug>`). The
  sanitizer lives in SKILL.md prose and needs care for edge cases.
- Per-issue template grows slightly. Adding `failure: true`, a
  `skipped_marker` state, and `failure_reason` writes is straightforward but
  non-obvious -- contributors modifying `work-on.md` need to preserve these
  to keep it batch-eligible. The F5 warning fires at compile time to catch
  regressions, so the pain is bounded.
- Diagnosing spawn failures requires reading typed error envelopes. Koto's
  `BatchError` / `InvalidBatchReason` / `TaskSpawnError.kind` are structured,
  but the SKILL.md escalation directive needs to map these to actionable
  guidance. This is a one-time authoring cost.
- Pinned koto version is now load-bearing. The workflow requires koto v0.8.0
  or later. The workspace's koto installation is controlled by tsuku, so this
  is a tsuku recipe concern, not a shirabe concern -- but it's a coupling
  that didn't exist before.
<!-- decision:end -->
