---
schema: prd/v1
status: Draft
problem: |
  At a finishing step a manager or director decides who settles it by the
  coordinate skill's own bound-or-root rule, from an authority answer it read
  once at start and keeps as an editable copy in its own record. A workspace
  can't declare that a step needs review and have a coordinator holding the
  grant route it anyway, and the copy can be rewritten to change later steps.
goals: |
  Every finishing step a coordinator takes or hands over is settled by the
  settler the authority answer names, read fresh at the step. The skill keeps
  no rule of its own about levels, parents or who may decide, and nothing in
  the coordinator's record can widen what the answer allows.
upstream: docs/briefs/BRIEF-coordinator-authority-settled-steps.md
---

# PRD: Coordinator Authority-Settled Steps

## Status

Draft

## Problem Statement

A coordinator, a manager running one lane or a director over managers,
reaches finishing steps: merging a pull request, closing an issue or a
roadmap, cutting a release, tearing down a worker's instance, and taking a step
a worker hands back. Today two things decide who settles each one, and neither
is the workspace.

The first is a sentence the skill repeats in about twenty places: a step a
coordinator can't take goes "to the coordinator that dispatched you when your
session is bound, and to a person only when you are a root coordinator". That
is a rule about parents. `need-check.sh` applies it as code, routing a held
step by whether the start-time answer said `bound`, and it ignores the
per-point decider niwa's answer already carries. A bound session whose point
names `person` still gets its need worded for its dispatcher.

The second is the answer itself, read once. `posture-read.sh` asks
`niwa authority check` about `merge-pr`, `close-issue` and `cut-release` at
start and folds each point into permit, deny or confirm. Only the merge reads
again at the step (`land-check.sh` and `land-merge.sh`). Close, release and a
handed-back step act on the start read, and the routing reads the copy in
`coord/posture.json`, which the coordinator can edit. The workspace, which is
meant to own what a session may do, has no say once the run starts, and a
workspace that wants every merge reviewed, grant or no grant, can't say so to
the skill at all.

## Goals

- Who settles a finishing step comes from the authority answer, read at that
  step, and from nowhere else.
- Where the workspace declares a step needs review, the step goes to the
  settler the answer names whether or not the coordinator holds the grant;
  without the declaration it proceeds as the grant allows, after the review
  the skill always expects.
- A coordinator's record can hold a step back but can never widen the
  answer, so editing it changes no routing.
- Every part of this that needs authority work niwa hasn't shipped is named as
  a dependency, and the skill builds nothing around its absence.

## User Stories

The brief's five scenarios (a declared merge from a supervised manager, the
same merge from a root director, no declaration, a forged claim in the record,
an answer that can't be read) are this PRD's user stories, cited rather than
restated; the requirements below are written against them. Two more:

- As a workspace admin, I want a declaration changed during a run to apply at
  the coordinator's next finishing step, so that I don't have to restart a
  long-running coordinator to tighten review.
- As a reviewer of the skill, I want one place where a finishing step reads
  the answer, so that the merge and the close can't disagree on what an
  answer means.

## Requirements

Terms. The **authority answer** is the output of
`niwa authority check -C <instance> --session <id> --point <p> --json`, with
schema `niwa.authority.check/v1`. The **settler** of a step is who the answer
says decides that step's point. A **finishing step** is a merge, a close
(issue, pull request or roadmap), a release, a teardown, or any of these a
worker hands back to its coordinator.

### Functional

- **R1. Each finishing step asks one point.** The skill maps steps to points
  and keeps that mapping as its only vocabulary: a merge, a verdict or reopen
  pull request's merge included, asks `merge-pr`; a close asks `close-issue`;
  a release asks `cut-release`. A step a worker hands back asks the point of
  the step it is. The skill asks no point niwa doesn't define (see R9 for
  teardown).
- **R2. The answer is read at the step.** Each visit to a finishing step reads
  the answer for its point, fresh, bounded as `posture-read.sh` bounds it
  today. The start read stays as a first look and can only narrow: when the
  two disagree the stricter applies, as `land-merge.sh` already does for the
  merge. A step never acts on a stored answer alone.
