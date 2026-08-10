---
schema: prd/v1
status: Done
problem: |
  `/scope` declines to produce BRIEF, PRD, or DESIGN on gates that run before
  the artifact exists, so no gate can tell whether the artifact would have
  carried anything. The reader-economy reason for reducing the artifact set is
  documented only inside `/brief`, where it cannot fire when `/scope` drives,
  and the children `/scope` does run are all invoked in their cold-start input
  mode, so none of them ever consumes the upstream the chain just produced.
goals: |
  A `/scope` run always walks the whole tactical chain, BRIEF through PLAN,
  and reduces the artifact set only after the content exists and only where
  the surviving artifact demonstrably carries what the removed one held. No
  decision anywhere in the run is made before the artifact it is about. Each
  child consumes its upstream instead of re-deriving it, and the reader-facing
  reason for every reduction is documented where the reduction happens.
upstream: docs/briefs/BRIEF-scope-consolidation-over-skipping.md
---

# PRD: scope-consolidation-over-skipping

## Status

Done

Requirements for replacing `/scope`'s produce-or-skip gates with an entry-
altitude choice plus a post-hoc consolidation judgment. The DESIGN owns the
mechanism; this PRD owns what the mechanism must do.

## Problem Statement

`/scope` walks BRIEF to PRD to DESIGN to PLAN, and three of those four
children can be declined. Every declination is decided before the artifact
exists. `/brief`'s gate reads whether an Accepted BRIEF is already on disk.
`/prd`'s reads whether an Accepted PRD is. `/design`'s reads three structural
predicates over the PRD body — how many architectural alternatives it names,
whether it references a component the repo lacks, whether it carries a
Complex label. None of them reads the artifact whose existence they are
deciding, because that artifact has not been written. Whether a BRIEF would
have said something its PRD will not is not a question a gate can answer
before the BRIEF exists.

The declination was built to serve the reader. Three documents that restate
one problem at three altitudes cost three reads for one idea. That reason is
stated in exactly one file — `skills/brief/references/phases/phase-0-setup.md`,
which is explicit that folding "exists to avoid a redundant second document,
never to leave the framing unpersisted." At `/scope`'s own gate layer the
recorded reason is different and unrelated: `skills/scope/references/phases/phase-1-discovery.md`
says the auto-skip exists because "the parent MUST NOT silently overwrite an
Accepted durable artifact." That is protection against clobbering something
settled — a real concern that has nothing to do with what a reader has to
read. Two mechanisms share one name, and only the producer-facing one is
reachable.

Nothing moves when a child is declined. A `{name, reason}` entry lands in
`chain_skipped:` and the chain advances. There is no receiver anywhere: `/prd`
records an upstream BRIEF's path and bumps its status, but drafts its Problem
Statement, Goals, User Stories, and Out of Scope from its own scoping
conversation and never reads the brief's body.

Underneath both problems sits a mechanical cause. `/scope` invokes every
child as `/<child> <topic-slug>`. A bare slug is each child's cold-start
input mode: `/brief` treats it as a freeform topic and disposes of the
fold-into-PRD branch before reaching it; `/prd` treats it as Input Mode 3,
which by its own eval "does NOT invoke shirabe transition because there is
no BRIEF path to transition." So under `/scope`, a PRD written immediately
after a BRIEF does not record that BRIEF as its upstream, does not advance
it, and does not read it. The chain produces artifacts that are not linked
to each other and whose content is independently re-derived — which is
exactly the condition that makes them read as repetitive, and exactly the
condition that made skipping look like the fix.

The reader ends up worse off either way. When the chain runs in full, BRIEF
and PRD restate the same four things at roughly constant size, because four
of the BRIEF's five required sections are renamed PRD sections with
equivalent content rules. When the chain declines instead, whatever the
declined artifact would have held is never written and nobody learns what
was lost.

## Goals

- A `/scope` run writes every artifact in the tactical chain, BRIEF through
  PLAN. Nothing is dropped.
- Reducing the artifact set is the only mechanism that ends a run with fewer
  documents than the chain has altitudes, and it never runs before the
  documents it compares exist.
- Reducing the artifact set happens after the artifacts exist, on a reading
  of what they actually say, and only where the surviving document can be
  shown to carry what the removed one held.
- Each child consumes the upstream the chain just produced instead of
  re-deriving its framing, so the artifacts in a chain cite each other rather
  than repeat each other.
- Protection against overwriting a settled artifact survives, under its own
  name, clearly not a judgment about whether the artifact is worth having.
- Every reduction is legible after the fact: what was written, what was
  absorbed into what, and on what finding.

## User Stories

- As an author scoping a feature whose framing is contested, I want the
  chain to write the BRIEF and keep it once the PRD is done, so the framing
  work that drove the requirements stays readable on its own.
