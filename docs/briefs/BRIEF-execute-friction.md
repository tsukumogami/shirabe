---
schema: brief/v1
status: Done
problem: |
  When a developer takes a feature through /explore → /scope → /execute in one
  sitting, /execute can't land into the branch/PR they already opened during
  scoping, forcing a manual fallback that bypasses its own finalization. Even on
  a clean run the PR isn't template-conformant, there's no pause-for-review
  before the chain is irreversibly finalized, docs coverage isn't guaranteed,
  and captured friction notes are erased by the workflow's own cleanup.
outcome: |
  A developer runs /execute against a plan they scoped on an existing branch and
  watches it land into that same PR, optionally pausing at a reviewable draft
  before finalization, with docs coverage ensured, a template-conformant PR, and
  any captured notes preserved durably. The developer trusts /execute to finish what
  it starts and sees clearly when something genuinely needs their hand.
motivating_context: |
  The first real end-to-end dogfood of the newly shipped /execute skill (the niwa
  niwa-default-worktree feature) surfaced seven friction points. Six are real
  shirabe gaps; this brief frames closing them as one coherent feature.
---

# BRIEF: execute-friction

## Status

Done

This brief frames the remediation of friction surfaced by the first real
end-to-end use of the `/execute` skill. The downstream PRD owns the requirements;
the DESIGN owns the mechanism choices. F2 (version skew) is excluded as an
install/plugin-cache concern outside shirabe.

Edited in place after acceptance (developer review during the downstream DESIGN): the
branch-targeting journey and Scope Boundary were made execution-mode-aware
(single-pr adopts the scoping branch; coordinated keeps code in per-repo worktrees
and reserves the coordination branch for scoping docs), and the pause journey was
scoped to interactive mode (`--auto` delivers a finished, mergeable result).

## Problem Statement

The shirabe chain promises that a developer can take a feature from idea to merged
code in one sitting: `/explore` to find the shape, `/scope` to settle
BRIEF→PRD→DESIGN→PLAN, and `/execute` to drive the plan to a finished pull
request. `/execute` is the newest link, and the first time it was used end-to-end
on a real feature, it could not hold up its end of that promise.

The break starts at the handoff seam. A developer who scopes and plans a feature
naturally does so on a branch — and often opens a pull request mid-chain to review
an early artifact. When they then run `/execute`, they expect it to continue into
that same branch and PR. Instead, `/execute` always creates a *new* `impl/<slug>`
branch and a *new* draft PR. The developer who required all the work to land in their
existing PR had no supported way to ask for that, and was forced into a manual
fallback — driving the plan's issues by hand. That fallback bypassed `/execute`'s
own automated finalization, so every step the skill was supposed to handle had to
be done by hand and remembered without help.

The damage compounds from there, and not all of it depends on the manual fallback:

- Even on a clean automated run, the pull request `/execute` assembles is not
  template-conformant — it carries a non-conventional title and a body that lacks
  the project's two-part structure, so a separate manual fix-up is always needed.
- There is no way to ask `/execute` to implement the plan and then *pause* for
  human review before the finalization cascade runs. That cascade irreversibly
  mutates the artifact chain (it deletes the PLAN and transitions the upstream
  documents), so a reviewer cannot see the assembled change while the chain is
  still intact.
- Nothing ensures user-facing documentation is updated when a plan adds
  user-visible surface. A feature can add CLI flags and behavior, the design can
  even name a docs guide, and the whole thing can flow to merge with no doc update
  — the gap falls through every layer and is caught only if a human notices.
- The friction notes the developer keeps to report problems upstream live in a
  location the workflow's own cleanup treats as disposable, so the very record
  meant to improve the tool is destroyed before it can be read.

Each gap is individually small. Together they mean a developer cannot trust
`/execute` to finish what it starts: the skill quietly leaves work undone, offers
no checkpoint to catch it, and erases the evidence that would have flagged it.

## User Outcome

A developer who has scoped and planned a feature can run `/execute` and watch the
implementation land into the pull request they already have open — no divergent
branch, no orphaned second PR, no manual reconstruction of work the skill should
drive. The continue-into-my-existing-PR path is a first-class, supported way to
run the skill, not an undocumented accident.

When the developer wants to inspect the result before it becomes final, they can have
`/execute` stop at a reviewable draft — the implementation complete, the artifact
chain still intact — review it, and then resume to let `/execute` finish the
finalization. The irreversible step waits for their go-ahead instead of firing the
moment the code is written.

Across both paths, the developer no longer hand-finishes the skill's own work. When
the plan touched user-visible surface, the documentation is covered rather than
silently skipped. The pull request arrives already shaped to the project's
template — conventional title, two-part body — with no fix-up pass. And any
friction or notes the developer captures along the way survive to a durable home
instead of vanishing into cleanup. The net experience: `/execute` finishes what it
starts, and surfaces clearly the rare moments that genuinely need a human hand.

