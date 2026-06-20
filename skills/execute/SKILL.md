---
name: execute
description: >-
  Implementation-altitude parent skill that owns plan-level execution. Takes a
  finished PLAN doc and drives it to merged code, delegating each single issue to
  /work-on. Use to run a plan end-to-end: `/execute docs/plans/PLAN-<topic>.md`.
  Skeleton scope (this slice): single-pr plans only. Coordinated multi-repo
  execution, cross-branch resume/state, parent-skill conformance, and security
  hardening are added by later issues in PLAN-execute-skill.md.
---

# Execute

`/execute` is the third parent skill in the trio, at the implementation altitude
(alongside `/charter` strategic and `/scope` tactical). It owns **plan-level
execution**: given a finished PLAN, it drives the plan's issues to merged code and
delegates each single issue to `/work-on`'s single-issue engine. `/work-on` itself
stays the canonical single-issue executor; `/execute` does not reimplement
single-issue mechanics.

This SKILL is the **walking-skeleton slice** (Issue 1 of `PLAN-execute-skill.md`):
it runs a single-pr PLAN end-to-end by lifting `/work-on`'s plan-orchestrator
template and pointing each per-issue child at `/work-on`'s `work-on.md` over a
cross-skill reference. The remaining shapes and guarantees land in later issues:

- coordinated multi-repo execution — Issue 4
- state projection, cross-branch resume, exit-path bindings — Issue 5
- parent-skill conformance + the six security surfaces — Issue 6
- backward-compatibility + parity-survival evals — Issue 7

## Input Modes

From `$ARGUMENTS`:

1. **Path to a PLAN doc** (`docs/plans/PLAN-*.md`, or any `.md` whose frontmatter
   has `schema: plan/v1`) — read the PLAN's `execution_mode`:
   - `single-pr` — run the single-pr execution path below.
   - `coordinated` — not implemented in this slice; report that coordinated support
     lands in Issue 4 and stop.
   - `multi-pr` — out of scope for `/execute`; multi-pr plans run one issue at a time
     through `/work-on` against the repo-persisted PLAN. Direct the user to `/work-on`.
2. **Empty** — ask which PLAN to execute.

## Single-PR Execution Path

The single-pr path reuses `/work-on`'s proven plan-orchestrator (lifted into this
skill, unchanged in behavior) so the value capabilities of multi-issue execution —
the base-branch drift gate, cross-issue carry-forward, dependency sequencing with
skip-dependents, shared-branch CI choreography, and the atomic finalization cascade
— carry over by construction rather than reimplementation.

### Step 1 — Preflight (cross-skill coupling)

Before any child is spawned, assert the cross-skill `/work-on` child template
resolves:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh
```

A non-zero exit halts the run with a clear message. This is the load-bearing
cross-skill reference: `/execute` spawns per-issue children with `/work-on`'s
`work-on.md`, referenced relatively from the lifted template as
`../../work-on/koto-templates/work-on.md` (canonically
`${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md`).

### Step 2 — Initialize the plan-level orchestrator

Derive the plan slug from the filename (`PLAN-foo-bar.md` → `foo-bar`) and
initialize the lifted orchestrator template:

```bash
koto init execute-<plan-slug> \
  --template ${CLAUDE_PLUGIN_ROOT}/skills/execute/koto-templates/work-on-plan.md \
  --var PLAN_DOC=<path-to-plan>
```

### Step 3 — Drive the orchestrator loop

In autonomous mode, drive this loop continuously per the **Autonomy** section below — do not stop between issues to advise a checkpoint. Drive the koto loop over the lifted `execute-plan` template, which carries the
orchestrator states (Issue 2 removed this machinery from `/work-on`; it lives here
now). The states and their tick mechanics:

- `orchestrator_setup` — create (or reuse, via `status: override`) the shared
  `impl/<slug>` branch and a draft PR.
- `spawn_and_await` — run `plan-to-tasks.sh` against the PLAN, inject `SHARED_BRANCH`
  into each task, submit `tasks`; koto materializes one child per issue using the
  cross-skill `work-on.md` (`default_template` in the lifted template).
- cross-issue context assembly between children; escalation on blocked/skipped.
- `pr_finalization` — assemble the combined PR body.
- `plan_completion` — run the finalization cascade, then `gh pr ready`; CI re-runs
  strict on the now-ready PR.

Each per-issue child is a `/work-on` single-issue run on the shared branch; the
narrowing of `/work-on` to single-issue-only (so it no longer carries the
orchestrator) is Issue 2 and does not block this slice.

## Autonomy

`/execute` honors an explicit autonomy mode — the `--auto` flag, or a clear author
instruction such as "run autonomously" or "don't stop" (resolved `flag > CLAUDE.md
## Execution Mode: header > default interactive`).

When authorized to run autonomously, the orchestrator loop (Step 3) runs to the
done-signal or a genuine blocker and **does not** pause for checkpoints, confirmation,
reassurance, or unsolicited advisory stops. It **does not** stop because the work is
large, because issues remain, or out of concern for its own context budget: the
coordinator stays thin by delegating each issue to a fresh `/work-on` child and reading
only status, so its context lasts the whole run. Stopping mid-run to "advise a
checkpoint" on an authorized autonomous run wastes the time the author set aside and is
forbidden.

**Genuine blockers that stop the run** (emit the forced-stop operator summary): a child
that fails or blocks needing human judgment and cannot be auto-resolved or isolated by
skip-dependents; an upstream-must-change boundary; a merge conflict or dirty state; a
destructive or irreversible action needing confirmation.

**Not blockers** (take the default, record it in the koto decision log, continue): a
decision with a reasonable default; the size or remaining count of the work; the
coordinator's own context budget.

In default (interactive) mode the existing approval/checkpoint behavior is unchanged;
the mandate governs the authorized-autonomous mode specifically.

## Team Shape

Single-agent parent in this slice — no team is spawned at the `/execute` layer. The
per-issue children are koto-materialized `/work-on` single-issue workflows on the
shared branch (the same dispatch `/work-on`'s plan-orchestrator uses today). The
full parent-skill conformance binding (state schema, resume ladder, three exit
paths, metadata-only inspection, security surfaces) is Issue 6.

## Reference Files

| File | When |
|------|------|
| `skills/execute/koto-templates/work-on-plan.md` | the lifted `execute-plan` orchestrator template |
| `skills/execute/scripts/preflight.sh` | Step 1 cross-skill preflight |
| `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` | the single-issue engine each child delegates to |
