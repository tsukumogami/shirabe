---
schema: prd/v1
status: Done
problem: |
  The chain-aware `shirabe validate --lifecycle` mode accepts
  single-pr-mid-PR as a passing chain state, which is correct while an
  author iterates on a DRAFT pull request but wrong when the PR flips to
  ready-for-review. With no CI wiring and no work-on cascade pulling the
  chain to its terminal at ready time, the discipline that single-pr
  chains land their BRIEF and PRD at Done and delete their PLAN atomically
  is unenforced and silently breaks on the corpus.
goals: |
  Land a strict-mode toggle on the lifecycle check that fails
  single-pr-mid-PR when set; ship a reusable lifecycle CI workflow plus a
  self-caller workflow that runs the check with strictness conditional on
  the PR's `draft` state; wire the work-on cascade so the draft-to-ready
  flip atomically finalizes the chain (single-pr terminal or multi-pr
  work-completing); remove stale `docs/plans/done/` wording and align the
  /shirabe:roadmap and /shirabe:plan skill references with the implemented
  mechanism.
upstream: docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md
source_issue: 117
complexity: Complex
---

# PRD: lifecycle-draft-ready-discipline

## Status

Done

The PRD operationalizes the upstream BRIEF's framing for the
DRAFT-vs-READY discipline. Two architectural choices are left open for
the DESIGN to settle: the strict-mode interface shape (CLI flag,
environment variable, or both) and the cascade trigger mechanism
(workflow event hook, explicit subcommand, or in-skill intercept). Both
are tagged in the Decisions and Trade-offs section.

## Problem Statement

The previous increment landed `shirabe validate --lifecycle <root>` —
a chain-aware passing-state check that walks every artifact chain in
the tree and verifies each member is at its passing state for the
chain's posture. The check accepts single-pr-mid-PR as a passing state
because that is the correct shape while an author iterates: PLAN at
Active on the branch (the Draft -> Active gate auto-fires for single-pr
execution as /shirabe:plan finishes authoring), BRIEF and PRD at
Accepted upstream, DESIGN at Planned or Current. The chain settles into
its terminal — PLAN deleted, BRIEF and PRD at Done, DESIGN at Current —
only at PR-merge time, and the verify-then-delete commit that performs
the transitions is the single forcing function that pulls the chain
across the line.

What the check cannot distinguish today is when an author is still
iterating versus when the work is finished and the PR is being marked
ready for review. A DRAFT PR with single-pr-mid-PR state is healthy
iteration; a READY PR with the same shape means the author forgot the
verify-then-delete commit. The validator treats both identically.

CI never runs the check on PRs. Even if the strictness gap closed
itself, the corpus would still not be protected. And the work-on
cascade — the skill that takes a contributor from a fresh branch to a
merged PR — does not pull the chain to its terminal at ready time, so
the contributor has to remember the verify-then-delete dance from
memory and CI has no signal when they forget. Two recent PRs (the FC09
and FC08 reconciliation work) landed before the chain-aware model
existed, shipped with the chains drifted, and required corpus
reconciliation alongside the model itself. The present work closes the
gap so the next instance is caught at PR time.

## Goals

Wire the chain-aware lifecycle check into the workspace's CI surface
and the work-on cascade with a DRAFT-vs-READY gating discipline, so
that:

- A DRAFT PR passes CI when the chain is at any in-flight state the
  upstream check accepts.
- A READY PR passes CI only when the chain is at one of two coherent
  terminals — single-pr at-merge (PLAN deleted, BRIEF/PRD Done,
  DESIGN Current) or multi-pr in-flight (BRIEF Accepted, PRD
  Accepted or In Progress, DESIGN Current, PLAN Active) for
  intermediate multi-pr PRs, or multi-pr at-merge for the final
  multi-pr verify-then-delete PR.
- Transitioning a PR from draft to ready triggers an atomic
  finalization commit that drives single-pr chains to their terminal
  and multi-pr work-completing chains through their terminal, so the
  cascade is the path of least resistance and CI is the backstop.

## User Stories

