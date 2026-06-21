---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-execute-friction.md
milestone: "execute-friction"
issue_count: 6
---

# PLAN: execute-friction

## Status

Active

## Scope Summary

Decomposes `DESIGN-execute-friction` into six single-pr issues that close the six
in-scope `/execute` friction gaps (F1/F3/F4/F5/F6/F7) — all in the shirabe repo,
landing as one PR.

## Decomposition Strategy

**Horizontal.** The design is six loosely-coupled skill/template/doc edits with
clear boundaries and minimal runtime interaction, so each issue builds one slice to
completion. Not a walking skeleton: there is no integration-risk end-to-end path to
exercise early — the slices are independent skill changes. One coupling edge exists
(the pause in Issue 3 depends on the `pr_finalization` shape settled in Issue 2),
and Issue 6 documents the behaviors the earlier issues add.

## Issue Outlines

### Issue 1: feat(execute): mode-aware branch/PR targeting

**Goal**: Make `/execute` branch targeting mode-aware — single-pr adopts the
scoping branch/PR by capturing the settled branch into `SHARED_BRANCH`; coordinated
keeps code in per-repo worktrees and reserves the coordination branch for
scoping-document updates only.

**Acceptance Criteria**:
- [ ] `orchestrator_setup` records the settled branch (HEAD) into a koto context
      key; both `spawn_and_await` ticks read it as `SHARED_BRANCH` with a
      `|| impl/$PLAN_SLUG` fallback (replacing the hardcoded value).
- [ ] R7 parity: a fresh single-pr run with no existing-PR context still lands on
      `impl/<slug>` (byte-identical injection).
- [ ] The recovered branch is re-validated before interpolation into emitted shell.
- [ ] `skills/execute/SKILL.md` Single-PR path states the adopt-the-scoping-PR rule;
      the Coordinated path states code-in-per-repo-worktrees / coordination-branch-
      docs-only.
- [ ] `skills/execute/evals/` updated to cover the adopt and parity cases.

**Dependencies**: None

**Type**: docs
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/SKILL.md`, `skills/execute/evals/evals.json`

### Issue 2: feat(execute): template-conformant PR in pr_finalization

**Goal**: Fold the PR-template authoring into `pr_finalization` so the PR carries a
conventional-commit title and the project's two-part body without a separate fix-up.

**Acceptance Criteria**:
- [ ] `pr_finalization`'s `gh pr edit` emits `--title "<type>(scope): <desc>"`
      (default `feat:`, derived from the validated PLAN slug, never raw prose).
- [ ] The body is two-part: Part 1 a factual change paragraph, `---`, Part 2 the
      child-outcome table (plus `Fixes #N` only when children are GitHub issues).
- [ ] The body is posted via `--body-file`/stdin, not `-m` interpolation.
- [ ] `pr-creation/SKILL.md` is referenced as the canonical template.
- [ ] `skills/execute/evals/` updated to assert title + two-part body shape.

**Dependencies**: None

**Type**: docs
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/evals/evals.json`

### Issue 3: feat(execute): interactive pause before finalization; --auto finalizes

**Goal**: Make interactive mode stop at a reviewable draft before the finalization
cascade and finalize on approval, while `--auto` drives straight through to a
ready-to-merge, green PR with the chain transitioned.

**Acceptance Criteria**:
- [ ] Execution-mode resolution drives `PAUSE_BEFORE_FINALIZE` (interactive true,
      `--auto` false); `pr_finalization`'s edge splits to a new non-failure
      `paused_for_review` terminal when set, else routes to `plan_completion`.
- [ ] At the pause the chain is intact: PLAN present, BRIEF/PRD/DESIGN
      un-transitioned, PR DRAFT.
- [ ] Resume re-enters `plan_completion` via the existing topic-keyed home-PR
      lookup; the pause is a suspension (`exit:` UNSET) so R9 does not trip.
- [ ] Under `--auto` no pause fires; the run reaches the finalized, mergeable result.
- [ ] `skills/execute/SKILL.md` documents the mode-driven pause + suspension exit;
      `skills/execute/evals/` cover pause-intact and `--auto`-finalizes.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/SKILL.md`, `skills/execute/evals/evals.json`

