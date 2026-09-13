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
- **Moving multi-pr execution into `/execute`.** Author decision, 2026-09-13:
  `/execute` is the skill for running a PLAN, one PR at a time, and people should
  not be invoking `/work-on` on a PLAN's individual issues. This inverts what is
  documented today and is expanded under its own heading below.
- A per-child "do not cascade" signal, replacing what would otherwise have been a
  last-issue discriminator (see below).
- A clean skip path for runs with no document chain.
- Keeping finalization out of `skills/work-on/SKILL.md`. This is a correctness
  constraint on the design, not a context-hygiene preference — see the section
  below.

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

## Where a fix may be written: a hard constraint

VERIFIED in koto's source. `init_child_core`
(koto `src/cli/init_child.rs:481-628`) seeds a child session by writing
`WorkflowInitialized` and `Transitioned` events straight from the compiled child
template. It builds no prompt and spawns no process. Separately, `koto next`
returns only the current state's `directive` and `details`
(koto `src/cli/next.rs:50-64`).

Two consequences the design hop must treat as constraints, not trivia:

1. **A child session never loads `SKILL.md` at all.** An obligation written into
   `skills/work-on/SKILL.md` is not merely skippable by a child — it is
   unreachable. A fix placed there would appear to work under direct invocation
   and silently not reach any `/execute` child, which is the hardest class of
   bug to notice: it fails only on the path nobody watches.
2. **Only `work-on.md` reaches both entry points** — its states, its gates, and
   its per-state prose. Reference files reach an agent when a state's prose tells
   it to read one, which is how the `Fixes #N` obligation reaches both paths
   today: `work-on.md:1180` cites `references/phases/phase-6-pr.md` from the
   `pr_creation` prose itself.

That second point is also why the diagnosis behind this work is about enforcement
and not about delivery. The `Fixes #N` instruction *was* delivered on both paths
and was skipped anyway. Writing an obligation in a reachable place is necessary
and not sufficient; what is missing is the evidence gate.

The practical test for any proposed change: name the file it lands in, and say
whether a `/work-on` child materialized by `/execute` would receive it.

## multi-pr moves into `/execute`

Author decision, 2026-09-13, taken after the direction was chosen and after this
handoff was first written. The intent: `/execute` is how a PLAN gets run, one PR
at a time, and `/work-on` should not be the thing a person points at a PLAN's
individual issues.

**This inverts what the repository currently says**, in at least six places
across three skills, two of them `description:` frontmatter that drives skill
triggering:

- `skills/execute/SKILL.md:48-49` — "`multi-pr` — out of scope for `/execute`;
  multi-pr plans run one issue at a time through `/work-on` ... Direct the user
  to `/work-on`."
- `skills/execute/SKILL.md:12` — frontmatter, "A `multi-pr` plan is the
  exception: those run through `/work-on` instead."
- `skills/work-on/SKILL.md:10` — frontmatter, "also runs a `multi-pr` PLAN, one
  issue at a time, each landing its own pull request."
- `skills/work-on/SKILL.md:137-141` — the multi-pr mode implementation.
- `skills/explore/SKILL.md:55` and `:70` — both routing tables name multi-pr as
  the exception that goes to `/work-on`.

Also affected: `/explore`'s crystallize framework states a candidacy
precondition that a multi-pr PLAN does not qualify for `/execute`
(`skills/explore/references/quality/crystallize-framework.md`), which this change
would reverse.

**What it buys, and it is substantial.** The hardest open question in this work
disappears. The exploration established that a last-issue discriminator was
needed because multi-pr runs inside `/work-on` with each issue landing its own
PR, so cascade states after `ci_monitor` would fire per issue; and that every
candidate discriminator carried a drift or race exposure, or required
re-deriving batch-completion machinery inside `/work-on`. With `/execute`
orchestrating multi-pr, the orchestrator already knows when the last child is
done — that is what its existing `children-complete` machinery is for — so the
cascade fires once, from `/execute`, exactly as it already does for single-pr.

The child then needs only to know **that it is a child**, not whether it is the
last one. That is a flag the orchestrator sets on dispatch, not a completion
query against GitHub or a PLAN table, so it is race-free and cheap. It is the
same shape as the existing `SHARED_BRANCH` signal, with one difference worth
flagging to the design hop: multi-pr children **do** create their own PRs and so
**do** reach `ci_monitor`, unlike single-pr children which take
`pr_status: shared` straight to `done`. The existing fork therefore does not
cover this case and a distinct signal is required.

It also gives an owner to a gap the exploration found unowned: issueless multi-pr
plans have no `/work-on` entry point today, and nobody is responsible for them.
Under this change `/execute` is.

**What it costs.** Routing prose, two frontmatter descriptions, the crystallize
precondition, and eval scenarios in several skills all have to change together,
and skill descriptions are what make a skill trigger, so they are part of the
contract rather than documentation. `/execute` grows a third execution path
alongside single-pr and coordinated. Anyone today invoking `/work-on` against a
multi-pr PLAN's issues is doing the documented thing and would need to be
redirected. Whether `/work-on` retains multi-pr as a mode for backward
compatibility, refuses it with a pointer to `/execute`, or drops it silently is
for the design hop — note that the earlier split rejected hard-removing
`/work-on`'s PLAN input because it "breaks existing invocations and `/work-on`'s
own evals", which is the same objection in the same place.

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

- **The per-child signal.** With multi-pr moving into `/execute`, the last-issue
  discriminator is replaced by a simpler need: a child must know it is a child so
  it does not cascade. multi-pr children reach `ci_monitor` (unlike single-pr
  children, which take `pr_status: shared` straight to `done`), so the existing
  fork does not cover them and a distinct signal is needed. Its shape is
  unsettled. The two discriminator precedents the exploration found
  (`DECISION-cascade-trigger-mechanism-2026-06-06.md:176-178` and
  `DECISION-multi-pr-posture-detection-2026-06-06.md:81`) are no longer the live
  question but remain useful context for how this repo has reasoned about
  posture signals before.
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

- **How `/work-on` treats a multi-pr PLAN once `/execute` owns that mode.**
  Retain it for backward compatibility, refuse it with a pointer to `/execute`,
  or drop it. The earlier split rejected hard-removing `/work-on`'s PLAN input
  because it "breaks existing invocations and `/work-on`'s own evals", which is
  the same objection in the same place.
- **The shape of the per-child "do not cascade" signal**, given that multi-pr
  children reach `ci_monitor` and single-pr children do not.
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