- **As a contributor on a single-pr chain via work-on**, I want CI to
  pass against my mid-PR drafts and the cascade to drive the
  verify-then-delete commit when I finalize, so I don't have to
  remember the transition sequence from memory.
- **As a contributor who flipped a PR to ready outside the cascade**,
  I want CI to fail with a precise error naming the missing
  transitions, so I can make the finalization commit by hand and
  re-push.
- **As a contributor on a multi-pr chain**, I want intermediate PRs
  to pass CI in strict mode against the legitimate multi-pr in-flight
  shape and the final PR to drive the chain to at-merge via the
  cascade.
- **As a reviewer reading a failing CI annotation**, I want the
  message to name the file path, current state, chain posture, and
  expected passing state inline, so I can read it without
  out-of-band documentation lookup.
- **As a downstream-skill maintainer**, I want the /shirabe:roadmap
  and /shirabe:plan references to describe the implemented mechanism
  (verify-then-delete terminal, whole-tree CI gate, DRAFT-vs-READY
  discipline) consistently, so authors reading the docs are not led
  astray by stale wording.

## Requirements

### Functional

**R1.** `shirabe validate --lifecycle` SHALL gain a strict-mode toggle
that, when set, disables in-flight exemptions for single-pr chains. A
present single-pr PLAN fails (regardless of `status:` value); a
single-pr BRIEF or PRD at Accepted fails when the chain's posture is
single-pr (the chain is in a single-pr shape, not the multi-pr
in-flight shape). Multi-pr in-flight states remain acceptable under
strict mode. Default off — preserves the upstream check's behavior in
non-CI invocations.

**R2.** The strict-mode toggle SHALL be exposed through an interface
the downstream DESIGN settles. The interface MUST be discoverable in
the same idiom as the existing `--visibility` flag (which is a CLI
flag set by the calling workflow). The interface MUST be threadable
from the lifecycle CI workflow's run step using only documented
GitHub Actions context expressions. Three alternatives are on the
table: a `--strict` CLI flag, a `SHIRABE_LIFECYCLE_STRICT` environment
variable, or both. The DESIGN picks one.

**R3.** A reusable lifecycle workflow SHALL be added at
`.github/workflows/lifecycle.yml`. The workflow SHALL declare
`workflow_call:` inputs (none required), build the `shirabe` binary
from source at the called workflow's ref (matching the existing
`validate-docs.yml` supply-chain pattern), and invoke `shirabe
validate --lifecycle .` against the caller repo's working tree. The
workflow SHALL set strict mode conditional on
`github.event.pull_request.draft == false`. The workflow's
`permissions:` block SHALL grant only `contents: read`.

**R4.** A self-caller workflow SHALL be added that invokes the
reusable lifecycle workflow against this repo's own PRs. The
self-caller SHALL trigger on `pull_request` events with no `paths:`
filter — the whole-tree scan is the point. The self-caller SHALL
include `types: [opened, synchronize, reopened, ready_for_review,
converted_to_draft]` so the strictness branch is re-evaluated on
every draft-to-ready (and ready-to-draft) transition.

**R5.** All workflow YAML SHALL use SHA-pinned actions, matching the
existing `validate-docs.yml` pattern (e.g.,
`actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2`).
No floating tags or branch references are acceptable.

**R6.** The work-on cascade SHALL be wired so that transitioning a PR
from draft to ready triggers atomic chain finalization. The trigger
mechanism is left to the DESIGN to settle from three alternatives: a
GitHub Actions `ready_for_review` workflow event hook, an explicit
`shirabe finalize` subcommand the cascade runs before `gh pr ready`,
or the work-on skill intercepting `gh pr ready` and performing the
finalization inline. The trigger MUST cover the three chain-shape
cases:

  - **single-pr chain.** PLAN transitioned Active to Done to deleted,
    BRIEF and PRD transitioned Accepted to Done atomically in the
    same commit before `gh pr ready` fires. The Active to Done flip
    is symmetric with the multi-pr work-completing gesture under the
    unified PLAN lifecycle; the only mode-specific difference is the
    Draft to Active gate (auto for single-pr, human-approved for
    multi-pr) which already fired earlier in the workflow.
  - **multi-pr chain in the work-completing PR.** PLAN transitioned
    Active to Done to deleted, BRIEF and PRD transitioned Accepted
    to Done in the same commit before `gh pr ready` fires.
  - **multi-pr chain in an intermediate PR.** No transitions needed
    — multi-pr in-flight is a legitimate passing state on a READY
    PR.

