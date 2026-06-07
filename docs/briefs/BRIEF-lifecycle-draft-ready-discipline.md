---
schema: brief/v1
status: Accepted
problem: |
  `shirabe validate --lifecycle` accepts single-pr-mid-PR as a passing chain
  state, which is correct while an author iterates on a DRAFT pull request
  but wrong when the PR flips to ready-for-review. With no CI wiring and no
  cascade pulling the chain to its terminal at ready time, the discipline
  that single-pr chains land their BRIEF and PRD at Done and delete their
  PLAN in the same commit is unenforced and silently breaks on the corpus.
outcome: |
  A contributor on a DRAFT pull request runs CI and the chain-aware check
  passes against mid-PR state; the same contributor marks the PR ready and
  CI now enforces the strict shape, with the work-on cascade having
  atomically finalized the chain (PLAN deleted, BRIEF/PRD Done) inside the
  draft-to-ready flip. The DRAFT-vs-READY distinction becomes the forcing
  function that drives every single-pr chain to its terminal before merge.
upstream: docs/briefs/BRIEF-lifecycle-passing-state-validation.md
---

# BRIEF: lifecycle-draft-ready-discipline

## Status

Accepted

The framing layers the DRAFT-vs-READY discipline on top of the chain-aware
passing-state model already landed by the upstream BRIEF. The downstream
PRD will operationalize the requirements articulation for the strict-mode
toggle, the reusable CI workflow, and the work-on cascade wiring.

## Problem Statement

The chain-aware `--lifecycle` check that landed in the previous increment
walks every artifact chain in the tree and verifies each member is at its
passing state for the chain's posture. The check accepts single-pr-mid-PR
as a passing state — a PLAN at Active on the branch, with the upstream
BRIEF and PRD at Accepted — because that is the correct shape while an
author iterates on the work. PLAN docs use a unified Draft -> Active ->
Done -> DELETED lifecycle; the Draft -> Active gate auto-fires for
single-pr execution as /shirabe:plan finishes authoring, so a committed
single-pr PLAN is always at Active.

What the check cannot distinguish is when an author is still iterating
versus when the work is finished and the PR is being marked ready for
review. A DRAFT PR with single-pr-mid-PR state is healthy iteration; a
READY PR with the same shape means the author forgot to delete the PLAN
and transition BRIEF and PRD to Done in the same commit. The validator
treats both identically, so the discipline that single-pr chains land
their terminal transitions atomically inside the draft-to-ready flip is
unenforced.

CI never runs the check today, so even if the strictness gap were closed
the corpus would still not be protected. And the work-on cascade — the
skill that takes an author from a fresh branch to a merged PR — does not
pull the chain to its terminal at ready time, so the author has to
remember the verify-then-delete dance from memory and CI has no signal
when they forget. Together the three gaps add up to a discipline that
reads as written in the parent PRD but does not hold on the corpus.

## User Outcome

A contributor working through a single-pr chain via the work-on skill
opens a draft PR, iterates against the chain mid-PR — PLAN at Active,
BRIEF and PRD at Accepted — and CI runs the lifecycle check against that
mid-PR state in non-strict mode and passes. The contributor then marks
the PR ready for review; the work-on cascade detects the draft-to-ready
flip, deletes the PLAN, transitions BRIEF and PRD from Accepted to Done
in the same finalization commit, and only then runs `gh pr ready`. CI
re-runs in strict mode against the ready PR and passes — the chain is at
its single-pr terminal (PLAN deleted, BRIEF/PRD Done, DESIGN Current).

A contributor who flips a PR to ready without running the cascade — for
example, by directly invoking `gh pr ready` on a PR with the PLAN still
present — sees CI fail in strict mode with a precise error naming the
chain member, its current state, and the passing state for the chain at
ready time. The fix is to add the missing finalization commit and push;
CI re-runs and passes. The DRAFT-vs-READY discipline becomes the gate
the existing chain-aware check enforces conditional on the PR's draft
state, and the work-on cascade becomes the mechanism that drives every
single-pr chain through it without the author having to remember the
sequence.