- As an author scoping a feature whose framing is two uncontested paragraphs,
  I want that framing written down properly once and then carried into the
  PRD, so I end with one document instead of two that say the same thing.
- As an author whose conversation is already at the architecture, I want to
  reach for `/design` directly rather than have `/scope` guess that my
  framing does not need writing down, so the choice to skip an altitude is
  mine and visible in what I typed.
- As a reader landing cold on a PRD months later, I want the problem stated
  in the PRD itself and everything else cited rather than re-narrated, so I
  can understand the feature without hunting for a document that no longer
  exists and without reading the same paragraph three times.
- As a reviewer reading the PR for a `/scope` run, I want to tell whether a
  missing artifact reflects a decision about content or a machine declining
  to write it, so I know whether to ask for it.
- As a maintainer of `/scope`, I want the reason each reduction exists
  recorded where the reduction is implemented, so the next person changing
  the gates does not have to infer intent from a neighbouring skill.

## Requirements

### Functional

**R1.** `/scope` SHALL invoke every child in the tactical chain, `/brief`
then `/prd` then `/design` then `/plan`, on every run. There is no altitude
at which the chain starts other than `/brief`, and no author-supplied or
computed value selects one.

**R2.** `/scope` SHALL NOT decide, at any point, whether an artifact is worth
producing. Every decision that reduces the artifact set SHALL be made after
the artifacts it compares have been written. An author who wants a chain that
starts above `/brief` reaches for `/design` or `/plan` directly; that choice
is theirs and is visible in what they invoked, and `/scope` does not make it
on their behalf.

**R3.** The R6 predicates that currently gate `/design` SHALL size
`/design`'s decision roster and SHALL NOT decide whether `/design` is
invoked.

**R4.** A child SHALL still be skipped when its durable artifact already
exists at a settled status at the canonical path. This protection SHALL be
named and documented as re-entry protection against overwriting a settled
artifact, distinct from any judgment about whether the artifact is worth
producing, and its recorded reason SHALL say so.

**R5.** `/scope` SHALL invoke each child through whichever of that child's
existing input modes carries the upstream the chain has produced: a child
whose upstream artifact exists in this chain is invoked with that artifact's
path, and only a child with no produced upstream is invoked with the topic
slug. This SHALL NOT add a flag, an argument, an environment variable, or a
new parse branch to any child.

**R6.** A PRD written from a BRIEF SHALL read that BRIEF's body and carry its
framing forward, rather than re-deriving the problem, outcome, journeys, and
scope boundary from the PRD's own scoping conversation.

**R7.** After each artifact lands, `/scope` SHALL run a consolidation
judgment comparing the artifact just written against the nearest surviving
durable artifact above it in the same chain. The judgment SHALL read both
bodies.

**R8.** The judgment SHALL reach one of two verdicts: `keep`, leaving both
artifacts in place, or `absorb`, in which the upstream artifact's durable
content is confirmed present in the downstream artifact and the upstream
artifact is then removed.

**R9.** `absorb` SHALL be available only at a hop where the downstream
artifact type's required sections provide a home for every required section
of the upstream type, so absorption never has to discard content or grow a
schema to hold it. Where no such mapping exists, the judgment's only
available verdict is `keep`.

**R10.** Before an `absorb` completes, `/scope` SHALL verify section by
section that the surviving artifact carries each of the absorbed artifact's
required-section concerns, and SHALL abort the absorb — leaving both
artifacts in place — if any is missing.

**R11.** When an artifact is absorbed, every `upstream:` reference to it
SHALL be re-pointed to the absorbed artifact's own upstream, or omitted when
it had none, per the settled rule that an upstream points at the nearest
artifact actually produced above it.

**R12.** `shirabe validate` SHALL report an `upstream:` value that does not
resolve to a tracked file in the repository, so a re-point that was missed
fails mechanically rather than silently.

**R13.** `/scope` SHALL record, for each hop, which artifacts were produced,
which were absorbed, into what, and the finding the verdict rested on. The
record SHALL survive into the run's durable output, not only into `wip/`.

**R14.** A `/scope` full-run SHALL leave at least one durable artifact.
This follows from R9 rather than needing its own guard: the PLAN is deleted
once its work is implemented, and no hop above BRIEF-to-PRD is absorbable, so
a run can never reduce below a surviving PRD, DESIGN and PLAN. A run that
leaves no durable artifact is not reachable through `/scope` at all.

**R15.** Each artifact SHALL state its own problem in full and SHALL cite,
rather than re-narrate, everything else its upstream already says. The
standalone-readability rule is satisfied by the problem statement; it does
not license restating requirements, journeys, or decisions the upstream
holds.

**R16.** The reader-facing reason for reducing the artifact set SHALL be
documented at the layer that implements the reduction — `/scope`'s own phase
references — and not only in a child skill.

