---
schema: prd/v1
status: Draft
upstream: docs/briefs/BRIEF-shirabe-pattern-v1-workflow-friction.md
problem: |
  Three shirabe pattern-v1 workflow primitives fail catastrophically and
  silently on routine chain runs: the single-pr `plan-to-tasks.sh` parser
  drops every dependency edge when the colon is inside the bold markers
  (tsukumogami/shirabe#156), `/design` and `/plan` refuse to auto-transition
  their upstream artifact the way `/prd` does (tsukumogami/shirabe#159), and
  `/work-on` doesn't notice an upstream main change that has invalidated the
  PLAN's foundation mid-chain (tsukumogami/shirabe#162). Each fires on a
  routinely-taken path, each fails without a signal the operator can act on,
  and each costs hours of manual recovery when discovered downstream.
goals: |
  Close the catastrophic-by-default, silent-by-default failure shape across
  all three surfaces as a coordinated sweep. After this PRD's downstream
  work ships, an operator running the standard pattern-v1 chain workflows
  (`/scope <topic>`, `/work-on` against a single-pr PLAN, `/work-on` driving
  a long-running PR) no longer pays a manual-recovery tax: chain handoffs
  complete without operator transition steps, single-pr linear dependency
  chains spawn sequentially, and upstream main changes that invalidate a
  PLAN's foundation surface mid-chain rather than at finalization.
---

# PRD: shirabe pattern-v1 workflow friction sweep

## Status

Draft

## Problem Statement

Three shirabe pattern-v1 workflow primitives fail catastrophically and
silently on routinely-taken chain paths. They are unrelated at the code
level — a regex in `plan-to-tasks.sh`, status-gate logic across `/design`
and `/plan`, worktree-discipline coverage in `/work-on` — but they share a
single failure shape: each fires on a path operators take by default, each
fails without a signal the operator could act on, and each leaves the chain
in a state where the only recovery is manual intervention costed at hours.

The shape recurs because every one of these surfaces has a default-failure
mode that the tooling treats as success. The parser succeeds on a PLAN with
silently-dropped dependencies; the status-gate "succeeds" by hard-stopping
without offering the operator a path forward; the orchestrator "succeeds"
by continuing to commit against a foundation that has been deleted on main.
Each surface has its own contract that needs binding; the sweep is
coordinated because the failure shape only closes when all three are bound.

The affected operators are shirabe maintainers and other authors running
pattern-v1 chain workflows during normal use, not edge-case experimentation.
The friction surfaced repeatedly during the v0.7.0/0.7.1-dev dogfooding
window (the `/comp` skill work in tsukumogami/shirabe#141 and the
child-dispatch-contract work in tsukumogami/shirabe#151). The dogfooding
also surfaced other workflow bugs (#155, #157, #158, #160, #161, #163,
#164) that are deliberately not part of this sweep — they have different
failure shapes (loud-not-silent, edge-case-not-routine, or
ergonomics-not-catastrophic) and are tracked as independent work streams.

## Goals

Operators running the three standard pattern-v1 chain workflows reach the
terminal artifact without manual recovery. Concretely:

- A `/scope <topic>` run threads `/brief -> /prd -> /design -> /plan`
  without the operator dropping into a shell to run a status-transition
  command between children.
- A `/work-on <plan-path>` run against a single-pr PLAN with a linear
  dependency chain spawns children in dependency order on the shared
  branch, regardless of which colon placement the PLAN author used inside
  the `**Dependencies**` line.
- A `/work-on` run driving a long-running PR detects an upstream change to
  the tracking branch that invalidates the PLAN's foundational assumptions,
  surfaces the change to the operator as an actionable signal, and does so
  before CI silently stops creating check-runs.

The unifying outcome is that the standard pattern-v1 chain workflows stop
having a class of routinely-reachable failure modes that hide from the
operator until downstream cost has accumulated.

## User Stories

These are technical workflow stories; the "user" is a shirabe maintainer or
other operator running pattern-v1 chain commands.

**Story 1 — Chain handoff completes without manual transitions.**
As a shirabe maintainer, I want `/scope <topic>` to thread through
`/brief -> /prd -> /design -> /plan` in one sitting without me needing to
drop into a shell and run a transition command between children, so that
the chain's value proposition (one orchestrated conversation through the
tactical altitude) is delivered without a recurring per-handoff recovery
step.

**Story 2 — Single-pr PLAN with linear chain spawns sequentially.**
As a shirabe maintainer running `/work-on` against a single-pr PLAN whose
issues form a strictly-linear dependency chain (issue N+1 edits files
issue N created), I want the orchestrator to spawn children in dependency
order on the shared branch regardless of which colon placement I used
inside `**Dependencies**`, so that authoring the PLAN doesn't have a
silent-failure mode that catastrophically reorders the work.

**Story 3 — Upstream main change is caught mid-chain.**
As a shirabe maintainer running `/work-on` against a multi-hour single-pr
PLAN, I want the orchestrator to detect an upstream change to the tracking
branch between commits and surface an actionable signal when the change
invalidates the PLAN's foundational assumptions, so that I find out at
the point recovery is cheapest rather than after CI has been silently
suppressed for hours.

**Story 4 — Silent failures convert to actionable signals.**
As a shirabe maintainer hitting any of the three failure shapes above, I
want the failure surface itself to emit a signal I can act on (a warning
the parser surfaced, an escalation the orchestrator raised, a CI-state
classification that distinguishes "pending" from "suppressed"), so that
the recovery work I do is targeted at the actual problem rather than at
diagnosing "what does silence mean here."

## Requirements

Requirements are grouped by the three bugs. Each requirement binds a
contract that must hold post-fix; mechanism choices (which fix candidate
each issue body enumerates) are deferred to DESIGN.

### Functional Requirements: Bug #156 (parser silent-empty-deps)

**R1.** The single-pr `plan_outline` parser in
`skills/plan/scripts/plan-to-tasks.sh` SHALL extract the dependency line
from a PLAN issue outline regardless of whether the author wrote
`**Dependencies**:` (colon outside the bold markers) or
`**Dependencies:**` (colon inside the bold markers).

**R2.** When the parser yields empty dependencies for a single-pr issue
outline AND the PLAN declares more than one issue, the workflow SHALL
surface a signal the operator can act on before the orchestrator's parallel
dispatch step runs. The surface that emits the signal (parser warning,
orchestrator refusal, validator check, or other) is a DESIGN choice; the
contract is that the failure case stops being silent on the path that
operators routinely take.

**R3.** The fix SHALL NOT regress the existing `### Dependencies` section
format (lines 312-339 of `plan-to-tasks.sh` as of the bug's surfacing
commit) which is independently parsed and must continue to work.

### Functional Requirements: Bug #159 (chain-handoff asymmetry)

**R4.** When `/design` is invoked from a parent-driven chain (the
`parent_orchestration` sentinel established in tsukumogami/shirabe#151 is
present in the invocation context) AND its upstream PRD is at a status
that today triggers the Phase 0 hard-stop, the handoff SHALL complete
without operator intervention. The mechanism (auto-transition, sentinel-gated
transition, documented operator-contract with a different escalation path,
or other) is a DESIGN choice; the contract is that the operator does not
drop into a shell to satisfy the gate when a parent is driving the chain.

**R5.** When `/plan` is invoked from a parent-driven chain (same sentinel
context) AND its upstream DESIGN is at a status that today triggers the
Phase 1 hard-stop, the handoff SHALL complete without operator
intervention. Same mechanism-deferred clause as R4.

**R6.** When `/design` or `/plan` is invoked directly (no parent
orchestration context), the existing protective behavior SHALL still be
reachable. A direct invocation against a Draft PRD or Proposed DESIGN
SHALL NOT silently auto-promote the upstream; the silent-by-default
failure shape is the parent-chain case, not the direct-invocation case.

**R7.** The chain-handoff pattern across `/prd`, `/design`, and `/plan`
SHALL be symmetric: whatever contract `/prd` applies to its upstream
BRIEF (auto-transition in v0.9.1-dev), `/design` (with PRD upstream) and
`/plan` (with DESIGN upstream) apply the analogous contract. DESIGN MAY
align by changing all three skills, or by leaving `/prd` as the reference
and bringing the other two into alignment, or by introducing a shared
helper they all consume; the contract R7 binds is that the asymmetry is
removed, not the direction of alignment.

### Functional Requirements: Bug #162 (work-on upstream-drift + ci_monitor)

**R8.** A `/work-on` run driving a long-running single-pr PR SHALL fetch
the tracking branch and classify the impact of any upstream changes
against the PLAN's foundational assumptions between per-issue commits.
The classification SHALL be one of three categories matching the contract
in `references/parent-skill-worktree-discipline.md` (None, Informational,
Intent-changing) or a successor categorization DESIGN defines.

**R9.** Intent-changing upstream changes SHALL surface an escalation the
operator can act on at the point of detection. The escalation surface
(operator prompt, halt + status report, koto-context decision request,
or other) is a DESIGN choice; the contract is that the operator finds out
mid-chain rather than at PR finalization.

**R10.** The `ci_monitor` step (defined in
`skills/work-on/koto-templates/work-on-plan.md` and used by `/work-on`'s
finalization phase) SHALL distinguish between "checks are pending" and
"checks cannot be reported because the PR state suppresses workflow
creation" (the latter typically signalled by
`mergeStateStatus=DIRTY` or by zero check-runs after a bounded duration).

**R11.** The suppressed-checks case SHALL route to an actionable
escalation surface, not to indefinite wait. DESIGN MAY share the
escalation surface with R9's escalation or use a distinct one; the
contract is that `ci_monitor` is no longer reachable as a silent
indefinite-wait state on a DIRTY PR.

### Non-Functional Requirements

**R12.** No requirement above shall be satisfied by a fix that silently
changes the behavior of skills outside the three named bugs (`/prd`'s
existing brief-handoff transition, the multi-pr / GitHub-issue-backed
parsing path in `plan-to-tasks.sh`, `/work-on`'s phases unrelated to
upstream-drift detection). DESIGN MAY refactor shared infrastructure if
that produces a better fix, but the test surface that proves R12 is grep-
or test-checkable: changes outside the three bugs' immediate surfaces are
documented in DESIGN and called out at review.

**R13.** Each of the three bugs' fixes SHALL be independently shippable.
DESIGN MAY group them into a single PR or split them across PRs; the
contract is that no fix creates a hard dependency on another fix landing
first. This preserves the sweep's roll-back granularity if a single fix
needs to be reverted.

## Acceptance Criteria

Acceptance criteria are grouped to match the requirements. Each criterion
is grep-checkable or executable unless explicitly marked as judgment-based.

### Bug #156 (parser silent-empty-deps)

- [ ] **AC1.1** (grep-checkable, satisfies R1): A test fixture PLAN
  containing one issue with `**Dependencies**:` and another issue with
  `**Dependencies:**` produces non-empty `waits_on` for both issues when
  `plan-to-tasks.sh` runs against it.
- [ ] **AC1.2** (grep-checkable, satisfies R1): The regex on
  `skills/plan/scripts/plan-to-tasks.sh:288` (or its successor location)
  matches both colon placements, verifiable by grep against the script
  body or by a unit-test fixture exercising both forms.
- [ ] **AC2.1** (executable, satisfies R2): A test fixture PLAN with two
  issues where the second's `**Dependencies**` line is malformed and
  yields empty deps SHALL produce an operator-visible signal (warning to
  stderr, validator error, orchestrator refusal, or equivalent) before the
  parallel-spawn step runs. The signal's surface is whatever DESIGN
  chose; AC2.1 verifies the signal exists.
- [ ] **AC2.2** (judgment-based, satisfies R2): The signal from AC2.1 is
  written in language that names what the operator should do next (not
  just "empty deps detected" but "empty deps on issue N of M; check
  Dependencies line formatting"). Verified by inspection at review.
- [ ] **AC3.1** (executable, satisfies R3): A test fixture PLAN using
  the `### Dependencies` section format (multi-line accumulator) parses
  unchanged from its pre-fix behavior.

### Bug #159 (chain-handoff asymmetry)

- [ ] **AC4.1** (executable, satisfies R4): A `/scope` run that produces
  a Draft PRD and then dispatches `/design` against that PRD completes
  Phase 0 without the operator running a transition command. End-to-end
  fixture: fresh BRIEF -> `/scope` -> `/design` reaches its Phase 1.
- [ ] **AC4.2** (grep-checkable, satisfies R4): `/design`'s Phase 0
  status-gate body in `skills/design/references/phases/phase-0-setup-prd.md`
  contains an explicit branch or invocation that handles the
  parent-orchestration case (sentinel detected, handoff completed without
  STOP). Surface name is whatever DESIGN named it.
- [ ] **AC5.1** (executable, satisfies R5): Same as AC4.1 extended one
  child: fresh BRIEF -> `/scope` -> `/design` -> `/plan` reaches a
  decomposition Phase without operator intervention.
- [ ] **AC5.2** (grep-checkable, satisfies R5): `/plan`'s Phase 1
  status-gate body in `skills/plan/references/phases/phase-1-analysis.md`
  contains the analogous branch to AC4.2.
- [ ] **AC6.1** (executable, satisfies R6): A direct `/design` invocation
  (no parent context, no sentinel) against a Draft PRD STILL produces the
  Phase 0 stop with the operator-facing "PRD must be Accepted" message.
  Same for `/plan` against a non-Accepted DESIGN.
- [ ] **AC7.1** (judgment-based, satisfies R7): A review of `/prd`,
  `/design`, and `/plan`'s upstream-handoff handling reaches the
  conclusion that the three skills' patterns are symmetric (a reviewer
  reading them can describe a single shared handoff contract). DESIGN
  documents the shared contract in its body; AC7.1 verifies the
  documentation exists and is consistent.

### Bug #162 (work-on upstream-drift + ci_monitor)

- [ ] **AC8.1** (grep-checkable, satisfies R8): `/work-on`'s per-commit
  loop body (one of the phase files under `skills/work-on/references/phases/`
  or the koto template that drives it) contains an invocation of the
  fetch + impact-classification flow defined in
  `references/parent-skill-worktree-discipline.md` (or its successor
  reference if DESIGN renamed it).
- [ ] **AC8.2** (executable, satisfies R8): A test fixture that simulates
  an upstream commit landing on the tracking branch between two `/work-on`
  iterations produces an impact classification (None / Informational /
  Intent-changing or the DESIGN-chosen successor categories) in the
  workflow's state.
- [ ] **AC9.1** (executable, satisfies R9): An intent-changing upstream
  change produced by AC8.2 routes to an actionable escalation surface
  visible to the operator before the next commit lands. The escalation
  surface's identity is whatever DESIGN chose; AC9.1 verifies the routing
  fires.
- [ ] **AC10.1** (grep-checkable, satisfies R10): The `ci_monitor` step
  body in `skills/work-on/koto-templates/work-on-plan.md` contains an
  explicit branch for the suppressed-checks case (DIRTY mergeStateStatus
  detection, zero-checks-after-timeout detection, or the DESIGN-chosen
  equivalent).
- [ ] **AC11.1** (executable, satisfies R11): A test fixture that creates
  a PR with `mergeStateStatus=DIRTY` (no workflow runs) running through
  the `ci_monitor` step produces an actionable escalation rather than
  indefinite wait, verifiable within a bounded test duration.

### Sweep-level criteria

- [ ] **AC12.1** (judgment-based, satisfies R12): DESIGN's body
  enumerates all surfaces touched outside the three named bugs and the
  reviewer agrees each touch is justified by a named fix.
- [ ] **AC13.1** (judgment-based, satisfies R13): The PRs that ship the
  fixes can be reviewed and merged in any order (DESIGN documents the
  independence; reviewer verifies no commit references "depends on PR for
  bug N" as a precondition).

## Out of Scope

- **Solution mechanism per bug.** The issues enumerate fix candidates
  (parser loosening vs. warning vs. validator check for #156;
  auto-transition vs. documented contract vs. sentinel-gated transition
  for #159; full worktree-discipline vs. operator-rebase doc vs.
  ci_monitor fix for #162). DESIGN picks one option per bug; this PRD
  binds the contracts, not the mechanisms.
- **Other open shirabe issues from the same dogfooding window:**
  tsukumogami/shirabe#155, #157, #158, #160, #161, #163, #164. Each is
  tracked as its own work stream. They are excluded from this sweep
  because their failure shapes don't match the "catastrophic-by-default,
  silent-by-default on a routine path" rubric (they are loud-not-silent,
  edge-case-not-routine, or ergonomics-not-catastrophic).
- **Broader pattern-v1 ergonomics work.** The larger workflow refactor
  the dogfooding surfaced is roadmap-altitude territory (SE12). It is
  not in this PRD's frame.
- **Refactoring of `plan-to-tasks.sh`, the status-gate framework, or
  `/work-on`'s orchestrator beyond what each fix needs.** R12 binds this
  constraint as a non-functional requirement; the Out of Scope entry is
  here for emphasis.
- **A consolidated escalation surface across R9 and R11.** DESIGN MAY
  choose to share one surface or use two; the PRD does not require either.
- **Backfilling existing PLANs with corrected `**Dependencies**:` lines.**
  R1 makes the parser tolerant of both placements; existing PLANs do not
  need to be edited.

## Known Limitations

- The sweep does not change the broader pattern-v1 contract surface.
  Operators continue to invoke the three child skills and the `/scope`
  parent the same way; the silent-failure modes close but the surface
  area for new silent-failure modes (in other parts of pattern v1)
  remains.
- R6 leaves the direct-invocation case as a hard-stop. Operators who
  invoke `/design` directly against a Draft PRD will continue to hit the
  Phase 0 stop. This is deliberate: the silent-failure shape #159 names
  is the parent-chain case, not the direct-invocation case.
- The `ci_monitor` fix in R10/R11 binds the surface to a specific signal
  shape (DIRTY-or-equivalent zero-checks-after-timeout). If GitHub
  introduces a new merge-state classification that also suppresses
  workflow runs, the contract may need extension.

## Decisions and Trade-offs

**D1: Sweep as a unit vs. three independent PRDs.** Decided: one PRD
covering all three bugs. Alternative considered: three separate
single-bug PRDs. The single-PRD choice won because the BRIEF carries the
unifying "catastrophic-by-default, silent-by-default" failure shape and
treating the bugs as a sweep keeps DESIGN honest about that shared frame.
Three independent PRDs would have re-derived the shape three times or
omitted it entirely.

**D2: Mechanism-deferred requirements vs. mechanism-bound requirements.**
Decided: mechanism-deferred for every requirement. Alternative
considered: pick the issue-body's "(a)" candidate for each bug and bind
the PRD to it. The deferred choice won because the issue bodies
explicitly note the implementer should weigh the candidates and DESIGN's
role is exactly that weighing; binding the PRD to candidates would
collapse the DESIGN phase to a no-op.

**D3: Splitting R8/R9 from R10/R11 (worktree-discipline vs.
ci_monitor).** Decided: two separate requirement pairs, both in scope.
Alternative considered: bind only the worktree-discipline surface
(R8/R9) and scope ci_monitor out to a separate follow-up. The both-in
choice won because the failure shape only fully closes when both
surfaces are bound — fixing only one leaves the operator with either
"caught upstream change but CI still silently waits" or "CI escalation
fires but the upstream change wasn't classified earlier when it could
have been escalated."

**D4: AC granularity.** Decided: each AC binds to a single requirement
clause and is labeled grep-checkable, executable, or judgment-based.
Alternative considered: write higher-level "the feature works end-to-end"
ACs and leave verification surface up to DESIGN. The labelled-per-clause
choice won because R12/R13 already constrain the verification surface
(grep-checkable where possible, executable for runtime behavior); making
the labels explicit lets the jury and the eventual reviewer agree on
what each AC commits to.

**D5: schema field set to `prd/v1`.** Decided: include
`schema: prd/v1` as the first frontmatter field. Phase 2 research
confirmed the v0.9.1-dev validator's `check_schema` emits a SCHEMA notice
and stops running downstream FC checks against PRDs without it; this is
the same silent-skip behavior #157 named for the v0.7.0 era, preserved
in the Rust cutover. Omitting the field passes `shirabe validate`
overall (notice-level only) but the downstream FC checks the chain
relies on never run. The decision is procedural and not a
contract on the bugs themselves.

## References

- BRIEF: `docs/briefs/BRIEF-shirabe-pattern-v1-workflow-friction.md`
- tsukumogami/shirabe#156 — `plan-to-tasks.sh` single-pr parser drops
  dependency edges when colon is inside bold markers.
- tsukumogami/shirabe#159 — `/design` and `/plan` chain-handoff status
  gates are asymmetric with `/prd`'s brief-handoff.
- tsukumogami/shirabe#162 — `/work-on` doesn't check upstream main
  between commits, allowing DESIGN staleness mid-chain.