**R7.** The work-on cascade SHALL run the strict-mode lifecycle check
locally before performing the finalization (verifying the check's
failure mode names the right violator) and again after the
finalization commit lands (verifying the chain is now at its passing
state). A check failure before finalization is expected and drives
the transitions; a failure after finalization is a bug in the
finalization logic and SHALL halt the cascade with a diagnostic.

**R8.** The stale `docs/plans/done/` wording SHALL be removed from
`skills/plan/references/quality/plan-doc-structure.md`. Two sections
carry the stale wording today: the lifecycle prose at line 50 and the
state-table row at line 80.

**R9.** The `/shirabe:roadmap` and `/shirabe:plan` skill references
SHALL be updated to describe the single verify-then-delete terminal,
the whole-tree CI gate, and the DRAFT-vs-READY discipline. The
updates SHALL replace any prose implying a `docs/plans/done/` move,
align with the chain-aware passing-state model the upstream PRD
codifies, and surface the DRAFT-vs-READY discipline as the gate that
fires at the draft-to-ready flip.

### Non-functional

**R10.** The lifecycle check's run time under CI SHALL remain
proportional to the size of the doc tree, bounded by the existing
chain-walker's complexity. The strict-mode toggle SHALL NOT add an
asymptotic complexity layer; it changes which conditions count as
failures, not which conditions are evaluated.