**R17.** A child invoked directly, outside `/scope`, SHALL behave exactly as
it does today. No consolidation judgment fires and no state is written for a
run `/scope` did not orchestrate.

### Non-functional

**R18.** No new gate shape SHALL be introduced. Every child-invocation gate
SHALL bind to one of the three shapes already in the parent-skill vocabulary.

**R19.** No new artifact type and no per-type schema variant SHALL be
introduced. A consolidated artifact SHALL satisfy the same format contract as
an unconsolidated one of its type.

**R20.** Every author-facing decision point added or changed SHALL reach a
conclusion and mark one option recommended, grounded in stated findings, with
the human able to override outside `--auto`.

**R21.** Evals SHALL be created or updated for every skill whose behavior
changes, and run for those suites only.

## Acceptance Criteria

- [ ] AC1. Running `/scope <topic>` on a cold start produces a BRIEF, a PRD,
      a DESIGN, and a PLAN, with no child recorded in `chain_skipped:` for a
      worth-producing reason.
- [ ] AC2. `planned_chain:` is `[brief, prd, design, plan]` on every run,
      minus only children held back by re-entry protection. No state field
      and no prompt selects a starting altitude.
- [ ] AC3. `/scope`'s phase references and SKILL.md contain no decision that
      reduces the artifact set before the artifacts exist. Every such
      decision is the Phase 2 consolidation judgment.
- [ ] AC4. The two artifact-set outcomes reachable through `/scope` are the
      full chain and the chain minus an absorbed BRIEF. Reaching a chain that
      starts above `/brief` requires invoking `/design` or `/plan` directly,
      and `/scope`'s prose says so.
- [ ] AC5. `/scope`'s phase references no longer contain a gate that declines
      `/design` on the R6 predicates; the predicates appear only as the
      sizing input to `/design`'s decision roster.
- [ ] AC6. A `chain_skipped:` entry produced by R4 carries a reason naming
      re-entry protection against overwriting a settled artifact, and the
      surrounding prose distinguishes it from a worth-producing judgment.
- [ ] AC7. With a BRIEF produced in the same chain, `/scope` invokes `/prd`
      with the BRIEF's path, and the resulting PRD carries
      `upstream: docs/briefs/BRIEF-<topic>.md`.
- [ ] AC8. With a PRD produced in the same chain, `/scope` invokes `/design`
      with the PRD's path; with a DESIGN produced, it invokes `/plan` with
      the DESIGN's path.
- [ ] AC9. No child's input-mode list, flag set, or environment-variable
      consumption grows as a result of AC7 and AC8.
- [ ] AC10. `/prd`'s drafting phase instructs the author to draw the Problem
      Statement, Goals, User Stories, and Out of Scope from the upstream
      BRIEF when one exists, rather than from the PRD's own conversation.
- [ ] AC11. After the PRD lands in a chain that produced a BRIEF, `/scope`
      runs the consolidation judgment and records a `keep` or `absorb`
      verdict with the finding behind it.
- [ ] AC12. On `absorb`, the BRIEF is deleted, the PRD's `upstream:` is
      re-pointed to the BRIEF's upstream or omitted, and the PRD still
      passes `shirabe validate` clean.
- [ ] AC13. On `absorb`, a per-section carry check is recorded showing where
      each of the BRIEF's four content sections landed in the PRD.
- [ ] AC14. An absorb attempted where the surviving artifact is missing one
      of the upstream's concerns aborts, leaves both artifacts in place, and
      records why.
- [ ] AC15. The consolidation judgment offers only `keep` at the PRD-to-
      DESIGN and DESIGN-to-PLAN hops, and the reason — no home in the
      downstream type's required sections — is stated where the judgment is
      documented.
- [ ] AC16. `shirabe validate` on a doc whose `upstream:` names a path not
      tracked in the repository reports an error-severity finding; the same
      doc with a resolving `upstream:` is clean.
- [ ] AC17. The run's durable output names every artifact produced and every
      artifact absorbed, so a reviewer reading only the PR can tell the
      difference between "not produced" and "absorbed."
- [ ] AC18. `/scope`'s phase references state the reader-facing reason for
      reducing the artifact set, in their own prose, without deferring to
      `/brief` for the rationale.
- [ ] AC19. Invoking `/brief`, `/prd`, `/design`, or `/plan` directly with no
      `/scope` state file present produces no consolidation judgment and
      writes no `/scope` state.
- [ ] AC20. `references/parent-skill-pattern.md` still names exactly three
      gate shapes after the change.
- [ ] AC21. `crates/shirabe-validate/src/formats.rs` gains no new format
      profile and no per-type required-sections variant.
- [ ] AC22. `cargo test --workspace` passes and `shirabe validate` is clean
      over every changed document.
- [ ] AC23. Evals exist and pass for `/scope` and for every child skill whose
      behavior changed.

