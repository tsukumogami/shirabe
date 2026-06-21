---
schema: prd/v1
status: Done
problem: |
  shirabe's /execute skill is the newest link in the /explore → /scope → /execute
  chain, and its first real end-to-end use exposed that it cannot reliably finish
  what it starts. It cannot land into a developer's existing branch/PR, it produces
  a non-template-conformant PR even on a clean run, it offers no pause-for-review
  before irreversibly finalizing the chain, it does not guarantee docs coverage
  when a plan adds user-visible surface, and the friction notes a developer keeps
  are erased by the workflow's own cleanup.
goals: |
  Make /execute trustworthy to finish a scoped+planned feature: land into the
  developer's existing PR, optionally pause at a reviewable draft before
  finalization, guarantee documentation coverage for user-visible surface, emit a
  template-conformant PR without manual fix-up, surface incomplete finalization on
  a manual/fallback run, and give report-upstream artifacts a durable home — all
  without changing the existing default behavior.
upstream: docs/briefs/BRIEF-execute-friction.md
motivating_context: |
  The first real dogfood of the shipped /execute skill (the niwa
  niwa-default-worktree feature, taken /explore → /scope → /execute in one sitting)
  surfaced seven friction points; six are real shirabe gaps this PRD specifies.
---

# PRD: execute-friction

## Status

Done

Requirements for closing the friction the first end-to-end `/execute` use
surfaced. Upstream BRIEF: `docs/briefs/BRIEF-execute-friction.md` (Accepted). The
mechanism choices are deferred to the downstream DESIGN and recorded under
Decisions and Trade-offs.

## Problem Statement

A shirabe developer who takes a feature through `/explore → /scope → /execute` in one
sitting expects `/execute` to drive the plan to a finished, reviewable pull
request. The first real end-to-end use — the niwa `niwa-default-worktree` feature —
showed `/execute` cannot hold up that promise, and the gaps affect every developer
who runs the skill, not just one case.

