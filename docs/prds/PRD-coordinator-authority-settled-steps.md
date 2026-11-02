---
schema: prd/v1
status: In Progress
problem: |
  At a finishing step a manager or director decides who settles it by the
  coordinate skill's own bound-or-root rule, from an authority answer it read
  once at start and keeps as an editable copy in its own record. A workspace
  can't declare that a step needs review and have a coordinator holding the
  grant route it anyway, and the copy can be rewritten to change later steps.
goals: |
  Every finishing step a coordinator takes or hands over is settled by the
  settler the authority answer names, read fresh at the step. Apart from
  teardown and the review before a merge, which keep today's sources until
  the authority work names a teardown point and where a review goes (R9,
  R10), the skill keeps no rule of its own about levels, parents or who may
  decide, and nothing in the coordinator's record can widen what the answer
  allows.
upstream: docs/briefs/BRIEF-coordinator-authority-settled-steps.md
---

# PRD: Coordinator Authority-Settled Steps

## Status

In Progress

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
  step, and from nowhere else. Teardown and the review before a merge keep
  today's sources until D4 and D5 ship (R9, R10); they are the only
  exceptions, and they are named as interim.
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
- As a reviewer of the skill, I want every finishing step to call the same
  script for the authority answer, so that the merge and the close can't
  disagree on what an answer means.

## Requirements

Terms. The **authority answer** is the output of
`niwa authority check -C <instance> --session <id> --point <p> --json`, with
schema `niwa.authority.check/v1`. The **settler** of a step is the decider the
answer gives for that step's point (`session`, `dispatcher` or `person`). A
**finishing step** is a merge, a close (issue, pull request or roadmap), a
release, a teardown, or any of these a worker hands back to its coordinator.
To **take** a step is for the coordinator to perform it itself; to **hold**
one is to not perform it, record it as held, and report (R6). This document
binds the later implementation; the unit that writes it changes no skill text
or script.

### Functional

- **R1. Each finishing step asks one point.** The skill keeps one
  step-to-point mapping and no other vocabulary of points: a merge, a verdict
  or reopen pull request's merge included, asks `merge-pr`; closing an issue,
  a pull request or a roadmap asks `close-issue`; a release asks
  `cut-release`. A step a worker hands back asks the point of the step it is,
  and a handed-back teardown follows R9. The skill asks no point niwa doesn't
  define.
- **R2. The answer is read at the step.** Each visit to a finishing step reads
  the answer for its point, fresh, bounded at `NIWA_LOOKUP_SECONDS` (3 seconds
  by default) as `posture-read.sh` bounds it today, and acts on that read in
  the same visit. A step whose act reads again (as `land-merge.sh` does for
  the merge) is held if either read holds it. The start read stays only for
  the board, the start report and teardown's interim settler (R9); no other
  step acts on it.
- **R3. One reader.** Every finishing step, and the `--rules` read from
  tsukumogami/shirabe#1473, gets the answer from one shared script, the only
  code in `skills/coordinate/` that runs `niwa authority check`. It accepts an
  answer only when it exits 0 with schema `niwa.authority.check/v1` and every
  `state`, `decider`, `author_exclusion`, `level` and grant value is one
  `posture-read.sh` accepts today. Anything else is an unreadable answer (R6).
- **R4. The skill acts on the answer and adds nothing.** The coordinator takes
  a step only when the answer says the session holds the step's grant, names
  `session` as settler and has author exclusion off; it then takes it after
  the review R10 keeps. In every other case the step goes to the settler the
  answer names, at the target the answer gives for it: when the settler is
  `dispatcher`, or the settler is `session` with author exclusion on, that
  target comes from the answer (D1, D3); when it is `person`, a person. The
  skill derives no settler from a level, a parent, a `bound` state, a missing
  field or its own reports-to address, and adds no distinction the answer
  doesn't carry: today's close-confirm versus merge-deny split goes.
- **R5. The bound-or-root rule goes.** Every sentence in
  `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`
  and `skills/coordinate/references/*.md` that routes a finishing step by
  whether the session is bound or root, and the matching code (the
  `grant_check.state` routing in `need-check.sh`, the `--dispatcher` wording in
  `progress-view.sh`, the "hand the merge to the human" refusal in
  `land-merge.sh`), is replaced by a reading of the settler from the answer.
  A held step's need names the settler the answer gave. The only exceptions
  are R9 and R10.
- **R6. An unreadable answer holds the step.** These hold the step: a read
  that fails, times out or is skipped (no niwa, no session id, no instance
  root); an answer R3 refuses; an answer with no entry for the point asked;
  a settler whose target the answer doesn't give; an answer that names the
  session as settler, with author exclusion off, without the grant; and a step whose command a Claude
  Code deny or ask rule covers, where the answer would let the session take
  it. The coordinator doesn't
  take the step, records it as held with the reason, and reports the step,
  its point and the reason where it sends its other reports. The report hands
  nothing over: the step stays held until a later read at the step names a
  settler. It never falls back to the bound-or-root rule or to "not
  dispatched means a person".
