---
schema: design/v1
status: Current
upstream: docs/prds/PRD-execute-friction.md
user_visible_surface: true
problem: |
  /execute's single-pr orchestrator hardwires a new impl/<slug> branch and draft
  PR, produces a non-template PR body, couples its only review-gate to readiness,
  has no docs-coverage step, and offers no manual-fallback finalization guard;
  report-upstream artifacts placed in wip/ are removed by squash-merge.
decision: |
  Six contained changes across /execute, /plan, and shirabe validate usage: make
  branch targeting mode-aware (single-pr adopts the scoping branch/PR; coordinated
  keeps code in per-repo worktrees and reserves the coordination branch for scoping
  docs only); make interactive mode pause at a new paused_for_review terminal before
  the cascade
  while --auto drives to a finished, mergeable result; have /plan emit a docs work
  item from a user_visible_surface signal;
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

Current

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

### D1 — Mode-aware branch/PR targeting

Branch targeting must differ by execution mode: single-pr lands code on the scoping
branch; coordinated keeps code off the coordination branch entirely.

- **(a) Mode-aware targeting — single-pr adopts the scoping branch/PR; coordinated
  uses a per-repo worktree and reserves the coordination branch for scoping-doc
  updates (chosen).**
  - *single-pr:* generalize the existing `status: override` and capture the settled
    branch into `SHARED_BRANCH` (replacing the hardcoded `impl/$PLAN_SLUG`),
    adopting the `/scope` `docs/<topic>` PR as the home PR. Code + scoping docs land
    on the one branch/PR.
  - *coordinated:* the coordination PR/branch is the home of the scoping documents
    (PR-Index, merge-order) ONLY — code never lands there. For each repository that
    needs changes, `/execute` creates a separate worktree and lands that repo's code
    as its own per-repo PR; the coordination branch receives only scoping-doc
    updates. This matches the existing coordinated dispatch (per-repo `/work-on` on
    each repo's own branch) and makes the worktree-per-repo isolation and the
    coordination-branch-is-docs-only rule explicit.
- (b) A single mode-agnostic rule (e.g. always adopt the home PR for code).
  **Rejected (developer directive):** it would land cross-repo code on the
  coordination branch, which must stay scoping-docs-only.
- (c) An explicit `--branch`/`--pr` flag. Rejected: redundant ceremony plus a new
  input surface, when auto-detect already has the signal in single-pr and the
  coordination PR is already located in coordinated.
- (d) Keep a distinct `/scope` PR and link it rather than adopt (single-pr).
  Rejected: leaves the orphaned-second-PR friction the PRD names.

### D2 — Pause before finalization

- **(a) The pause is interactive-mode behavior, not a flag; `--auto` never pauses
  (chosen).** Execution-mode resolution (the existing `interactive` vs `--auto`
  resolution, not a new flag) drives `PAUSE_BEFORE_FINALIZE`. In interactive mode,
  `/execute` stops at the body-assembly/cascade boundary #117 created — a new
  non-failure `paused_for_review` terminal out of `pr_finalization`, chain intact —
  and finalizes on the developer's approval. Under `--auto` it drives straight through
  `plan_completion` to a ready-to-merge, green PR with the chain transitioned to its
  final state. A developer who runs `--auto` expects a finished, mergeable result,
  consistent with the autonomy mandate that an authorized autonomous run does not
  stop short of completion.
- (b) An explicit `--pause-for-review` flag orthogonal to `--auto`. **Rejected
  (developer directive):** the implement-then-pause behavior must be tied to
  interactive mode; `--auto` must deliver a finished, mergeable result and must
  never pause for review.
- (c) A mid-machine pause STATE with a human-wait, or reframing stop-at-ready.
  Rejected: koto has no human-wait primitive (a terminal is the right encoding of a
  resumable stop), and stop-at-ready is after the cascade — the wrong place.

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

1. **D1 (mode-aware):** *single-pr* — in `execute.md`, persist the settled branch
   (HEAD) in `orchestrator_setup` into a koto context key, and read it in both
   `spawn_and_await` ticks as `SHARED_BRANCH` with a `|| impl/$PLAN_SLUG` fallback;
   add one prose rule to `skills/execute/SKILL.md` Single-PR path that an existing
   branch with an open PR is adopted as the home PR. *coordinated* — make the
   Coordinated Execution Path's targeting explicit in `skills/execute/SKILL.md`: the
   coordination branch/PR carries scoping-document updates only (PR-Index,
   merge-order); each repo that needs changes is worked in its own worktree and lands
   as its own per-repo PR (code never lands on the coordination branch). The
   recovered single-pr branch is re-validated before interpolation (it is an input
   surface); the coordinated per-repo worktree paths follow the same closed
   write-target discipline.
2. **D2:** The implement-then-pause behavior is governed by the existing execution
   mode, not a new flag. `/execute`'s `interactive` vs `--auto` resolution drives a
   `PAUSE_BEFORE_FINALIZE` template var: interactive sets it true, `--auto` sets it
   false. `pr_finalization`'s single edge becomes two guarded edges — when
   `PAUSE_BEFORE_FINALIZE`, route to a new non-failure terminal `paused_for_review`
   (chain intact: PLAN present, upstream un-transitioned, PR DRAFT); otherwise route
   straight to `plan_completion`. Under `--auto` the run therefore drives through the
   cascade and `gh pr ready` to a ready-to-merge, green PR with the chain
   transitioned — it never pauses. In interactive mode the run stops at
   `paused_for_review` and finalizes on the developer's approval (resume is the existing
   topic-keyed home-PR lookup re-entering `plan_completion`). The interactive pause is
   a **suspension**, not a termination: `exit:` stays UNSET with a resumable
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

