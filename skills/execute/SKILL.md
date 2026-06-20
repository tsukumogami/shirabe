---
name: execute
description: >-
  Implementation-altitude parent skill that owns plan-level execution. Takes a
  finished PLAN doc and drives it to merged code, delegating each single issue to
  /work-on. Use to run a plan end-to-end: `/execute docs/plans/PLAN-<topic>.md`.
  Scope (current slice): single-pr and coordinated plans. Cross-branch
  resume/state, parent-skill conformance, and security hardening are added by
  later issues in PLAN-execute-skill.md.
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
cross-skill reference, and runs a coordinated multi-repo PLAN as a plain
durable-state loop over the coordination PR's merge-order DAG. The remaining
guarantees land in later issues:

- state projection, cross-branch resume, exit-path bindings — Issue 5
- parent-skill conformance + the six security surfaces — Issue 6
- backward-compatibility + parity-survival evals — Issue 7

## Input Modes

From `$ARGUMENTS`:

1. **Path to a PLAN doc** (`docs/plans/PLAN-*.md`, or any `.md` whose frontmatter
   has `schema: plan/v1`) — read the PLAN's `execution_mode`:
   - `single-pr` — run the single-pr execution path below.
   - `coordinated` — run the coordinated execution path below.
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
- `plan_completion` — run the finalization cascade
  (`${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/run-cascade.sh`, relocated into
  `/execute` along with its `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch), then
  `gh pr ready`; the cascade runs BEFORE the PR flips ready (DRAFT-before-READY)
  so CI re-runs strict on the now-ready PR against the finalized chain.

Each per-issue child is a `/work-on` single-issue run on the shared branch; the
narrowing of `/work-on` to single-issue-only (so it no longer carries the
orchestrator) is Issue 2 and does not block this slice.

## Coordinated Execution Path

A `coordinated` PLAN spans more than one repository, so there is no single shared
branch and no plan-spanning koto session (koto has no cross-repo session). The
coordinated path is therefore a **plain durable-state loop** the SKILL drives
directly: the durable state lives on the **coordination PR** itself (its PR-Index
and fenced merge-order block), and each pass refreshes from live `gh`, advances the
merge-order DAG, and re-gates. The full coordinated contract — the coordination PR,
the create → track → finalize → merge-last lifecycle, the coarsest-legal-grouping
rule, the two-node merge-order DAG, the done-signal, and the load-bearing F1/F2/F4
rules — is canonical in
[`${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md`](../../references/coordination-strategy.md).
This path **binds** to that contract and does not restate it; the `shirabe validate`
mode args (`--coordination-body`, `--merge-gate`) and their fail-closed behavior are
owned by the CLI.

This path is **metadata-only**: it reads issue/PR status and the merge-gate result,
never child PR bodies. It runs against an existing coordination PR (creating the
coordination home up front stays `/scope`'s responsibility; `/execute` consumes it).

### Step 1 — Preflight

Assert the same cross-skill `work-on.md` child template resolves (per-repo PR nodes
dispatch to it), and confirm `gh` auth is live — it is a precondition, since every
status read and every body write goes through `gh`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh
```

A non-zero exit halts the run. Locate the coordination PR for this effort (the
home PR carrying the verbatim `This is a **coordination PR**` declaration marker)
before entering the loop.

### Step 2 — Drive the track-to-merge-last loop

Loop the following pass until the done-signal fires. Every step that goes through
`gh` is **fail-closed**: a `gh` failure halts and surfaces the failed step (R21); it
never papers over a failed step as success and never advances past a coordination
step it could not complete.

1. **Refresh coordination state from live `gh`.** Read each indexed PR's live
   merged/open status on the operator's own `gh` credentials. Re-validate the
   `repo` / `pr_group` tags on this read (not only at authoring time), because the
   index is re-derived from the editable body each pass.
2. **Re-author the coordination body and re-validate on write.** Rewrite the
   PR-Index and the fenced merge-order block from the template in
   `coordination-strategy.md`, derived from the PLAN and the live `gh` reads, keeping
   the declaration marker verbatim. Run the **full**
   `shirabe validate --coordination-body <file>` on the rewritten body (declaration
   marker present, every reference passes F2, merge-order acyclic) — the offline
   authoring surface runs on every write, not just the merge-gate on read — then post
   with `gh pr edit`. A public coordination PR never embeds private-repo content
   (F1); a reference that fails F2 component validation halts with a diagnostic
   (R21), never silently skipped.
3. **Walk the merge-order DAG.** A node is unblocked when every predecessor is
   satisfied (a PR node when its PR has merged; a gate node when its condition
   verifies live). For each unblocked **PR node**, dispatch its issue(s) to
   `/work-on`'s `work-on.md` per repo, on that repo's own branch (the same per-issue
   delegation contract the single-pr path uses, minus the shared branch — each repo's
   work lands as its own PR). Cross-unit carry-forward flows through the coordination
   PR's durable state, not a shared branch.
4. **Resolve gate nodes before dependents advance.** A non-PR gate node (e.g. a
   package publish) is satisfied only when its condition verifies **live** at
   recompute time. An unsatisfiable or unverifiable gate fails closed and blocks
   every node ordered after it — do not advance its dependents.
5. **Re-gate.** Run `shirabe validate --merge-gate` (live status, never the editable
   body text) to recompute merge state. Under `--mode=draft` an unmerged-indexed-PR
   state is a tolerable notice mid-effort; the gate is the only authority on live
   merge state.

### Step 3 — Done-signal (merge last, fail-closed)

The single done-signal is the **coordination PR merging last**. It is gated on
`shirabe validate --merge-gate --mode=ready`: the gate recomputes from authoritative
`gh` queries at gate time, and **fails closed** — any PR it cannot resolve is treated
as not-merged, and a `gh` failure halts rather than falsely signaling done. Only once
every indexed per-repo PR has merged, every gate node is satisfied, and finalization
is complete (each repo finalizes its own artifacts repo-locally; the cross-repo
boundary is a read-only verification gate, never a cross-repo write) does the gate
pass under `--mode=ready` and the coordination PR merge. There is no separate "effort
complete" marker — the merged coordination PR is it.

### Abandonment (R20)

When a coordinated effort is abandoned mid-flight — the loop reaches a genuine
blocker and the operator elects to abandon rather than resolve — close the
coordination PR **unmerged** with `gh pr close` (the same `gh` surface used to author
the body) and document the partial state, rather than leaving it open and
merge-eligible. The coordination PR is the durable home of the chain, so abandoning
the chain closes that home. The lifecycle this short-cuts is the canonical contract
in `coordination-strategy.md` (R20).

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

Single-agent parent in this slice — no team is spawned at the `/execute` layer. In
single-pr, the per-issue children are koto-materialized `/work-on` single-issue
workflows on the shared branch (the same dispatch `/work-on`'s plan-orchestrator uses
today). In coordinated, each unblocked PR node dispatches a `/work-on` single-issue
run per repo on that repo's own branch, driven by the plain durable-state loop rather
than a koto session. The full parent-skill conformance binding (state schema, resume ladder, three exit
paths, metadata-only inspection, security surfaces) is Issue 6.

## Reference Files

| File | When |
|------|------|
| `skills/execute/koto-templates/work-on-plan.md` | the lifted `execute-plan` orchestrator template |
| `skills/execute/scripts/preflight.sh` | Step 1 cross-skill preflight |
| `skills/execute/scripts/run-cascade.sh` | `plan_completion` atomic finalization cascade (carries the `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch) |
| `references/coordination-strategy.md` | the canonical coordinated contract the coordinated path binds to (lifecycle, merge-order DAG, done-signal, F1/F2/F4, R20/R21) |
| `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` | the single-issue engine each child delegates to |