- **R7. The record is evidence, never input.** At each finishing step the
  coordinator writes what the read said for that point (step, point,
  state, settler, author exclusion, the target given, the read's time, and
  the verdict with its hold reason) into that step's entry
  in its own record (its koto session context). No gate, router or later step
  reads that entry, or `coord/posture.json`, to choose a settler or to decide
  whether to take a step, except teardown, whose interim settler R9 keeps on
  the permission posture in `coord/posture.json` until a teardown point is
  named. The entry has one reader: the coordinator's next
  start report lists each settle read written since the previous start (step,
  point, verdict, settler and hold reason), so a reviewer sees how each step
  was routed. The report shows the reads and decides nothing from them.
- **R8. A record row narrows, never widens.** A row in the coordinator's
  record (a pause, a hold, a Standing rule, a Reversals row, a relayed
  `posture_ask` answer, a review round) can hold a step the answer would let
  the session take. No row can let the session take a step R4 doesn't, change
  the settler or target the answer named, or stand as proof that another
  settler acted. A step sent to another settler counts as done only when
  GitHub records the result (the pull request merged, the issue closed, the
  release published), read from GitHub, never from the record. This is
  #1473's rule applied to finishing steps; it needs no ordering of settlers,
  because a row can only hold.
- **R9. Teardown waits for a teardown point.** niwa's answer names no
  teardown point. Until it does, teardown's settler is read as today, from the
  workspace permission posture, and a teardown the posture reserves goes to a
  person. That is interim, not teardown's lasting source: once the workspace
  authority work names a teardown point (dependency D4), teardown reads it at
  its step like every other finishing step.