This feature itself adds user-visible surface (the mode-driven interactive pause vs
`--auto`-finalizes behavior, the adopt-PR targeting, and the new durable-capture
convention), so per D3 this DESIGN carries `user_visible_surface: true` and `/plan`
will emit a docs work item for it — the change dogfoods its own rule.

## Solution Architecture

**Components touched:**

- `skills/execute/koto-templates/execute.md` — D1 (branch capture/inject), D2 (the
  `PAUSE_BEFORE_FINALIZE` edge split + `paused_for_review` terminal), D6 (PR title +
  two-part body in `pr_finalization`).
- `skills/execute/SKILL.md` — D1 adopt-PR prose, D2 mode-driven pause +
  suspension-exit documentation (interactive pauses, `--auto` finalizes), D4 guard
  pointer, D5 durable-capture pointer.
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

The change set adds no new attack surface beyond `/execute`'s six documented
security surfaces (`references/parent-skill-security.md`); each decision either
reuses an existing fail-closed check or stays within those surfaces.

- **D1 recovered branch (single-pr) is an input surface.** The settled branch
  captured from `HEAD` into a koto context key is re-validated before interpolation
  into any emitted shell or write path — the same discipline `/execute` already
  applies to the `gh`-recovered slug on cross-branch resume. An unparseable recovered
  branch rejects rather than interpolating. The `|| impl/$PLAN_SLUG` fallback never
  interpolates untrusted text.
- **D1 coordinated worktree paths.** Per-repo worktree paths are derived from the
  validated PR-Index `repo`/`pr_group` tags (already re-validated on each refresh
  read), not from free text; they follow `/execute`'s closed write-target discipline.
- **D2 pause adds no write target and no R9 bypass.** The `paused_for_review`
  terminal writes only the existing state projection; the suspension leaves `exit:`
  UNSET legitimately (the run has not terminated), so the R9 hard-finalization check
  — which fires only at terminal exits — is neither bypassed nor weakened.
- **D3 signal is read, not interpolated.** `user_visible_surface` is a boolean
  frontmatter flag read by `/plan` (which already reads bodies); the `docs/guides/*`
  fallback is a path-pattern match. Neither introduces untrusted interpolation, and
  `/execute` gains no content read (its metadata-only contract holds).
- **D4 reuses a fail-closed check.** `shirabe validate --lifecycle-chain … --mode=ready`
  is the existing validator with its multi-level exit-code contract (0/1/2); no new
  code surface, and a tool-error (exit 1) is distinct from a violation (exit 2).
- **D5 deliberately does not widen the write-target set.** The durable-capture home
  is a convention (a GitHub issue / `docs/` note authored by the developer), not an
  automated `/execute` emit — precisely to avoid adding a remote write target outside
  `/execute`'s closed set. The automated emit is deferred for that reason.
- **D6 PR title derives from the validated slug.** The conventional title is built
  from the PLAN slug (which matches `^[a-z0-9-]+$`), defaulting to `feat:`, never from
  raw developer prose interpolated into the title or shell. The two-part body is
  posted via `gh pr edit --body-file`/stdin discipline, not `-m` interpolation —
  consistent with `/execute`'s no-untrusted-input-interpolation surface.

No secrets, tokens, or credentials are introduced. The visibility boundary is
unchanged: `/execute` v1 binds to public-repo chains, and this work adds no
cross-visibility path.

## Consequences

**Positive:**

- Closes all six in-scope friction points with a minimal footprint — most changes
  are wiring or small additions to existing machinery (the override substrate,
  stop-at-ready, `/plan`'s docs routing, the `lifecycle-chain` validate mode).
- Preserves the default path byte-for-byte (R7): a fresh single-pr run with no
  existing-PR context and no interactive pause behaves exactly as today.
- Reinforces the autonomy contract: `--auto` delivers a finished, mergeable result;
  the pause is interactive-only.
- Dogfoods D3 — this feature sets `user_visible_surface: true`, so `/plan` emits a
  docs work item for its own user-visible surface (the mode-aware behaviors).

**Negative / trade-offs:**

- The R2 pause, R4 template PR, R5 guard, and R6 capture are specified for the
  single-pr path; the coordinated path's finalization contract is unchanged and a
  later effort is needed if those gaps prove to affect it.
- D1's coordinated branch-targeting introduces per-repo worktree management; this
  states an existing-dispatch rule explicitly rather than adding a new subsystem, but
  the worktree lifecycle is operational surface to get right.
- D5's durable-capture home, as a convention rather than an automated emit, depends
  on developer discipline; the automated alternative is heavier (it widens
  `/execute`'s write-target set) and is deferred.

**Mitigations:**

- Each of the six changes is an independently verifiable slice, so a regression in
  one does not block the others.
- The D4 finalization guard backstops the manual/fallback path that originally
  caused the missed finalization, catching the exact F5 failure mechanically.