A contributor on a multi-pr chain experiences the gate symmetrically: a
DRAFT or READY PR carrying the multi-pr in-flight state (BRIEF Accepted,
PRD Accepted or In Progress, DESIGN Current, PLAN Active) passes the
check in both modes, because multi-pr in-flight is a legitimate ongoing
shape that lives across multiple PRs. The last PR in the multi-pr chain
— the verify-then-delete PR — runs the cascade, which transitions PLAN
from Active through Done to deleted and BRIEF/PRD from Accepted to Done,
and CI passes in strict mode against the at-merge multi-pr shape.

## User Journeys

### A contributor lands a single-pr feature via work-on

A contributor invokes `/shirabe:work-on` against a PLAN whose
`execution_mode` is `single-pr`. The skill creates a branch, opens a
draft PR, and iterates through implementation. CI runs the lifecycle
workflow on every push; while the PR is draft, the workflow invokes the
chain-aware check in non-strict mode, and the chain at single-pr-mid-PR
(BRIEF Accepted, PRD Accepted, DESIGN Current, PLAN Active) passes. When
implementation is complete, the contributor instructs work-on to
finalize. The cascade runs the chain-aware check in strict mode locally
first — which fails on the PLAN-still-present condition — then performs
the atomic finalization commit (`git rm` the PLAN, edit BRIEF and PRD
frontmatter and Status section from Accepted to Done), pushes the
commit, and only then runs `gh pr ready`. CI re-runs in strict mode
against the ready PR and passes.

### A contributor flips a PR to ready without the cascade

A contributor opens a draft PR manually and works through the chain
without invoking the work-on cascade. When the work is done, the
contributor runs `gh pr ready` directly, bypassing the cascade. CI runs
the lifecycle workflow against the ready PR in strict mode; the check
fails with the message that names the present PLAN as the violator and
the expected at-merge passing state (BRIEF Done, PRD Done, DESIGN
Current, PLAN deleted). The contributor reads the failure, makes the
atomic finalization commit by hand, pushes, and the next CI run passes.
The CI gate is the safety net for the cascade — the cascade is the path
of least resistance, the CI gate is the backstop.

### A contributor opens the final PR in a multi-pr chain

A contributor on the last child issue of a multi-pr chain invokes
work-on. The branch carries the PLAN at Active and the parent BRIEF and
PRD at Accepted. After implementation the contributor finalizes; the
cascade detects the multi-pr work-completing shape (the chain's PLAN is
the only remaining open work item), transitions PLAN from Active to
Done to deleted, transitions BRIEF and PRD from Accepted to Done, and
the resulting commit reaches the at-merge multi-pr shape. CI re-runs in
strict mode and passes. Mid-chain PRs in the same multi-pr chain — PRs
that close intermediate child issues without completing the chain —
mark themselves ready while the chain stays at multi-pr in-flight, and
CI passes in strict mode against that legitimate ongoing shape.

### A contributor edits the chain on a non-cascade PR

A contributor opens a PR that touches a single doc in `docs/` — say, a
typo fix in the parent PRD body — and marks the PR ready. The lifecycle
workflow runs in strict mode against the whole tree; the check
inspects every chain in the tree (not just the chain the diff touches)
and passes because no chain is at a violating shape. The whole-tree
scan is the point — the check finds drift in chains the PR's diff does
not name, because the whole-tree shape is the property the CI gate
defends.

### A maintainer reads the failure annotation

A maintainer reviews a CI annotation emitted by a failing strict-mode
check. The annotation names the file path, the current frontmatter
status, the chain posture the validator inferred, and the passing state
expected for that posture. The maintainer reads the annotation, opens
the named file, sees the discrepancy, and either applies the missing
transition or queries the author for the next step. The annotation is
self-explanatory — no out-of-band documentation lookup is needed to
read it — because the chain-aware model already names every state in
plain English.

## Scope Boundary

### IN scope

