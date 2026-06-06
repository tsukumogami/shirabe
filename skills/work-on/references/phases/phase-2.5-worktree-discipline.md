# Phase 2.5: Worktree Discipline Check (Plan-Orchestrator Only)

Detect upstream main movement before dispatching the next child workflow and
classify whether the movement invalidates the PLAN's intent. This phase runs
inside the `worktree_discipline_check` koto state defined in
`skills/work-on/koto-templates/work-on-plan.md`.

## When This Phase Runs

This phase runs once between `orchestrator_setup` and `spawn_and_await` in
plan-orchestrator mode (`/work-on <PLAN-*.md>` against a `schema: plan/v1` doc).
Single-issue `work-on.md` invocations do NOT execute this phase.

## Goal

Catch upstream drift mid-chain rather than at PR finalization. When main has
advanced under a long-running PR's shared branch, the PLAN's foundation may have
shifted in ways the operator needs to act on before the next child commits.
Detecting this between children — at the point recovery is cheapest — is the
contract this phase delivers.

## Steps

### 2.5.1 Fetch Origin and Rebase

```bash
git fetch origin
git rebase origin/main
```

If the rebase fails with conflicts, resolve them before classifying. The
conflict-resolution mechanics belong to git, not to this phase; the
classification below is about intent, not mechanics.

### 2.5.2 Classify Upstream Impact

Read `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` for the full
classification rule. The three classes are:

- **None** — main has not advanced, or advanced in directories the PLAN does
  not touch.
- **Informational** — main has advanced and the changes touch directories the
  PLAN cares about, but the changes do NOT invalidate the PLAN's intent
  (e.g., docs-only edits, unrelated test additions, formatting passes).
- **Intent-changing** — main has advanced in ways that invalidate the PLAN's
  intent: the design's referenced files were deleted, the contract the PLAN
  relies on was changed, the substrate the PLAN edits was restructured.

The classification is about whether the PLAN's foundation still holds, not
about whether the rebase was mechanically clean. A clean rebase can silently
land a contract change that breaks the PLAN's references; a mechanical
conflict can be in a file the PLAN doesn't care about.

### 2.5.3 Write Impact Artifact

Write `wip/work-on_${PLAN_SLUG}_impact.json`:

```json
{
  "impact": "none|informational|intent-changing",
  "rationale": "<one-paragraph explanation>",
  "rebase_head": "<commit SHA of new HEAD after rebase>",
  "main_head": "<commit SHA of origin/main at fetch time>"
}
```

The file presence is what the `impact_classified` gate checks; the `impact`
field is what the agent submits as evidence.

### 2.5.4 Submit Evidence

Submit `impact` to the `worktree_discipline_check` state:

```bash
koto next {{SESSION_NAME}} --with-data '{"impact": "none"}'
# or
koto next {{SESSION_NAME}} --with-data '{"impact": "informational", "rationale": "main added unrelated tests in skills/charter/"}'
# or
koto next {{SESSION_NAME}} --with-data '{"impact": "intent-changing", "rationale": "main deleted references/worktree-discipline.md that this PLAN renames to; PLAN must be re-planned against new main"}'
```

`none` and `informational` route forward to `spawn_and_await`. `intent-changing`
routes to `escalate_upstream_drift` → `done_blocked` carrying the rationale as
the actionable failure reason.

## Why This Phase Exists

Without it, `/work-on`'s plan-orchestrator mode could ship a PR whose PLAN
foundation has silently shifted out from under it. The catastrophic failure
mode (SE11 PR-141 in the v0.7.0 friction record) hit when main moved during a
multi-day chain run and the operator only discovered the drift at PR
finalization — at which point recovery costs were maximal. This phase moves
the detection point to the per-child boundary, where recovery is cheapest.

## Quality Checklist

- [ ] `wip/work-on_${PLAN_SLUG}_impact.json` exists and matches the schema
- [ ] `impact` value is one of `none`, `informational`, `intent-changing`
- [ ] `rationale` is populated when `impact` is `intent-changing`
- [ ] Rebase succeeded or conflicts were resolved before classification
