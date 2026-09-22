# Exploration Findings: scope-then-execute

## Core Question

Can one agent session take a feature from `/scope` all the way to merged code
when the PLAN is `single-pr` or `coordinated`, given that the execution mode is
only decided inside `/scope`? And if the PLAN lands `multi-pr`, what should that
same session do instead of stalling on merges it can't perform?

## Round 1

### Key Insights

- **Nothing in shirabe merges.** `/execute` single-pr ends at `gh pr ready` with
  green CI; `/work-on` ends at "PR open, CI green". No skill calls `gh pr merge`,
  and the draft/ready design says "the agent marks ready; the human merges".
  `/execute`'s description and its `full-run` exit still promise "merged".
  (lead-execute-merge, lead-multi-pr-fallback, lead-parent-composition)
- **`coordinated` is not a one-session mode without merge rights.** Its loop
  walks a merge-order DAG of per-repo PRs and only advances when predecessors
  merge; the coordination PR merges last. It behaves like multi-pr with a
  coordinator on top. The one-session case is really `single-pr` alone.
  (lead-execute-merge, lead-scope-exit)
- **The mode is mostly predictable, and knowable at two points.** `coordinated`
  is fixed at `/scope` Phase 0 (from `--coordinated` or CLAUDE.md headers), before
  any hop runs. `single-pr` vs `multi-pr` is decided at `/plan` step 3.6, defaults
  to single-pr under the repo's Delivery Preference, and splits only on a Hard
  Constraint, Incremental Value, or a CLAUDE.md-declared Stated Preference.
  History: 7 single-pr, 5 multi-pr, 0 coordinated; every single-feature PLAN since
  June was single-pr. (lead-mode-decision)
- **No per-run steering exists.** `/scope` passes `/plan` only the DESIGN path
  (plus `--upstream`). The Delivery Preference stack documents a "flag" layer that
  `/plan` does not define. Goal text cannot count as a Stated Preference.
  (lead-mode-decision)
- **The branch model already expects the continuation, but a push is missing.**
  `/execute` adopts the scoping branch and its open PR as the home PR, so PLAN and
  code ship in one PR. But `/scope` never pushes or opens a PR in single-repo
  mode, so `/execute` falls back to cutting `impl/<slug>` from the scoping branch.
  (lead-execute-merge, lead-parent-composition, lead-scope-exit)
- **No recorded decision forbids chaining parents**, and the parent-skill pattern
  names a "parent-of-the-parent" slot. Every existing precedent (explore handoff,
  work-on dispatcher) stops and names the next command instead of invoking it.
  No `--continue`, `--through`, or umbrella command exists. (lead-parent-composition)
- **`/scope` exits with a bare line and no next step**:
  `/scope finished: exit=full-run; artifact=docs/plans/PLAN-<topic>.md`.
  (lead-scope-exit)
- **Multi-pr fallback shape:** push a scoping-docs PR, PLAN Active with issues
  filed, report the unblocked issues. Per-issue fan-out through
  `niwa dispatch --detach` is feasible once the docs PR merges.
  (lead-multi-pr-fallback)

### Tensions

- The user's premise groups `coordinated` with `single-pr`; the code groups it
  with `multi-pr` whenever the session can't merge.
- "Done only when merged" versus "the agent marks ready; the human merges": the
  goal as stated is unsatisfiable for every mode unless merge authority is
  granted explicitly.
- Stop-and-name-the-command is the house pattern for parent handoffs, while the
  author wants an automatic continuation. Explore's rationale (resume ladders,
  re-entry protection) applies to explore invoking a parent mid-session; it's
  unclear whether it applies to `/scope` -> `/execute`.

### Gaps

- Whether `/scope --auto` forwards `--auto` to `/plan`, so step 3.6 and the
  issue-filing approval don't block an unattended run.
- Whether a per-issue `/work-on` run on a multi-pr PLAN ends at `done_blocked`
  under the new cascade (read from the template, not run).
- How `/plan` learns coordination intent to write `execution_mode: coordinated`.

### Stale or contradictory docs found along the way

- `/scope` Phase 3 says single-pr PLANs exit Draft; `/plan` writes them Active.
- `/plan` Phase 7 and `/scope`'s resume redirect send single-pr/Active PLANs to
  `/work-on`, though `/execute` owns single-pr and coordinated.
- `references/parent-skill-state-schema.md` lists `plan_execution_mode` as
  `single-pr | multi-pr`, missing `coordinated`.
- `/scope` Phase 3 writes the chain record "into the run's pull-request body" that
  it never opens.

### Decisions

See `wip/explore_scope-then-execute_decisions.md`.

### User Focus

The author offered to take questions mid-run and answered three: done means
"merge when permitted"; coordinated and multi-pr should get different
approaches (multi-pr is the only mode whose Active PLAN may merge to main); and
the author suspects the coordinated/multi-pr distinction is really caller
intent, asking for a recommendation rather than taking that as given. The
exploration checked `references/coordination-strategy.md` and
`skills/execute/SKILL.md` and recommends adopting intent as the axis (see
decisions).

## Accumulated Understanding

The author's problem is real, but its shape differs slightly from the premise.
The launch-time uncertainty is smaller than it looks: coordinated intent is
settled before `/scope` runs any hop, and single-pr is the default that only a
named split reason overturns. What's missing is a runtime branch at `/scope`'s
exit: read the PLAN's `execution_mode` and either continue into `/execute`
(single-pr) or stop cleanly with a docs PR and a list of dispatchable issues
(multi-pr, and coordinated without merge rights).

Two things a combined run needs are owned by nobody today: pushing the scoping
branch and opening its PR so `/execute` adopts it, and merging. The goal "done
when merged" therefore needs either a redefined terminal ("ready and handed off
for merge") or an explicit, permission-checked merge step. That's a policy
choice, not a mechanical gap.

Where the continuation lives is the main open architectural question: a flag on
`/scope` (e.g. continue into `/execute` when the mode allows), a thin driver
skill above both parents, or a documented goal recipe with a conditional. A
per-run delivery-preference flag that `/scope` forwards to `/plan` is a
complementary lever that would let the author bias toward single-pr at launch.

### Revised after author input

The launch-time uncertainty dissolves if the caller declares intent when
launching `/scope`. With "continue into execution", `/plan`'s split step still
prefers single-pr, and any multi-PR split resolves to `coordinated`, which a
driving session can run: merging when it has permission, suspending on the
coordination PR and resuming when it doesn't. With "stop at PLAN", splits
resolve to `multi-pr`, the docs PR lands the Active PLAN on main, and per-issue
sessions take over. That means lifting coordinated's multi-repo-only
restriction, adding a permission-checked merge step, having `/scope` push and
open its PR so `/execute` adopts it, and deciding where the continuation lives
(a `/scope` flag, a thin driver, or a goal recipe).

## Decision: Crystallize
