# Explore Scope: execute-friction

## Visibility

Public

## Topic

Identify all the work needed to address the friction reported against the new
`/execute` skill during real-world dogfooding on the niwa repo (single-PR plan
execution into an existing branch/PR, `--auto` mode).

Source friction log: reconstructed at a durable path after the in-repo `wip/`
copy was lost to finalization cleanup + squash-merge. Seven friction points
(F1–F7) plus one already-fixed niwa-side bug (R6 gap, out of shirabe scope).

## Friction Inventory (from the log)

- **F1** — single-pr `orchestrator_setup` hardwires a NEW `impl/<slug>` branch +
  new draft PR; no way to target an EXISTING branch/PR. Root cause of F5/F6.
- **F2** — version skew within one chain: `/execute` ran under `0.12.1-dev`
  while sibling skills ran under `0.11.0`. (Likely environment/install, not a
  skill bug — confirm.)
- **F3** — no "implement, pause for review before merge" mode. Done-signal is
  the home PR MERGING; DRAFT→READY cascade is coupled to readiness/merge.
- **F4** — no doc-completeness guarantee. Feature added user-visible CLI surface
  + DESIGN referenced a guide, yet no docs issue/update happened. Gap fell
  through `/plan` (no docs issue) and `/execute` (no docs-coverage check).
- **F5** — finalization cascade not auto-invoked when run fell back to manual
  (consequence of F1). Manual/fallback path should still surface "finalization
  not done."
- **F6** — `/fix-pr` template step skipped (same root cause as F5).
- **F7** — wip-cleanup destroys the friction log itself; squash-merge keeps
  `wip/` off main. The artifact meant for upstream reporting is destroyed by the
  workflow's own cleanup.

## Core Question

What is the complete set of work needed to close the seven friction points
(F1–F7) reported against the new `/execute` skill, and for each: is it a direct
fix, or does it carry design decisions that need settling first? The friction
clusters around three themes — (a) `/execute` can't land into an existing
branch/PR produced by `/scope`, which cascades into skipped finalization, (b) no
"implement, pause for review" mode and no doc-completeness guarantee, and (c)
friction-log durability and version hygiene.

## Context

- `/execute` shipped in shirabe v0.12.0. The friction is from the FIRST real
  external dogfood: niwa's `niwa-default-worktree` feature, taken
  `/explore → /scope → /execute --auto` in one sitting.
- `/explore` and `/scope` ran cleanly; the friction is almost entirely in
  `/execute`, rooted in F1 (can't honor "implement into my existing branch/PR").
- Grounding done: `skills/execute/SKILL.md`, `orchestrator_setup` /
  `plan_completion` / `pr_finalization` states, the metadata-only inspection
  model, and the `--auto` autonomy mandate are all read.
- Key seam: the canonical flow is now `/scope` (produces PLAN on a `docs/<topic>`
  branch, often with an open PR from mid-chain review) → `/execute`. F1 is that
  `/execute`'s single-pr `orchestrator_setup` only reuses a branch named
  `impl/<slug>` with an open PR; a `docs/<topic>` branch + PR is not recognized.

## In Scope

- Fixes/design for F1–F7 in shirabe (`/execute`, and `/plan` for the F4 half).
- The `/scope → /execute` branch/PR handoff seam.

## Out of Scope

- The R6 niwa-code gap (already fixed in niwa PR #167; not shirabe).
- Re-litigating the parent-skill pattern or coordinated-execution model.

## Research Leads

1. **How should `/execute` land into an existing branch/PR (esp. a `/scope`
   `docs/<topic>` branch with an open PR) instead of always creating
   `impl/<slug>` + a new draft PR?** (lead-branch-pr-targeting)
   F1 is the root cause of F5/F6. `/work-on`'s plan-orchestrator already has a
   "Branch Context Evaluation" + `status: override` path — investigate exactly
   what it recognizes today (only `impl/<slug>` + open PR?), what the cleanest
   extension is (a `--branch`/`--pr` flag, auto-detect "current branch has an open
   PR", or generalizing the override predicate), and how `SHARED_BRANCH` injection
   and `plan-to-tasks.sh` behave when the branch isn't `impl/<slug>`.

2. **How should `/execute` support "implement, pause for review before
   finalization/merge"?** (lead-review-gate-mode)
   F3: the done-signal is the home PR merging and the DRAFT→READY cascade is
   coupled to readiness. Investigate where a first-class "stop before
   `plan_completion`, present for review, resume to finalize" boundary would sit
   in the phase spine, how it interacts with DRAFT-before-READY, and whether it's
   a new flag/mode or a new exit/pause state. Does full-run actually auto-merge,
   or stop at ready? Confirm against the `execute.md` template states.

3. **Where should the doc-completeness guarantee live — `/plan` emitting a docs
   issue, `/execute` running a docs-coverage check before the done-signal, or
   both?** (lead-doc-completeness)
   F4: the feature added user-visible CLI surface and the DESIGN referenced a
   guide, yet no docs work happened — `/plan` emitted no docs issue and `/execute`
   has no doc step. Investigate what signal detects "user-visible CLI/behavior
   change," which layer is the right owner, and what `/plan` and `/execute`
   currently do (or don't) about docs.

4. **Does `/execute`'s `pr_finalization` produce a template-conformant PR
   (conventional title + two-part body), and should the `/fix-pr` template step be
   folded in so it isn't a manual afterthought?** (lead-pr-template-finalization)
   F6: the PR-template application had to be prompted manually. Investigate what
   `pr_finalization` assembles today, what `/fix-pr` does, and whether
   `/execute`'s finalization should guarantee a template-conformant PR. Also F5's
   secondary ask: should a manual/fallback path surface "finalization not done"?

5. **How should friction logs (and other report-upstream artifacts) survive
   `/execute`'s wip-cleanup + squash-merge?** (lead-friction-durability)
   F7: the friction log lived in `wip/`, which finalization deletes and
   squash-merge keeps off main — the artifact meant for upstream reporting was
   destroyed by the workflow's own cleanup. Investigate durable-location
   conventions (a `docs/` note, a GitHub issue on the skill repo, run output), and
   whether this is a `/execute` cleanup change or a workspace convention.

6. **Is shipping a dev build (`0.12.1-dev`) alongside stable (`0.11.0`) in the
   same plugin cache intended, and is the version-skew-within-one-chain a shirabe
   release/versioning concern or a niwa/install concern?** (lead-version-skew)
   F2: `/execute` resolved under `0.12.1-dev` while sibling skills ran under
   `0.11.0`. Triage whether this is a shirabe-side issue (release/plugin
   versioning) or an install/marketplace artifact outside shirabe, and what (if
   anything) shirabe should change.
