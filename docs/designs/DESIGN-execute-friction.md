---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-execute-friction.md
user_visible_surface: true
problem: |
  /execute's single-pr orchestrator hardwires a new impl/<slug> branch and draft
  PR, produces a non-template PR body, couples its only review-gate to readiness,
  has no docs-coverage step, and offers no manual-fallback finalization guard;
  report-upstream artifacts placed in wip/ are removed by squash-merge.
decision: |
  Six contained changes across /execute, /plan, and shirabe validate usage: capture
  the settled branch into SHARED_BRANCH and adopt a scoped branch/PR as the home PR;
  add a --pause-for-review flag routing to a new paused_for_review suspension before
  the cascade; have /plan emit a docs work item from a user_visible_surface signal;
  fold PR-template authoring into pr_finalization; reuse validate --lifecycle-chain
  --mode=ready as the finalization guard; and record a report-upstream durability
  convention.
rationale: |
  Most machinery already exists (the override substrate, stop-at-ready, /plan docs
  routing, the lifecycle-chain validate mode), so the work is wiring and small
  additions, not new subsystems. Each change is minimal, preserves the existing
  default path (R7), and respects /execute's metadata-only inspection and closed
  write-target contracts.
---

# DESIGN: execute-friction

## Status

Proposed

## Context and Problem Statement

`/execute`'s single-pr path is driven by the koto orchestrator template
`skills/execute/koto-templates/execute.md`, whose states (`orchestrator_setup`,
`spawn_and_await`, `pr_finalization`, `plan_completion`) carry the finalization
behavior. The first end-to-end use exposed five mechanism gaps and one convention
gap that the accepted PRD (`docs/prds/PRD-execute-friction.md`) requires closing
(R1–R6, with R7 parity and R8 autonomy as constraints). The technical problem is
to close them with the smallest changes that preserve the existing default path
and respect `/execute`'s metadata-only inspection (R14/R15) and closed
write-target contracts.

The concrete technical surfaces:

- **Branch/PR targeting (R1).** `orchestrator_setup` already accepts
  `status: override` for any non-main branch with an open PR, and finalization/CI
  already target `HEAD`. But `spawn_and_await` hardcodes
  `SHARED_BRANCH="impl/$PLAN_SLUG"` (two `jq --arg b` ticks), so even a successful
  override routes per-issue children to a divergent branch.
- **Pause before finalization (R2).** The template already terminates at
  `gh pr ready` and never auto-merges; #117's DRAFT-before-READY reorder moved both
  the cascade and `gh pr ready` into `plan_completion`, leaving `pr_finalization` as
  body-assembly-only. The missing capability is a stop at that exact boundary —
  after body assembly, before `plan_completion`.
- **Docs coverage (R3).** `/plan` is the only layer that reads the DESIGN body
  where the user-visible-surface signal lives, and it already routes `Type: docs`
  work items; it just never emits one. A content check inside `/execute` would
  violate its metadata-only contract.
- **Template-conformant PR (R4).** `pr_finalization` runs only `gh pr edit --body`
  with a child-outcome table and never sets the title, which stays the
  non-conventional `impl: <slug>` from PR creation; the two-part body is absent even
  on a clean run.
- **Finalization guard (R5).** No guard fires when koto is bypassed (the only one,
  R9, rides the `/execute` exit). The cascade already self-verifies finalized
  posture with `shirabe validate --lifecycle-chain … --mode=ready`.
- **Durable report-upstream capture (R6).** `run-cascade.sh` does no `wip/` scrub;
  squash-merge removes `wip/` as designed. This is a convention gap, not a write.

## Decision Drivers

- **Preserve the default path (PRD R7).** Every change is additive; a fresh run
  with no existing-PR context and no pause request behaves exactly as today.
- **Respect `/execute`'s contracts.** Metadata-only child inspection (R14/R15) and
  the closed write-target set bound what `/execute` may do.
- **Lowest ceremony.** Most machinery exists; prefer wiring and small additions
  over new subsystems.
- **Author-with-skills / check-with-validate.** New authoring belongs in skills;
  new correctness checks reuse `shirabe validate`, never a renderer subcommand.
- **Autonomy compatibility (PRD R8).** The pause is a solicited stop, orthogonal to
  `--auto`.
- **DRAFT-before-READY discipline.** The pause and cascade compose with the rule
  that the cascade runs before `gh pr ready`.

## Considered Options

### D1 — Existing branch/PR targeting

- **(a) Generalize the existing override + capture the settled branch into
  `SHARED_BRANCH`, adopting a `/scope` `docs/<topic>` PR as the home PR (chosen).**
  Reuses the override substrate that already exists; the only code change is
  replacing the hardcoded `impl/$PLAN_SLUG` with the recorded settled branch.