### Issue 4: feat(plan): docs-coverage guarantee for user-visible surface

**Goal**: Have `/plan` emit a documentation work item when a plan adds user-visible
surface, driven by a structured `user_visible_surface` signal with a `docs/guides/*`
prose fallback, with a `review-plan` backstop.

**Acceptance Criteria**:
- [ ] `user_visible_surface` added to the design-format spec (written by `/design`),
      optionally mirrored into the PRD format.
- [ ] `/plan` Phase 3 decomposition emits a `Type: docs` work item when the flag is
      set or the `docs/guides/*` fallback matches; no emit when neither holds.
- [ ] A `review-plan` Scope-Gate backstop flags a missing docs item rather than
      passing silently.
- [ ] `/execute` gains no content gate (its metadata-only contract is untouched).
- [ ] Evals updated for `plan`, `design` (format), and `review-plan`.

**Dependencies**: None

**Type**: docs
**Files**: `skills/plan/references/phases/phase-3-decomposition.md`, `skills/design/references/lifecycle.md`, `skills/review-plan/SKILL.md`, `skills/plan/evals/evals.json`

### Issue 5: feat(execute): finalization-not-done guard via validate

**Goal**: Document and CI-wire `shirabe validate --lifecycle-chain <seed> --mode=ready`
as the R5 guard that reports whether a run's finalization is complete, invokable from
the CLI and CI.

**Acceptance Criteria**:
- [ ] `skills/execute/SKILL.md` documents the guard: invocation, the 0/1/2
      exit-code contract, and the seed-doc rule (seed the durable DESIGN anchor
      post-finalization, never the deleted PLAN path).
- [ ] CI runs the guard gated on `pull_request.draft == false`, matching the
      existing lifecycle CI convention.
- [ ] A manual run with an un-finalized chain reports incomplete (exit 2); a
      finalized chain reports complete (exit 0).
- [ ] Evals/docs updated.

**Dependencies**: None

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `.github/workflows/validate-docs.yml`, `skills/execute/evals/evals.json`

### Issue 6: docs(execute): report-upstream convention + user-facing behavior docs

**Goal**: Record the report-upstream durability convention (artifacts → a GitHub
issue on the skill repo or a `docs/` note, never `wip/`) and document the new
user-visible `/execute` behaviors — the docs item this feature's own
`user_visible_surface: true` requires (the D3 dogfood).

**Acceptance Criteria**:
- [ ] `skills/execute/SKILL.md` carries the durable-capture convention pointer;
      the cross-repo workspace `CLAUDE.md` + dot-niwa-overlay mirror are noted as
      out-of-repo follow-up (not landable in the shirabe PR).
- [ ] Developer-facing documentation covers the mode-aware targeting (Issue 1), the
      interactive-pause-vs-`--auto`-finalizes behavior (Issue 3), and the
      finalization guard usage (Issue 5).
- [ ] `skills/execute/evals/` (or the relevant docs eval) updated.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:3>>, <<ISSUE:5>>

> Documents the developer-invoked behaviors of Issues 1, 3, and 5. Issue 2
> (template-PR) is a PR-quality improvement, not a developer-invoked behavior, so it
> is not a blocker. Issue 4 builds the auto-emit machinery for docs items; this
> issue is its manually-emitted dogfood output, so it does not depend on Issue 4.

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `docs/guides/execute-friction.md`

## Dependency Graph

## Implementation Sequence

- **Parallelizable first wave:** Issues 1, 2, 4, 5 are independent and can be
  implemented in any order (or concurrently — they touch overlapping files only via
  the star-topology `Files` ownership, which serializes shared-file writes).
- **Critical path:** Issue 2 (`pr_finalization` shape) → Issue 3 (pause splits that
  state's edge) → Issue 6 (documents the resulting behavior).
- **Last:** Issue 6 documents the developer-invoked behaviors Issues 1, 3, and 5
  add, so it lands after them.

**Cross-cutting AC (every issue):** each issue touches a shirabe skill, so per the
Skill-Evals rule its evals must not only be updated but **run green** via a
`/skill-creator` agent (`scripts/run-evals.sh <skill>`) before the issue's
acceptance is met — the CI existence check is not a substitute for running them.