**R11.** The lifecycle workflow's permissions SHALL be `contents:
read` only. The check is a read-only scan; no write token, no
issue-comment write, no PR-edit, no branch push from the workflow.

**R12.** Test coverage SHALL include the six shapes named in the
acceptance criteria (single-pr-mid-PR on DRAFT and READY; single-pr
terminal on READY; multi-pr in-flight on READY; multi-pr
mid-transition on READY; strict-flag-threading verified) plus the
work-on cascade's three chain-shape cases (single-pr, multi-pr
work-completing, multi-pr intermediate).

## Acceptance Criteria

- [ ] `shirabe validate --lifecycle` gains a strict-mode toggle whose
  interface matches the chosen DESIGN alternative. Default off.
- [ ] A present single-pr PLAN fails the check in strict mode.
- [ ] A single-pr BRIEF or PRD at Accepted (chain in single-pr
  posture) fails the check in strict mode.
- [ ] A multi-pr in-flight chain (BRIEF Accepted, PRD Accepted or In
  Progress, DESIGN Current, PLAN Active) passes the check in strict
  mode.
- [ ] A multi-pr mid-transition chain (PLAN Done but BRIEF or PRD
  still at Accepted) fails the check in strict mode.
- [ ] A reusable lifecycle workflow at `.github/workflows/lifecycle.yml`
  builds the binary from source and runs the check with strictness
  conditional on `github.event.pull_request.draft == false`.
- [ ] A self-caller workflow invokes the reusable workflow on this
  repo's PRs with no `paths:` filter and the
  `types: [opened, synchronize, reopened, ready_for_review,
  converted_to_draft]` event surface.
- [ ] All workflow YAML uses SHA-pinned actions.
- [ ] The lifecycle workflow declares `permissions: contents: read`
  only.
- [ ] The work-on cascade performs the atomic finalization commit
  before `gh pr ready` fires on single-pr and multi-pr
  work-completing chains; the cascade is a no-op on multi-pr
  intermediate chains.
- [ ] The cascade runs the strict-mode check before and after the
  finalization commit; a post-commit failure halts the cascade with a
  diagnostic.
- [ ] `skills/plan/references/quality/plan-doc-structure.md` is free
  of `docs/plans/done/` wording. Both sections at lines 50 and 80 are
  reworded to match the verify-then-delete terminal.
- [ ] The `/shirabe:roadmap` and `/shirabe:plan` skill references
  describe the verify-then-delete terminal, the whole-tree CI gate,
  and the DRAFT-vs-READY discipline.
- [ ] `cargo build` and `cargo test` pass.
- [ ] All edits are public-visibility clean and use no banned
  writing-style words.
- [ ] `shirabe validate --lifecycle .` against the final tree passes
  in both non-strict (mid-PR) and strict (at-merge) modes.

## Out of Scope

- Extending the chain-aware passing-state model itself. The upstream
  BRIEF and PRD define the posture inference and the per-posture
  passing-state table; the present work consumes both unchanged and
  adds a strictness branch only on the single-pr-mid-PR exemption.
- A separate ROADMAP-lifecycle check or any other new check code
  beyond the existing `Lnn` family. The strict-mode toggle reshapes
  which conditions fire `L01` for single-pr chains; it does not
  introduce a new check code.
- Auto-fixing drifted docs the current PR does not touch. The
  cascade performs the finalization commit for the chain the current
  PR participates in; it does not scan the tree for other drifted
  chains.
- Multi-repo chain validation. The whole-tree scan is bounded to the
  given root, matching the upstream BRIEF's scope.
- Reorganizing the existing `validate-docs.yml` workflow. The
  lifecycle workflow is a separate file with separate semantics; the
  content validator remains diff-scoped and unchanged.
- Changing the `L02` orphan-doc rule. The orphan-doc semantics were
  settled by the upstream decision record; the present work runs the
  unchanged orphan rule under both strict and non-strict modes.

## Decisions and Trade-offs

The DESIGN owns two settled-by-decision questions. Both are
deliberately left as alternatives in the requirements above so the
DESIGN can pick the option matching the workspace's other tooling
patterns.

**Strict-mode interface (R2).** Three viable alternatives:

- A `--strict` CLI flag — discoverable via `--help`, parallel to the
  existing `--visibility` flag, but requires the workflow YAML to
  template the flag conditionally based on the PR's `draft` state.
- A `SHIRABE_LIFECYCLE_STRICT=1` environment variable — simpler
  workflow YAML (one `env:` block with a ternary expression), but
  hidden from authors running the CLI locally.
- Both — belt-and-suspenders, but adds API surface area and a
  precedence rule (flag wins, env loses) the validator now has to
  carry.

**Cascade trigger mechanism (R6).** Three viable alternatives:

- A GitHub Actions `ready_for_review` workflow event hook —
  GitHub-side; the workflow runs, fails on missing finalization, and
  the author makes the fix-up commit and re-pushes. The cascade
  exists only as a CI gate.
- An explicit `shirabe finalize` subcommand the cascade runs before
  `gh pr ready` — local, explicit, surfaces the finalization
  gesture as a discoverable command. The cascade is a path the
  work-on skill walks the author through.
- The work-on skill intercepts `gh pr ready` and performs the
  finalization inline — most automated, lowest author burden, but
  the work-on skill becomes the only path that gets the cascade
  right and authors using `gh pr ready` outside the skill miss the
  forcing function.

The DESIGN evaluates these against the existing tooling idioms in
shirabe, the failure-mode profile each alternative leaves on the
corpus, and the developer-experience profile each leaves for
contributors not using the work-on skill.

## References

- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` — the
  upstream BRIEF; the present PRD operationalizes its framing.
- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` and
  `docs/prds/PRD-lifecycle-passing-state-validation.md` — the
  upstream increment's BRIEF and PRD; their delivered chain-aware
  passing-state model is what the present work extends.
- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
  — the orphan-doc rule that applies unchanged under strict mode.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
  — the posture-detection rule that drives the strict-vs-non-strict
  branch on single-pr-mid-PR exemption.
- `docs/prds/PRD-roadmap-plan-standardization.md` — the parent PRD;
  R17 and R18 carry the chain-aware passing-state framing the
  upstream work amended, and the present work completes the CI-wiring
  half those requirements name.
- `.github/workflows/validate-docs.yml` — the existing reusable
  validator workflow whose SHA-pinning and binary-build patterns the
  lifecycle workflow mirrors.