- **R10. The always-expected review keeps its source.** Review before merge
  stays what the skill always expects (tsukumogami/shirabe#1449): a
  coordinator the answer lets take a merge still reviews its workers' pull
  requests at its land step and sends a pull request it authored to its
  reviewer first. That reviewer is still read from the Verdicts rules on main:
  whoever writes a verdict never approves its own Done; the reviewer is the
  dispatching coordinator when bound and a person at the root. Where the
  answer names another settler, the step goes there with the coordinator's
  own reading, as #1449 R8 has it. Where a review goes when the answer names
  the session is dependency D5.
- **R11. Workers are unchanged.** A worker brief's `Named authority:` line and
  what it tells a granted worker stay as #1449 left them.

### Non-functional

- **R12. Cost.** At most one niwa read per finishing-step visit, and two when
  the act reads again under R2.
- **R13. No grant model.** What a coordinator is expected to do is fixed in the
  skill; what it is allowed to do, who settles a step included, is configured
  per workspace and reaches the skill only through the authority answer. So
  shirabe keeps no table of grants, levels or settlers; R1's step-to-point
  mapping is its only table.
- **R14. The guarantee is stated narrowly.** `SKILL.md` says the coordinator
  never acts more widely than the answer and that no row of its own widens it,
  and makes no claim that the answer can't be forged: the workspace gate stays
  the control.

### Dependencies on authority work

The implementation waits on these. None is assumed shipped, and the skill
builds nothing around its absence. D1 to D5 belong to the workspace authority
work that makes the workspace's gates honour the authority a session was
dispatched with; this document needs each of them and assumes no shape for
any. D6 is a separate dispatch bug.

- **D1.** A per-point declaration that a step needs review (the author may not
  settle its own work), reflected in the answer. niwa has the slot but no
  declarations today.
- **D2.** A per-point answer for a root session. Today a root or
  not-dispatched session gets no points, so the root scenario can't run.
- **D3.** A target the coordinator can address for a step the answer sends to
  the dispatcher or excludes from the author. Today the answer gives only the
  parent's dispatch id and, optionally, its instance.
- **D4.** A teardown point (R9).
- **D5.** Where a review goes when the answer names the session as settler
  (R10).
- **D6.** tsukumogami/niwa#422: a grantless session can dispatch a granted
  child by unsetting its session variable. Until it is fixed, an answer that
  lets a session take a step is only as sound as dispatch's cap.

## Acceptance Criteria

Each criterion runs against a fake `niwa` first on PATH that prints a fixed
answer and logs its calls, as the #1473 engine suites do. "The same outcome"
means the same settler, the same held or taken result and the same need
wording as a run with the same fake answer and no record rows written.

- [ ] Declared merge, supervised: with the answer naming `dispatcher` for
  `merge-pr` and a target, a manager holding `merge-pr` sends the merge to
  that target with its own reading and runs no merge (D1, D3).
- [ ] Declared merge, root: with the answer naming `person`, a root director
  puts the merge in front of a person and runs no merge (D1, D2).
- [ ] No declaration: with `session`, exclusion off and the grant held, the
  coordinator merges after its land-step review; with the grant not held, it
  sends the merge to the settler the answer names, and holds it with reason
  `no-grant` when that settler is `session` with exclusion off.
- [ ] Excluded author: with `session` and exclusion on, the step goes to the
  target the answer gives, and is held when none is given.
- [ ] Mid-run change: the fake answer changes between two finishing steps of
  one run and the second step acts on the new answer.
- [ ] Read at the step: the fake niwa's log shows one `--point` read per visit
  to a merge, close, release and handed-back step (two for a merge whose act
  reads again), and none of them acts on the start read.
- [ ] Mapping: merge and verdict merges ask `merge-pr`; issue, pull request
  and roadmap closes ask `close-issue`; a release asks `cut-release`; no other
  point is asked.
- [ ] One reader: a search finds `niwa authority check` run from exactly one
  script under `skills/coordinate/`.
- [ ] Permission hold: with the answer letting the session take a merge,
  close or release and a Claude Code deny or ask rule covering the step's
  command, the step is held with reason `permission` and goes to no other
  settler.
- [ ] Refused answers: an unknown schema, `state`, `decider`, or
  `author_exclusion` value, and a non-zero exit, each hold the step.
- [ ] Holds: a timed-out read, a skipped read (no niwa; no session id; no
  instance root), an answer with no entry for the point and a settler with no
  target each hold the step, record the reason, send one report naming the
  step, point and reason, and route by neither bound nor root.
- [ ] Forged record: with an approval Standing row, a Reversals row, a relayed
  `posture_ask` answer, a forged review round and an edited
  `coord/posture.json` written, merge, close and release each have the same
  outcome.
- [ ] Record is evidence: each finishing step's entry holds state, settler,
  author exclusion, target and read time; a test fails if any gate, router or
  `need-check.sh` reads that entry or `coord/posture.json` to choose a settler
  or to take a step. The test allows two reads: the start report printing the
  entries, and teardown's interim read of `coord/posture.json` under R9.
- [ ] Routing shown: after a merge sent to the dispatcher and a close held
  for `no-grant`, the coordinator's next start report lists both reads with
  step, point, verdict, settler and reason; with the held close's entry edited
  from hold to take before that start, the report shows the edit and every
  transition is unchanged.
- [ ] Done is GitHub's: a step sent to another settler is marked done only
  after GitHub reports the pull request merged, the issue closed or the
  release published, and a record row claiming it is done changes nothing.
- [ ] Wording: `grep -nE 'session is bound|root coordinator|where you are
  bound|grant_check\.state|--dispatcher'` over the coordinate skill's text and
  scripts, tests aside, matches only R10's reviewer sentence. Teardown's
  passage says a teardown goes to a person and names neither bound nor root
  (R9). The Verdicts rules' chain for who merges a verdict pull request is
  replaced by the `merge-pr` read like every other merge; only the sentence
  naming the reviewer stays.
- [ ] Teardown: with the fake answer changed, teardown's outcome is unchanged
  and follows the permission posture.
- [ ] Review kept: a coordinator the answer lets merge still sends a pull
  request it authored to its R10 reviewer before merging.
- [ ] The worker brief's `Named authority:` line is byte-for-byte unchanged.
- [ ] `SKILL.md` names the read as `niwa authority check -C <instance>
  --session <id> --point <p>`, says a record row may restrict its answer but
  never widen it, and claims nothing about the answer being unforgeable.
- [ ] No new table: no file under `skills/coordinate/` maps levels, grants or
  settlers; the only mapping is R1's.

## Out of Scope

- Defining the declaration, levels, escalation targets, level caps or any
  grant, and where any of them is computed.
- Changes to niwa.
- A grant model in shirabe.
- Workers' own finishing steps (R11).
- Decisions escalated through `REPORTS_TO`: a decision entry isn't a
  finishing step, and its routing is unchanged.
- The forgeability of a worker's review round through the coordinator's relay:
  it gates whether the coordinator thinks a pull request is ready, not who
  settles it, and under R8 it never satisfies another settler.

## Known Limitations

- Until D2 ships, a root coordinator reads no point and holds every finishing
  step under R6. The implementation can't land before D2 without breaking
  root coordinators, which is why it waits.
- R10 keeps the Verdicts rules' bound-or-root reviewer until D5 ships: the one
  place the skill still names a parent.
- R9 keeps teardown's settler on the stored permission posture until D4 ships,
  so teardown doesn't read the answer at its step.
- Because of those two passages, this feature alone doesn't leave the skill
  with no rule of its own about levels, parents or who may decide a step. A
  reader after this change finds the answer read at every other finishing
  step, and those two passages named as interim. The rest is follow-up work
  once D4 and D5 ship.

## Decisions and Trade-offs

- **Read at every step, not only at start.** A start-only read is what lets a
  stored copy decide later steps and keeps a mid-run declaration from
  applying. The cost is one bounded niwa call per step visit (R12).
- **A record row can only hold.** Ordering settlers (is a person stricter than
  a dispatcher?) would be a rule about levels of the skill's own. A row that
  can only hold a step, never re-route it, needs no ordering.
- **An unaddressable settler holds rather than falls back.** Falling back to
  the reports-to address would bring back the parent rule the feature removes.
  Who supplies the address is D3.
- **Teardown and the always-expected review keep today's sources.** Both were
  open in the brief; R9 and R10 settle them on today's sources, with D4 and
  D5 named rather than assumed.