## User Journeys

### Land into the existing scoping work, mode-aware

A shirabe developer runs `/scope` for a feature and opens a pull request mid-chain to
review an early artifact. With the plan ready, they run `/execute`. In a single-pr
plan, the trigger is the `/execute` invocation on the scoping branch that already
has an open PR, and the outcome shape is the implementation committed onto that same
branch and the same PR carried to a finished state — not a new `impl/<slug>` branch
and a second draft PR beside the one they were using. In a coordinated plan, the
coordination branch/PR is the home of the scoping documents only: the outcome shape
is that code never lands on the coordination branch — each repository that needs
changes is worked in its own worktree and lands as its own per-repo PR, while the
coordination branch receives only scoping-document updates.

### Implement, then pause for review before finalizing (interactive mode)

A developer running interactively wants to see the assembled change before it is
locked in. `/execute` implements every issue in the plan and then stops at a
reviewable draft, with the artifact chain still intact (the PLAN not yet deleted,
the upstream docs not yet transitioned). The trigger is an interactive run reaching
the end of implementation; the outcome shape is a reviewable draft pull request the
developer inspects and approves, after which `/execute` runs the finalization cascade
and completes the landing. Under `--auto` there is no pause — the developer expects a
finished, mergeable result.

### A plan that adds user-visible surface reaches merge documented

A developer executes a plan whose feature adds user-visible CLI or behavior — the
kind of change a user reads about in a guide. The trigger is the plan carrying
user-visible surface; the outcome shape is that the run reaches its finished state
only with the user-facing documentation accounted for, rather than the doc update
falling through every layer and being noticed only by luck.

### Finish a run and find it already clean

A developer completes an `/execute` run and turns to the pull request. The trigger
is reaching the end of the run; the outcome shape is a PR that is already
template-conformant — conventional title, two-part body — needing no manual
fix-up, and any friction notes they captured during the run still present in a
durable location rather than erased by the finalization cleanup.

## Scope Boundary

**IN:**

- The `/execute` handoff seam, mode-aware: in single-pr, landing a run into an
  developer's existing scoping branch/pull request rather than always creating a new
  `impl/<slug>` branch and draft PR; in coordinated, keeping code off the
  coordination branch entirely (per-repo worktrees, each landing its own PR) and
  reserving the coordination branch for scoping-document updates (the friction's
  F1, and the F5 consequence where the manual fallback it forced bypassed automated
  finalization).
- A pause-for-review capability: implement the plan, then stop at a reviewable
  draft before the finalization cascade irreversibly mutates the artifact chain,
  with a resume that completes finalization (F3).
- A documentation-coverage guarantee for plans that add user-visible surface,
  owned at whichever chain layer holds the signal (F4 — the signal lives in
  `/plan`, which reads the DESIGN body).
- A template-conformant pull request produced by `/execute`'s own finalization —
  conventional title and two-part body — without a separate manual fix-up (F6),
  and a way for a manual/fallback run to surface that finalization is not yet done
  (the F5b guard).
- A durable home for friction notes and report-upstream artifacts so the
  workflow's own cleanup does not erase them (F7).

**OUT:**

- **Version-skew handling (F2).** The newly shipped skill resolving under a
  `-dev` plugin-cache directory while sibling skills resolved under the prior
  stable version is an install/marketplace + plugin-cache resolution concern owned
  outside shirabe, and is benign (the dev build is a forward-compatible superset).
  This brief does not pursue it.
- **The coordinated path's finalization/merge-gate contract, and the multi-PR
  path.** Branch targeting is framed mode-aware here (single-pr adopts the scoping
  branch; coordinated keeps code in per-repo worktrees and the coordination branch
  for scoping docs only), but the coordinated path's done-signal, merge-order, and
  merge-gate are its existing contract and are not reframed. The multi-pr path
  (one issue at a time) is not reframed. The pause, template-PR, guard, and durable-
  capture concerns are framed against the single-PR path the dogfood exercised.
- **Reimplementing the per-issue execution engine.** `/execute` delegates each
  issue to `/work-on`; this work touches the orchestration and finalization seam,
  not the single-issue engine.
- **The chosen mechanisms.** Which user surface exposes existing-PR targeting,
  the exact shape of the pause state, the docs-detection contract, and where the
  manual-run finalization guard lives are design decisions the PRD and DESIGN
  settle, not framing this brief fixes.

## References

- `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md` — the
  skill and orchestrator template this brief frames remediation for.
- `skills/plan/SKILL.md` — the chain layer that holds the docs-coverage signal
  (F4), since `/plan` reads the DESIGN body.
- The motivating evidence is the friction log from the first end-to-end
  `/execute` dogfood (the niwa `niwa-default-worktree` feature), reported upstream
  to shirabe. The exploration that triaged the seven friction points into this
  scope is captured on this branch as exploration scratch.