- (b) Add an explicit `--branch`/`--pr` flag. Rejected: redundant ceremony plus a
  new validation/input surface, when auto-detect already has the signal.
- (c) Keep a distinct `/scope` PR and link it rather than adopt. Rejected: leaves
  the orphaned-second-PR friction the PRD names.

### D2 — Pause before finalization

- **(a) A `--pause-for-review` flag → `PAUSE_BEFORE_FINALIZE` template var that
  splits `pr_finalization`'s outgoing edge to a new `paused_for_review` terminal
  (chosen).** Stops at the body-assembly/cascade boundary #117 already created.
- (b) A mid-machine pause STATE with a human-wait. Rejected: koto has no human-wait
  primitive; a terminal is the correct encoding of a resumable stop.
- (c) Reframe the existing stop-at-ready as the pause. Rejected: by `done` the
  cascade has already run, so it stops at the wrong place.

### D3 — Docs-coverage owner and signal

- **(a) Owner `/plan`; signal a structured `user_visible_surface` flag plus a
  `docs/guides/*` prose fallback (chosen).** `/plan` is the only layer that reads
  the DESIGN body and emits issues; the structured flag is deterministic where
  prose-grepping alone is brittle.
- (b) A docs-coverage check inside `/execute`. Rejected: a content read that
  violates `/execute`'s metadata-only inspection contract (R14/R15).
- (c) Pure prose-grep of the DESIGN for guide references. Rejected as the sole
  signal: false positives in rejected-option prose, false negatives when no literal
  path is written; kept only as a fallback.

### D4 — Finalization-not-done guard

- **(a) Reuse `shirabe validate --lifecycle-chain <seed> --mode=ready` (chosen).**
  The cascade already self-verifies with this exact probe; under ready posture a
  present PLAN or un-transitioned upstream fails `L01`. No new flag, no subcommand.
- (b) A new dedicated validate mode (`--finalization-complete`). Rejected: the
  existing mode already expresses the check; a new flag duplicates it.
- (c) A renderer/status subcommand. Rejected by the CLAUDE.md CLI-Surface contract
  (the removed `shirabe coordination` subcommand is the cited precedent).

### D5 — Durable report-upstream home

- **(a) File report-upstream artifacts as a GitHub issue on the shirabe repo, with
  a committed `docs/` note fallback; record the rule as a convention (chosen).**
  Reuses the `gh issue create` pattern `/plan` and `/roadmap` own; zero code.
- (b) An automated `/execute` run-report emit. Deferred: adds a remote write target
  outside `/execute`'s closed write-target set and needs an R9 amendment.

### D6 — Template-conformant PR

- **(a) Fold the PR-template authoring into `pr_finalization` (chosen).** One file;
  the existing `gh pr edit` gains `--title` and a two-part body.