The root break is at the handoff seam. A developer scopes and plans on a branch and
often opens a pull request mid-chain to review an early artifact; when they run
`/execute`, they expect it to continue into that same branch and PR. Instead,
`/execute`'s single-pr path always creates a new `impl/<slug>` branch and a new
draft PR, with no supported way to target the existing one. The developer is forced
into a manual fallback (driving the plan's issues by hand), which bypasses
`/execute`'s automated finalization — so the lifecycle cascade and PR-template
steps silently do not run.

Four further gaps compound it, several independent of the manual fallback: even on
a clean run the assembled PR is not template-conformant (non-conventional title,
no two-part body); there is no way to implement-then-pause before the finalization
cascade irreversibly mutates the artifact chain; nothing guarantees user-facing
documentation is updated when a plan adds user-visible surface; and the friction
notes a developer keeps to report problems upstream are deleted by the workflow's
own cleanup before they can be read. The net effect: a developer cannot trust
`/execute` to finish cleanly, gets no checkpoint to catch what it skipped, and
loses the evidence that would have flagged the skip. The version-skew observation
(a `-dev` plugin-cache directory resolving alongside stable) is excluded — it is
an install/plugin-cache concern outside shirabe and is benign.

## Goals

- A developer can run `/execute` against a plan scoped on an existing branch and
  have the implementation land into that same branch and open PR.
- A developer can have `/execute` implement the whole plan and stop at a reviewable
  draft before the finalization cascade mutates the chain, then resume to finish.
- A plan that adds user-visible surface cannot reach the done-signal with its
  user-facing documentation silently unaddressed.
- The PR `/execute` finalization produces is template-conformant without a manual
  fix-up pass.
- A manual or fallback run that bypasses automated finalization can be told,
  mechanically, that finalization is not yet complete.
- Friction and other report-upstream artifacts survive to a durable home rather
  than being erased by the finalization cleanup and squash-merge.
- None of the above changes `/execute`'s existing default behavior when the new
  capabilities are not invoked.

## User Stories

- As a shirabe developer who scoped and planned a feature on a `docs/<topic>` branch
  with an open PR, I want `/execute` to land the implementation into that same PR,
  so that I am not left with a divergent `impl/<slug>` branch and an orphaned
  second PR to reconcile by hand.
- As a developer who wants to inspect the assembled change before it is final, I
  want `/execute` to implement every issue and then pause at a reviewable draft
  with the artifact chain still intact, so that I can review and only then let it
  finalize.
- As a developer executing a plan that adds user-visible CLI or behavior, I want the
  run to account for user-facing documentation before it finishes, so that the
  docs gap is not discovered only by luck after merge.
- As a developer finishing an `/execute` run, I want the PR to already carry a
  conventional title and the two-part body, so that I do not run a separate
  template fix-up.
- As a developer who had to drive a run manually, I want a mechanical signal that
  finalization is incomplete, so that I do not forget the cascade and template
  steps the automated path would have done.
- As a developer reporting friction upstream, I want my notes to live somewhere the
  workflow cleanup will not erase, so that the record meant to improve the tool
  survives to be read.

## Requirements

### Functional

- **R1 — Mode-aware existing-branch/PR targeting.** `/execute` SHALL target
  branches in an execution-mode-aware way:
  - *single-pr:* `/execute` SHALL land a run into the developer's existing scoping
    branch and its open pull request (the branch on which `/scope` produced the
    PLAN) instead of creating a new `impl/<slug>` branch and a new draft PR; the
    per-issue children SHALL commit to that branch and the run SHALL finalize that
    PR.
  - *coordinated:* `/execute` SHALL NOT land code on the coordination branch/PR.
    The coordination branch carries only scoping-document updates (the PR-Index and
    merge-order). For each repository that needs changes, `/execute` SHALL work it in
    a separate worktree and land that repo's code as its own per-repo PR.
- **R2 — Pause before finalization (interactive mode).** In interactive mode,
  `/execute` SHALL drive every plan issue to a reviewable draft pull request and
  stop BEFORE the finalization cascade runs — with the artifact chain still intact
  (the PLAN not deleted, the upstream BRIEF/PRD/DESIGN not transitioned) — and SHALL
  finalize (run the cascade and complete the landing) on the developer's approval. This
  implement-then-pause behavior is interactive-mode only; under `--auto` no pause is
  offered (see R8).
- **R3 — Documentation-coverage guarantee.** When a plan adds user-visible surface
  (new or changed CLI/behavior a user would read about in a guide), the chain
  SHALL ensure user-facing documentation is accounted for before the run reaches
  its done-signal: either by the planning step emitting a documentation work item,
  or by an explicit documentation-coverage check, such that the gap cannot pass
  silently.
- **R4 — Template-conformant PR.** `/execute`'s finalization SHALL produce a pull
  request whose title follows the conventional-commit convention and whose body
  follows the project's two-part structure, without requiring a separate manual
  template fix-up pass.
- **R5 — Finalization-not-done guard.** A run whose finalization did not complete
  through the automated path (a manual or fallback run) SHALL be detectable
  mechanically — a check, invokable both by a human from the command line and in
  CI, that reports whether the chain's finalization is complete.
- **R6 — Durable report-upstream capture.** Friction logs and other
  report-upstream artifacts SHALL have a durable home that survives `/execute`'s
  finalization cleanup and the squash-merge that keeps `wip/` off the main branch,
  so the artifact reaches its intended upstream reader.

### Non-Functional

- **R7 — Default-behavior preservation.** When the existing-PR targeting (R1) is
  not invoked, `/execute`'s branch/PR behavior SHALL be unchanged: a fresh run still
  creates the `impl/<slug>` branch and draft PR and drives to the merged-PR
  done-signal. The new surfaces are additive, not a replacement.
- **R8 — Autonomy delivers a finished result.** The implement-then-pause behavior
  (R2) is interactive-mode only. Under an authorized autonomous (`--auto`) run,
  `/execute` SHALL NOT pause for review: it drives through finalization to a pull
  request that is ready to merge and green, with the artifact chain already
  transitioned to its final state (PLAN deleted, BRIEF/PRD → Done, DESIGN →
  Current). A developer who runs `--auto` expects a finished, mergeable result —
  consistent with the autonomy mandate that an authorized autonomous run does not
  stop short of completion. The pause is never offered in `--auto`.

## Acceptance Criteria

- [ ] Running `/execute` against a single-pr plan on a branch that already has an
      open PR lands the implementation commits on that branch and finalizes that
      PR — no new `impl/<slug>` branch and no second draft PR are created.
- [ ] Running `/execute` against a coordinated plan does NOT land code on the
      coordination branch: the coordination branch receives only scoping-document
      updates, and each repository that needs changes is worked in its own worktree
      and lands as its own per-repo PR.
- [ ] Running `/execute` with no existing-PR context (single-pr) still creates the
      `impl/<slug>` branch and draft PR and drives to the done-signal (R7 parity).
- [ ] In interactive mode, after all issues are implemented the run stops with a
      draft PR open AND the PLAN file still present and the upstream BRIEF/PRD/
      DESIGN still at their pre-finalization statuses.
- [ ] On the developer's approval, the paused interactive run executes the
      finalization cascade (PLAN deleted, upstream transitioned) and completes the
      landing.
- [ ] A plan whose DESIGN/PRD indicates user-visible surface yields either a
      documentation work item or a documentation-coverage check result before the
      run can reach its done-signal; a plan with no user-visible surface does not.
- [ ] The PR produced by `/execute` finalization has a conventional-commit title
      and a two-part body with no manual fix-up applied.
- [ ] A run whose finalization did not complete is reported as incomplete by a
      check that a human can run from the CLI and that CI can run; a fully
      finalized run reports complete.
- [ ] A friction/report-upstream artifact produced during a run is retrievable
      from a durable location after finalization cleanup and after the PR's
      squash-merge.
- [ ] Under `--auto`, the run drives to a finished result with no pause: the PR is
      marked ready to merge and CI is green, and the artifact chain is transitioned
      to its final state (PLAN deleted, BRIEF/PRD → Done, DESIGN → Current). The
      pause is never offered in `--auto` (R8).
- [ ] In interactive mode, the run pauses at the reviewable draft before the
      finalization cascade and only finalizes on the developer's approval (R2).

## Out of Scope

- **Version skew (F2).** The newly shipped skill resolving under a `-dev`
  plugin-cache directory alongside the prior stable version is an
  install/marketplace + plugin-cache resolution concern owned outside shirabe, and
  is benign (the dev build is a forward-compatible superset). Not specified here.
- **The coordinated path's finalization/merge-gate contract, and the multi-PR
  path.** Branch/PR targeting (R1) is specified mode-aware for both single-pr and
  coordinated, but the coordinated path's done-signal, merge-order DAG, and
  merge-gate are unchanged from their existing contract — only its branch-targeting
  rule (code in per-repo worktrees, coordination branch for scoping docs only) is
  stated here. The multi-pr path (one issue at a time against a repo-persisted PLAN)
  is not reshaped. The R2 pause, R4 template PR, R5 guard, and R6 capture are
  specified for the single-pr path the dogfood exercised.
- **Reimplementing the per-issue execution engine.** `/execute` delegates each
  issue to `/work-on`; this PRD governs the orchestration and finalization seam,
  not the single-issue engine.
- **The chosen mechanisms.** Which user surface exposes R1's targeting, the exact
  shape of the R2 pause, the R3 detection signal and owning layer, the R5 guard's
  form, and the R6 durable-capture home are HOW decisions owned by the downstream
  DESIGN — see Decisions and Trade-offs for the constraints this PRD places on
  them.

## Decisions and Trade-offs

These resolve the upstream BRIEF's Open Questions at requirements altitude: each
records what this PRD settles versus what it deliberately constrains-but-defers to
the DESIGN.

- **D1 — Existing-PR targeting is required; the surface is deferred.** R1 settles
  that the capability must exist. The DESIGN chooses the surface among the options
  the exploration surfaced (a flag, auto-detecting "the current branch has an open
  PR," generalizing the existing `status: override` reuse predicate beyond
  `impl/<slug>`, or formalizing a `/scope → /execute` handoff). Constraint: the
  chosen surface MUST preserve R7 default behavior, and MUST resolve whether a
  `/scope` `docs/<topic>` PR is adopted as the home PR or kept distinct. The
  exploration found the override substrate already exists and the gap is a
  hardcoded `SHARED_BRANCH` — a small mechanical core — so the DESIGN is expected
  to favor the lowest-ceremony surface that satisfies R1 and R7.
- **D2 — Pause is required; its shape is deferred.** R2 settles that an
  implement-then-pause capability must exist with the chain intact at the stop.
  The DESIGN chooses among a mode/flag that stops after PR assembly but before the
  cascade, a new pause state, or a reframing of the existing stop-at-ready
  behavior. Constraint: the pause MUST leave the chain un-mutated (PLAN present,
  upstream not transitioned) and MUST compose with the DRAFT-before-READY cascade
  discipline and R8 autonomy rule. The exploration found `/execute` already stops
  at `gh pr ready` and never auto-merges, so the DESIGN's real work is the
  pre-cascade pause seam, not a "don't merge" mode.
- **D3 — Docs coverage is required; owner/signal deferred (leaning `/plan`).** R3
  settles the guarantee. The exploration found `/plan` is the only layer that
  reads the DESIGN body where the user-visible-surface signal lives, and that a
  content-completeness check inside `/execute` would violate its metadata-only
  inspection contract — so the owning layer leans to `/plan`. The DESIGN settles
  the owner and the detection signal (a prose reference to a `docs/guides/*` path,
  named CLI flags, or a structured frontmatter flag).
- **D4 — Finalization guard is required; home deferred (leaning `shirabe
  validate`).** R5 settles the guard must exist and be invokable from CLI and CI.
  The exploration found the only existing guard (R9 hard-finalization) rides the
  `/execute` exit and cannot fire when koto is bypassed, and pointed at a new
  `shirabe validate` mode as the home, consistent with the "check with `validate`"
  half of shirabe's CLI split. The DESIGN confirms the home and shape.
- **D5 — Durable capture is required; home deferred.** R6 settles that
  report-upstream artifacts need a durable home. The exploration reframed F7 as a
  convention gap (the cascade has no `wip/` scrub; squash-merge removes `wip/` as
  designed) and identified a GitHub issue on the skill repo as the lowest-ceremony
  durable home, with a `docs/` note as fallback and an automated `/execute`
  run-report emit as a design-gated follow-on (it would widen `/execute`'s closed
  write-target set). The DESIGN/convention settles which.

## Known Limitations

- The single-PR focus means a later, separate effort is needed if the same
  finalization gaps prove to affect the coordinated multi-repo path.
- R6's durable-capture home, if realized as a manual convention rather than an
  automated emit, depends on developer discipline; the automated-emit alternative is
  heavier (it touches `/execute`'s security-bounded write-target set) and is left
  to the DESIGN to weigh.
