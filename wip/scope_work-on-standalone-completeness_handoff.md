# /scope Handoff: work-on-standalone-completeness

## Provenance

Written by `/explore` on 2026-09-13 from
`wip/explore_work-on-standalone-completeness_crystallize.md`.
Research files: `wip/explore_work-on-standalone-completeness_findings.md`,
`wip/explore_work-on-standalone-completeness_decisions.md`,
`wip/explore_work-on-standalone-completeness_routing-options.md`, and
`wip/research/explore_work-on-standalone-completeness_r*_lead-*.md`.

Two discover-converge rounds. Round 1 ran eight leads and overturned two of the
six claims in the tracking issue; an adversarial review of round 1 found one
substantive hole, and round 2 ran two narrow leads to close it and to answer a
question round 1 had wrongly recorded as undeterminable. The author narrowed to
one of three candidate directions at the end of round 2.

## Problem Statement

A `/work-on` run invoked on its own opens a pull request and stops, leaving
whoever is supervising to supply the remaining steps from memory. The tracking
issue (tsukumogami/shirabe#361) attributes this to five capabilities living only
in `/execute`, but the code supports a narrower and different account: `/work-on`
is missing exactly one capability, the document-chain cascade, and carries most
of the others as prose in reference files rather than as koto states with
evidence gates. Prose is skippable and gated states are not, which is why three
separate worker sessions skipped steps that were written down and delivered to
them.

## Scope Boundary

### In scope

- Turning `/work-on`'s existing finishing obligations from prose into koto states
  with evidence gates.
- Adding document-chain cascade states to `/work-on`, positioned after
  `ci_monitor`.
- A shared cascade script both skills call, so the cascade logic is not
  duplicated even though the states are.
- A last-issue discriminator for multi-pr plans.
- A clean skip path for runs with no document chain.
- Keeping finalization out of `skills/work-on/SKILL.md`, which is loaded
  wholesale on direct invocation.

### Out of scope

- The `cannot_verify` definition-of-done gate. MEASURED as a per-repo
  configuration gap: of the five repos in this workspace only shirabe ships
  `.claude/shirabe-extensions/work-on.md` with a `## Verification map`. Both
  entry points run the same shared template state, so no boundary change alters
  exposure to it.
- The missing `check-staleness.sh` that `/work-on`'s `staleness_check` gate calls
  (`work-on.md:325`). Already recorded as an open question in
  `docs/plans/PLAN-work-on-friction-fixes.md:81`.
- Issue #87, filed 2026-04-28, which is the same PLAN-deletion and
  DESIGN-transition gap filed four months earlier and still open. It should be
  reconciled with this work rather than re-solved beside it.
- shirabe#360 (`--no-cleanup` on terminal `koto next`). Assigned to a separate
  worker: cheap, boundary-independent, already solved transferably by `/scope` at
  `skills/scope/references/phases/phase-4-cleanup.md:119-124`, and destroying
  context records today.
- shirabe#352 (no gate can observe whether a review panel ran). Deferred on
  purpose until this work settles which skill owns `/work-on`'s three panels, so
  the redesign is done once rather than twice. Note that the `/prd` and `/design`
  instances of the same defect sit outside both skills and no change here reaches
  them.
- The naming fossils left by the earlier split (five "work-on cascade" references
  in `skills/roadmap/SKILL.md`, three Rust doc comments, one citing a path that
  has never existed). Worth fixing alongside, but not the point of the work.

## Decisions Already Settled

From `wip/explore_work-on-standalone-completeness_decisions.md`:

- **The direction is chosen.** The author selected adding gated cascade states to
  `/work-on` over the tracking issue's two candidates (folding `/work-on` into
  `/execute`, or relocating `/execute`'s finishing states into `/work-on`). The
  deciding argument was the author's own: koto hands an agent only the current
  state's prose, so finalization states cost a `/work-on` child nothing unless it
  reaches them, and a child under `/execute` never does. This keeps finalization
  instructions out of the context of agents that will not use them.
- **The cascade logic is shared as a script, not duplicated.** A script is
  executed rather than read into context, so it costs a child nothing, and it is
  not what `DESIGN-execute-skill.md:98-104` rejected — that rejection was of a
  neutral shared *template*, on the grounds that it muddied single-issue
  legibility. How far the shared-script refactor goes is for the design hop.
- **Two of the tracking issue's six items are withdrawn.** `/work-on` never
  creates a draft PR, so there is nothing to ready; and it already carries
  `Fixes #N` and body conformance via
  `skills/work-on/references/phases/phase-6-pr.md:35` and the repo-root
  `references/pr-body-conformance.md`, which `/execute` also consumes.
- **The enforcement-altitude diagnosis replaces the location diagnosis.** The
  obligations mostly exist; what is missing is the evidence gate.
- **The multi-pr discriminator is a rebuild, not an invention.**
  `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md:176-178`
  already adopted posture detection by `execution_mode` plus open-issue count.
  The implementing code moved into `/execute` during PR #199, which excludes
  multi-pr, with no amendment recording the removal.
- **A cheaper discriminator shape has its own precedent.**
  `DECISION-multi-pr-posture-detection-2026-06-06.md:81` rejected inferring
  posture from the issues table — it "races with child PR merges" — in favour of
  an explicit author gesture at trivial cost.

## Coverage Notes

What the exploration did not answer and the chain should:

- **Which discriminator, and scoped to what.** The exploration established that a
  last-issue discriminator is needed and that two shapes have precedent; it did
  not choose between querying open issues and requiring a deliberate author
  gesture, and it did not settle whether the discriminator is scoped to the
  issue-tracked multi-pr shape that works today or waits on the separately
  flagged, currently unowned work of giving issueless multi-pr plans any driver
  at all.
- **What the no-chain skip path looks like.** A standalone issue-driven run may
  have no PLAN, DESIGN or BRIEF. The exploration identified the requirement but
  did not specify the behaviour, and did not establish how `run-cascade.sh`
  currently behaves against an absent or partial chain.
- **Whether multi-pr ROADMAP deletion has ever worked.**
  `skills/roadmap/SKILL.md:350` and
  `skills/plan/references/quality/plan-doc-structure.md:95` both state that the
  work-completing PR runs the cascade. Nothing implements it. Whether that is
  aspirational prose that has never been true, or a capability lost in PR #199,
  determines whether fixing it belongs here or is separately filable.
- **What merges a coordinated run's per-repo child PRs.** No `gh pr merge` was
  found anywhere in either skill. It appears to be left to a human, but that is
  nowhere stated.
- **Whether `/work-on` and `/execute` lacking a `team.yaml`** — which all seven
  authoring skills have — is a documented exception or a gap.
- **How much of the `/execute` finishing surface is genuinely per-plan.** The
  exploration classified capabilities but did not settle whether `pr_finalization`
  needs to keep a separate aggregating implementation for `/execute`'s shared PR
  once `/work-on` gains a per-change one.

## Upstream Observations

No ROADMAP exists in this repo (`docs/roadmaps/` is absent), so nothing travels
on `--upstream`.

The exploration read several upstream documents that the chain should know about.
`docs/designs/current/DESIGN-execute-skill.md` records the split that created
`/execute` out of `/work-on` and, at lines 98-104, the rejection of a shared
library for this exact machinery — the chain must answer that rejection rather
than re-propose it, and the shared-script refinement above is the argument that
it does not apply. `docs/designs/current/DESIGN-work-on-koto-unification.md` is
still `status: Current` even though the later design superseded its plan-mode
architecture, and neither frontmatter records the relationship; the actual state
has to be reconstructed from which files exist on disk. Two decision records bear
directly on the discriminator and are cited above.
`docs/plans/PLAN-work-on-friction-fixes.md` is `execution_mode: multi-pr` and
does not cover this work; its #80 is the separate `check-staleness.sh` defect.

## Framing-Shift Answer

**Pre-supplied answer:** yes, the framing shifted.

**Evidence:** The tracking issue frames the problem as five capabilities living
in the wrong skill. Round 1 established from the code that two of those five do
not exist as gaps at all, and that the remaining difference is one missing
capability plus a difference in enforcement altitude rather than in location.
That is a different problem statement, not a refinement of the original, and the
acceptance criteria in #361 rest on the superseded one. Round 2 then narrowed the
solution space further by establishing that koto delivers prose per state, which
made context placement rather than code ownership the deciding consideration for
the author.

## Shape Signals

### Architectural alternatives left open

- **The multi-pr last-issue discriminator.** Querying open issues via `gh` is
  buildable cheaply for plans with tracking level `issues` or
  `issues-and-milestone`, but is silent for issueless multi-pr plans and inherits
  a drift-and-race objection already recorded against a structurally similar
  check. A deliberate author gesture avoids the race entirely at trivial
  implementation cost, but shifts correctness onto an operator who can forget it.
  Re-deriving koto's `children-complete` inside `/work-on` is correct by
  construction but pulls multi-pr back toward the orchestrator architecture it
  was deliberately carved away from.
- **How far the shared cascade script goes.** Both skills calling one
  `run-cascade.sh` avoids duplicating cascade logic, but the two callers want
  different cadences and different chain postures. Whether that is one script
  with a posture argument, or a shared core with two thin wrappers, is open.
- **Whether `/execute` keeps an aggregating `pr_finalization`.** Its current one
  exists to assemble several children's outcomes into a single shared PR. Whether
  that survives unchanged, or shares machinery with `/work-on`'s per-change
  equivalent, is unsettled.

### Complexity signals

- The boundary between these two skills has moved once already (PR #199) and left
  inaccurate cross-references in shipped source, including one citing a path that
  has never existed. A second move needs to clean those up or add to them.
- Roughly 15 to 20 files across the repo are load-bearing on the current
  boundary: routing prose in four skills, a CI-enforced cross-skill path
  assertion, a merge gate whose comments name `/execute` specifically, and eval
  scenarios in four skills. The chosen direction touches fewer of these than
  either alternative, but not none.
- Two committed documents describe a multi-pr cascade capability that nothing
  implements, so the work includes reconciling documentation with reality rather
  than only adding code.
- koto templates have no include or inherit mechanism, so sharing is available
  only as a script or a prose reference. The repo's accepted pattern where true
  sharing is unavailable is deliberate duplication plus a CI drift check, already
  used between these two templates for the CI-gate expression
  (`work-on.md:789`, `execute.md:381`, guarded by
  `scripts/validate-template-mermaid.sh` check 4).
- The repo's own CLAUDE.md forbids a CLI subcommand that renders or creates an
  artifact body, which constrains any answer that proposes moving authoring logic
  into the binary.