- A strict-mode toggle on `shirabe validate --lifecycle` that disables
  in-flight exemptions for single-pr chains: a single-pr PLAN present in
  the tree fails, and single-pr BRIEF or PRD at Accepted (when the chain
  is at single-pr posture and not at the multi-pr in-flight shape) fails.
  Multi-pr in-flight states remain acceptable in strict mode. Default
  off — preserves the upstream check's behavior in non-CI invocations.
- The interface shape for the strict-mode toggle: CLI flag, environment
  variable, or both. The downstream design owns the choice.
- A reusable lifecycle workflow at `.github/workflows/lifecycle.yml` (or
  a similarly-named file) that runs `shirabe validate --lifecycle .` on
  every PR, with strict mode set conditional on
  `github.event.pull_request.draft == false`. Permissions limited to
  `contents: read`. SHA-pinned actions throughout.
- A self-caller workflow that invokes the reusable lifecycle workflow
  against this repo's own PRs, with no `paths:` filter — the whole-tree
  scan is the point.
- The work-on cascade wiring that runs the strict-mode check locally
  before `gh pr ready`, performs the atomic finalization commit (PLAN
  deletion plus BRIEF/PRD Done transitions for single-pr; PLAN Active to
  Done to deleted plus BRIEF/PRD Done transitions for multi-pr
  work-completing; no-op for multi-pr in-flight), pushes the commit, and
  only then runs `gh pr ready`. The trigger mechanism — workflow event
  hook, subcommand the author runs explicitly, or in-skill intercept of
  `gh pr ready` — is owned by the downstream design.
- Removal of the stale `docs/plans/done/` wording from
  `skills/plan/references/quality/plan-doc-structure.md`. The wording
  predates the verify-then-delete terminal and gives a misleading
  alternative path.
- Skill-reference updates to `/shirabe:roadmap` and `/shirabe:plan`
  describing the single verify-then-delete terminal, the whole-tree CI
  gate, and the DRAFT-vs-READY discipline so the prose reads
  consistently with the implemented mechanism.
- Tests covering the six shapes named in the issue's acceptance
  criteria: DRAFT PR with single-pr-mid-PR (pass), READY PR with
  single-pr-mid-PR (fail), READY PR with single-pr terminal (pass),
  READY PR with multi-pr in-flight (pass), READY PR with multi-pr
  mid-transition (fail), strict-flag threading verified.

### OUT of scope

- Extending the chain-aware passing-state model itself. The upstream
  BRIEF and its delivered work define the posture inference and the
  per-posture passing-state table; the present work consumes both
  unchanged and adds a strictness branch only on the single-pr-mid-PR
  exemption.
- A separate ROADMAP-lifecycle check or any other new check code
  beyond the existing `Lnn` family. The strict-mode toggle reshapes
  which conditions fire `L01` for single-pr chains; it does not
  introduce a new check code.
- Auto-fixing drifted docs. The cascade performs the finalization
  commit when the author invokes the finalization gesture; it does not
  scan the tree for drifted chains the current PR does not touch.
- Multi-repo chain validation. The whole-tree scan is bounded to the
  given root, matching the upstream BRIEF's scope.
- Reorganizing the existing `validate-docs.yml` workflow. The lifecycle
  workflow is a separate file with separate semantics; the existing
  content validator remains diff-scoped and unchanged.
- Changing the L02 orphan-doc rule. The orphan-doc semantics were
  settled by the upstream decision record; the present work runs the
  unchanged orphan rule under both strict and non-strict modes.

## References

- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` — the
  upstream BRIEF whose delivered chain-aware passing-state model the
  present work consumes and extends with a strictness branch.
- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
  — the orphan-doc rule that applies unchanged under strict mode.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` —
  the posture-detection rule that drives the strict-vs-non-strict
  branch on single-pr-mid-PR exemption.
- `docs/prds/PRD-roadmap-plan-standardization.md` — the parent PRD;
  R17 and R18 carry the chain-aware passing-state framing as amended
  by the upstream work, and the present work completes the CI-wiring
  half that those requirements name.