- (b) Invoke the cross-plugin `/fix-pr` from `/execute`. Rejected: a second
  remediation pass (violates R4's "without a separate manual fix-up") and a runtime
  shirabe→tsukumogami coupling.

## Decision Outcome

Six contained changes, each minimal and additive:

1. **D1:** In `execute.md`, persist the settled branch (HEAD) in `orchestrator_setup`
   into a koto context key, and read it in both `spawn_and_await` ticks as
   `SHARED_BRANCH` with a `|| impl/$PLAN_SLUG` fallback. Add one prose rule to
   `skills/execute/SKILL.md` Input Modes / Single-PR: an existing branch with an
   open PR is adopted as the home PR. The recovered branch is re-validated before
   interpolation (it is an input surface).
2. **D2:** Add `--pause-for-review` (alias `--no-finalize`) to `skills/execute/SKILL.md`
   Execution-Mode Flags, threaded as `PAUSE_BEFORE_FINALIZE` into `execute.md`.
   `pr_finalization`'s single edge becomes two guarded edges: the pause case routes
   to a new non-failure terminal `paused_for_review` (chain intact: PLAN present,
   upstream un-transitioned, PR DRAFT). Resume is the existing topic-keyed home-PR
   lookup re-entering `plan_completion` with `PAUSE_BEFORE_FINALIZE=false`. The pause
   is a **suspension**, not a termination: `exit:` stays UNSET with a resumable
   `paused_for_review` marker, so the parent-skill R9 hard-finalization check (which
   fires only at terminal exits) does not trip.
3. **D3:** Add `user_visible_surface` to `skills/design/references/` design-format
   (written by `/design`), optionally mirrored into the PRD format. In
   `skills/plan/references/phases/phase-3-decomposition.md`, add a docs-coverage emit
   step that produces a `Type: docs` work item when the flag is set (or the
   `docs/guides/*` fallback matches), plus a Scope-Gate backstop in
   `skills/review-plan/` so a missing docs item loops back rather than passing
   silently. `/execute` gains no content gate.
4. **D4:** Document and CI-wire `shirabe validate --lifecycle-chain <seed> --mode=ready`
   as the R5 guard. Post-finalization the seed is the durable DESIGN anchor (the PLAN
   is gone); CI runs it gated on `pull_request.draft == false`, matching the existing
   lifecycle CI convention.
5. **D5:** A convention carve-out — report-upstream artifacts go to a GitHub issue on
   the skill repo (never `wip/`), with a `docs/` note fallback — recorded in the
   workspace `CLAUDE.md` wip rule (mirrored verbatim in the dot-niwa-overlay
   fragment) and pointed to from `skills/execute/SKILL.md`.
6. **D6:** In `execute.md` `pr_finalization`, the existing `gh pr edit` gains
   `--title "<type>(scope): <description>"` (default `feat:`, derived from the
   validated PLAN slug, never raw prose) and a two-part body: Part 1 a factual change
   paragraph, `---`, Part 2 the existing child table (plus `Fixes #N` only when the
   children are GitHub issues, not single-pr outlines). `pr-creation/SKILL.md` is the
   canonical template reference. No new koto state, no new write target.

This feature itself adds user-visible surface (the `--pause-for-review` flag and the
adopt-PR behavior), so per D3 this DESIGN carries `user_visible_surface: true` and
`/plan` will emit a docs work item for it — the change dogfoods its own rule.

## Solution Architecture

**Components touched:**

- `skills/execute/koto-templates/execute.md` — D1 (branch capture/inject), D2 (the
  `PAUSE_BEFORE_FINALIZE` edge split + `paused_for_review` terminal), D6 (PR title +
  two-part body in `pr_finalization`).
- `skills/execute/SKILL.md` — D1 adopt-PR prose, D2 flag + suspension-exit
  documentation, D4 guard pointer, D5 durable-capture pointer.
- `skills/plan/` (`references/phases/phase-3-decomposition.md`, format refs) and
  `skills/review-plan/` — D3 docs emit + backstop.
- `skills/design/references/` (and optionally `skills/prd/references/prd-format.md`)
  — D3 `user_visible_surface` frontmatter field.
- Workspace `CLAUDE.md` + dot-niwa-overlay fragment + `skills/execute/SKILL.md` — D5
  convention.
- CI workflow (lifecycle check) — D4 guard wiring (no new binary code; reuses the
  existing validate mode).

**Data flow (single-pr happy path with the new capabilities):**

`orchestrator_setup` records HEAD as the settled branch → `spawn_and_await` injects
it as `SHARED_BRANCH` (children commit there) → `pr_finalization` assembles the
template-conformant PR (title + two-part body) → if `PAUSE_BEFORE_FINALIZE`, route to
`paused_for_review` (stop, chain intact); else `plan_completion` runs the cascade then
`gh pr ready`. Resume of a paused run re-enters `plan_completion`. A manual/fallback
run is checkable any time by `shirabe validate --lifecycle-chain <seed> --mode=ready`.

**Contract preservation:** `/execute` still reads only PR/issue/unit status (R14/R15);
the docs-coverage signal is read by `/plan` (which already reads bodies), never by
`/execute`. No new remote write target is added to `/execute`'s closed set (D5's
automated emit is the deferred item that would have).

## Implementation Approach

The work decomposes into independent, separately-verifiable slices, ordered by
coupling rather than by a forced sequence:

1. **D1 branch capture/inject** (`execute.md`, SKILL prose) — smallest, unblocks the
   adopt-PR journey; verify R7 parity (fresh run still lands `impl/<slug>`).
2. **D6 template PR** (`execute.md` `pr_finalization`) — independent of D1; verify a
   clean run yields a conventional title + two-part body.
3. **D2 pause** (`execute.md` edge split + terminal, SKILL flag) — depends on D6's
   `pr_finalization` shape being settled; verify chain-intact at pause and resume.
4. **D3 docs coverage** (`skills/plan`, `skills/design` format, `review-plan`) —
   independent of the `/execute` slices; verify emit-on-flag and no-emit-when-absent.
5. **D4 guard** (docs + CI wiring) — independent; verify incomplete-vs-complete with
   the correct seed doc.
6. **D5 convention** (prose only) — independent; no code.

Each slice is a self-contained, observable unit consistent with single-pr execution.

## Security Considerations

<!-- Phase 5 fills this in. -->

## Consequences

<!-- Phase 5/6 finalize this. -->