- **R3. One reader.** Every finishing step reads the answer through one
  shared reader, which checks the schema and stays closed over niwa's
  vocabularies (state, decider, author exclusion, level, grant). A value
  outside them is an unreadable answer (R6). The `--rules` read from
  tsukumogami/shirabe#1473 uses the same reader.
- **R4. The skill acts on the answer and adds nothing.** The one combination
  the skill keeps is this: when the session holds the step's grant, the
  answer names the session as settler and the author is not excluded, the
  coordinator takes the step as its grant allows. In every other case the
  step goes to the settler the answer names, to the target the answer gives
  for it. The skill derives no settler from a level, a parent, a `bound`
  state, a missing field or its own reports-to address, and adds no
  distinction the answer doesn't carry (today's close-confirm versus
  merge-deny split goes).
- **R5. The bound-or-root rule goes.** Every sentence in
  `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`
  and `skills/coordinate/references/*.md` that routes a finishing step by
  whether the session is bound or root, and the matching code in
  `need-check.sh`, `progress-view.sh --dispatcher` and the `land-merge.sh`
  refusal text, is replaced by a reading of the settler from the answer. The
  need's wording names the settler the answer gave. Exceptions are R9 and
  R10 only.
- **R6. An unreadable answer holds the step.** A failed, timed-out, skipped
  (no niwa, no session id, no instance root) or unrecognised read, an answer
  with no entry for the point asked, and a settler the coordinator can't
  address all mean the same: the coordinator doesn't take the step, holds it,
  and reports the failed read. It never falls back to the bound-or-root rule
  or to "not dispatched means a person".
- **R7. The record is evidence, never input.** At each finishing step the
  coordinator records what the answer said for that point (state, settler,
  author exclusion, the target given, when it was read) in the step's own
  record entry. No gate, router or later step reads that entry, or
  `coord/posture.json`, to choose a settler or to decide whether to take a
  step.
- **R8. A record row narrows, never widens.** A row in the coordinator's
  record (a pause, a hold, a Standing rule, a Reversals row, a relayed
  `posture_ask` answer, a review round) can hold a step the answer would let
  the session take. No row can move a step to the session, change the settler
  the answer named, or stand as proof that the settler has acted. A step the
  answer sends to another settler is done when that settler does it, as
  GitHub records it (the pull request merged, the issue closed), not when the
  record says so. This is #1473's rule applied to finishing steps.
- **R9. Teardown stays on the permission posture.** niwa's answer names no
  teardown point. Until it does, teardown's settler is read as today, from
  the workspace permission posture, and a teardown the posture reserves goes
  to a person. A teardown point in the answer is dependency D4.