## Out of Scope

- `/charter` and the strategic chain. The DESIGN states in prose whether the
  model is intended to generalize to VISION to STRATEGY to ROADMAP; no
  strategic-chain behavior changes here.
- Renaming or re-scoping the artifact types themselves. R9 deliberately
  derives absorbability from the existing schemas rather than reshaping them.
- Un-absorbing a consolidated artifact as a supported operation. The commit
  history is the recovery path.
- Retrofitting BRIEF/PRD pairs already on disk. The change applies to runs
  from here forward.
- The README rewrite and the eval-harness work tracked separately.
- Growing the `upstream:` convention. R11 applies the rule already settled:
  nearest artifact actually produced, omitted when none was.
- Adding a fourth gate shape, a consolidated-document schema, or a CLI
  subcommand that renders an artifact body.

## Decisions and Trade-offs

**Consolidation and consumption are both needed; they are not alternatives.**
The upstream BRIEF asked whether the BRIEF-to-PRD overlap should be answered
by consolidating instances or by making `/prd` consume the BRIEF. Consumption
alone leaves two documents saying the same four things, which is the reader's
actual complaint. Consolidation alone would try to absorb a BRIEF into a PRD
that was written without reading it, so the carry check in R10 would fail
most of the time. Consumption is what makes absorption reliably available;
absorption is what removes the second document. R6 and R7 ship together.

**One mechanism reduces the set, and it runs after the fact.** An earlier
revision of this PRD gave `/scope` an entry altitude chosen once in Phase 1,
on the reasoning that a question about the conversation an author is having
is answerable when a question about an unwritten document is not. It was
rejected: it is still a decision that shrinks the artifact set before any
artifact exists, which is the exact shape this feature removes, and having
two reduction mechanisms operating at different times made neither one
legible. `/scope` now walks the whole chain and the consolidation judgment
is the only thing that removes a document.

The cost is that two of the four artifact-set outcomes are no longer
reachable through `/scope`. Because no hop above BRIEF-to-PRD is absorbable
(R9), a `/scope` run ends with either all four artifacts or the chain minus
an absorbed BRIEF. A DESIGN-and-PLAN run, or a PLAN alone, is reached by
invoking `/design` or `/plan` directly — which the pipeline already supports
and CLAUDE.md already documents, and which puts the choice in what the author
typed rather than in a judgment `/scope` makes for them.

**Absorbability is derived, not enumerated.** R9 states the rule in terms of
whether the downstream type's required sections have a home for the
upstream's. Applied to the current schemas that yields exactly one absorbable
hop, BRIEF to PRD: problem to Problem Statement, outcome to Goals, journeys
to User Stories, boundary to Out of Scope. PRD to DESIGN has no home for
requirements or acceptance criteria; DESIGN to PLAN has none for decisions or
architecture. Stating the rule rather than the answer means the set changes
correctly if a schema ever does.

**A run must leave something durable.** R14 forbids reducing to a PLAN alone
from an entry above `plan`, because the PLAN is deleted at implementation and
the run would leave no record of why the work happened. Entering at `plan` is
still allowed: an author who says the work needs no record beyond the code is
making a claim they are entitled to make, and the run says so out loud first.

**Re-entry protection stays, under its own name.** R4 keeps the behavior that
protects a settled artifact from being clobbered. The complaint was never
that this behavior is wrong; it was that its name and its recorded reason
made it look like a judgment about whether the artifact was worth writing.

**Verification is split.** R10's carry check is semantic and belongs to the
skill; R12's upstream-resolution check is structural and belongs to the
validator, matching the repository's rule that correctness checks live in
`shirabe validate` rather than in a renderer.

## Known Limitations

- The carry check in R10 is a judgment made by the same agent that wrote both
  artifacts. It is a real check against a written body rather than a guess
  about an unwritten one, which is the improvement being bought, but it is
  not independent.
- One absorbable hop is a thin surface for a rule stated in general terms.
  If no schema ever changes, R9's generality never pays off, and a reader may
  reasonably ask why the rule was not simply written as "BRIEF folds into
  PRD."
- A feature with no live architectural question still gets a DESIGN, because
  `/design` always runs and no hop above BRIEF-to-PRD can absorb it. The
  citation rule in R15 keeps that document short, and recording one live
  option and why no alternative was live is a better audit trail than
  silence, but it is a document that would not have existed before.
- Absorption runs in one direction, from an upstream artifact into the
  downstream one that replaced it. A thin DESIGN therefore has nowhere to go:
  its natural home would be the PRD above it, and folding backward is not a
  move this model has. If thin DESIGNs turn out to be common, that is the
  next question to open.
- Evidence for the constancy of BRIEF-to-PRD overlap comes from documents
  this same pipeline produced against these same format references. The
  overlap may be a property of the generator rather than of the feature
  space.