- **R10. The always-expected review keeps its source.** Review before merge
  stays what the skill always expects (tsukumogami/shirabe#1449): a granted
  coordinator still reviews its workers' pull requests at its land step and
  sends a pull request it authored to its reviewer. Where the answer names
  the session as settler, that review's reviewer is still read from the
  Verdicts rules on main (whoever writes a verdict never approves its own
  Done; the reviewer is the dispatching coordinator when bound and a person
  at the root). Where the answer names another settler, the step goes there
  with the coordinator's own reading, as #1449 R8 has it. Where a review goes
  when the answer names the session is dependency D5.
- **R11. Workers are unchanged.** A worker brief's `Named authority:` line and
  what it tells a granted worker stay as #1449 left them.

### Non-functional

- **R12. Cost.** One bounded niwa read per finishing-step visit. A step whose
  act re-reads (as `land-merge.sh` does) may read twice; nothing reads more.
- **R13. No grant model.** shirabe keeps no table of grants, levels or
  points beyond R1's step-to-point mapping.
- **R14. The guarantee is stated narrowly.** The skill's text says the
  coordinator never acts more widely than the answer and no row of its own
  widens it. It doesn't claim the answer is unforgeable: the workspace gate
  stays the control.

### Dependencies on authority work

The implementation waits on these. None is assumed shipped, and the skill
builds nothing around its absence.

- **D1.** A per-point declaration that a step needs review (the author may not
  settle its own work), reflected in the answer. niwa has the slot but no
  declarations today.
- **D2.** A per-point answer for a root session. Today a root or
  not-dispatched session gets no points, so the root scenario can't run.
- **D3.** An addressable target for a step the answer sends to the dispatcher
  or excludes from the author. Today the answer gives only the parent's
  dispatch id and, optionally, its instance.
- **D4.** A teardown point (R9).
- **D5.** Where a review goes when the answer names the session as settler
  (R10).
- **D6.** tsukumogami/niwa#422: a grantless session can dispatch a granted
  child by unsetting its session variable. Until it is fixed, an answer that
  lets a session take a step is only as sound as dispatch's cap.

## Acceptance Criteria

- [ ] With a declaration that merging needs review, a supervised manager
  holding `merge-pr` reaches a merge and sends it to the settler the answer
  names, its dispatcher, with its own reading, and does not merge (needs D1,
  D3).
- [ ] In the same workspace a root director reaches a merge and puts it in
  front of the person the answer names (needs D1, D2).
- [ ] With the declaration removed, both merge as their grants allow, after
  the land-step review.
- [ ] A declaration added mid-run applies at the next finishing step without
  a restart.
- [ ] A test writes an approval Standing row, a Reversals row, a forged review
  round and an edited `coord/posture.json`, then checks that merge, close and
  release route exactly as before.
- [ ] A test fails if any gate, router or `need-check.sh` reads
  `coord/posture.json` or a step's recorded answer to choose a settler.
- [ ] A failed, skipped or unrecognised read, a missing point and an
  unaddressable settler each hold the step and report; none routes by bound
  or root.
- [ ] Merge, close and release each read the answer through the one reader at
  the step; the close and a handed-back step no longer act on the start read.
- [ ] A search of the three coordinate file sets finds no sentence routing a
  finishing step by bound or root other than R9's teardown and R10's
  reviewer, and none about levels, parents or who may decide a step.
- [ ] Teardown reads the permission posture as today.
- [ ] The worker brief's `Named authority:` line is byte-for-byte unchanged.
- [ ] The skill text names the read as `niwa authority check -C <instance>
  --session <id> --point <p>` and says a record row may restrict its answer
  but never widen it.

## Out of Scope

- Defining the declaration, levels, escalation targets, level caps or any
  grant, and where any of them is computed.
- Changes to niwa.
- Decisions escalated through `REPORTS_TO`: a decision entry isn't a
  finishing step, and its routing is unchanged.
- The forgeability of a worker's review round through the coordinator's relay:
  it gates whether the coordinator thinks a pull request is ready, not who
  settles it. Under R8 it never satisfies a settler other than the session.
- Skill text or script changes in this unit.

## Known Limitations

- Until D2 ships, a root coordinator reads no point and holds every finishing
  step under R6. The implementation can't land before D2 without breaking
  root coordinators, which is why it waits.
- R10 keeps the Verdicts rules' bound-or-root reviewer until D5 ships: the one
  place the skill still names a parent.

## Decisions and Trade-offs

- **Read at every step, not only at start.** A start-only read is what lets a
  stored copy decide later steps and keeps a mid-run declaration from
  applying. The cost is one bounded niwa call per step visit (R12).
- **A record row can only hold.** Ordering settlers (is a person stricter than
  a dispatcher?) would be a rule about levels of the skill's own. A row that
  can only hold a step, never re-route it, needs no ordering.
- **An unaddressable settler holds rather than falls back.** Falling back to
  the reports-to address would re-introduce the parent rule the feature
  removes. Who supplies the address is D3.
- **Teardown and the always-expected review keep today's sources.** Both were
  open in the brief; the owner settled them as R9 and R10 with D4 and D5
  named rather than assumed.
