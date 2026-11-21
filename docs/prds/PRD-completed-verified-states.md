---
schema: prd/v1
status: Accepted
problem: |
  On a milestone roadmap, Done is set only when a verified verdict's roadmap
  edit merges, so a milestone whose work has landed reads In progress until
  then. Readers can't see landed work, the coordinator holds dependents and its
  own successor behind a verdict owed, and the tools that decide whether a
  milestone is finished disagree with each other.
goals: |
  A new milestone roadmap schema shows, per milestone, Completed when its work
  lands and Verified when a non-delivering checker's verdict holds, each
  recorded by the coordinator in the same pass it learns of it. Dependents start on Completed, Verified keeps Done's strictness,
  every tool reads status through one shared definition, and existing roadmaps
  move over with a tool that shows what changes.
upstream: docs/briefs/BRIEF-completed-verified-states.md
---

# PRD: Completed and Verified milestone states

## Status

Accepted

## Problem Statement

A milestone roadmap (`roadmap/v2` or `roadmap/v3`) closes a milestone on a
verdict, not on a merge. When the milestone's last pull request merges, the
coordinator records that a verdict is owed and opens no roadmap edit, so the
milestone keeps reading In progress (or even Not started, since nothing writes
In progress on these roadmaps) until a checker who didn't deliver the work
judges it against each Evidence clause and a roadmap pull request carrying the
verdict merges. The gap is often hours and sometimes days, when an Evidence
clause needs a walkthrough.

Three groups pay for it. People reading a roadmap can't tell landed work from
work nobody has started, so progress looks stalled while work is landing.
Coordinators treat the gap as a block: a milestone with a verdict owed takes no
worker, its dependents stay blocked though the code they build on is already
on the default branch, and when a lane's only open unit is a verdict owed the
coordinator refuses even its own successor's brief. Maintainers of the tools
face several separate answers to "is this milestone finished?": the shell
roadmap reader accepts Done or Shipped, the Rust validator and populate accept
Done or Closed, populate treats Dropped as open while the coordinator's picker
treats it as finished, and a changes-needed verdict leaves Status untouched.
Adding a second finished state by editing each of those places would multiply
the disagreement.

The verdict rule itself is right: milestones marked Done when their work merged
failed their Evidence often enough to matter. The problem is that one status
word has to carry two facts, "the work landed" and "someone who didn't build it
checked it", that happen at different times.

## Goals

- A roadmap reader sees, for every milestone, whether its work has landed
  (Completed) and, separately, whether it has been verified (Verified), each
  recorded in the roadmap edit the coordinator opens or updates in the pass it
  learns of it, so the reader never has to read a pull request to know.
- A coordinator starts a milestone's dependents as soon as the milestone's work
  lands, and a pending verdict never stops the coordinator's own succession.
- Verified means what Done means today: a verified verdict from a checker who
  didn't deliver the work. A roadmap is finished only when every milestone is
  Verified or Dropped.
- Every shirabe tool answers status questions through one shared definition,
  so a later change to the status set, up to a workflow a workspace configures,
  doesn't require finding every reader again.
- A roadmap author moves an existing milestone roadmap onto the new states with
  a tool that shows every row it would change and why, before changing it.

## User Stories

- As a maintainer checking how far an initiative has got, I want landed
  milestones shown apart from verified ones and from unstarted ones, so that I
  can say what has shipped and where verification is owed without reading pull
  requests.
- As a coordinator that just merged a milestone's last pull request, I want the
  milestone treated as Completed and its dependents offered before my next pick,
  so that work continues while the verdict is pending and my successor starts
  normally.
- As a checker recording a verdict, I want a verified verdict to set Verified
  and a changes-needed verdict to send the milestone back to In progress with
  the dependents already dispatched named, so that the roadmap tells the truth
  either way.
- As a worker building a dependent milestone, I want the coordinator to name
  my milestone in a held-dependent line when the milestone my work depends on
  comes back changes needed, so that I know my base may change before I land
  on it.
- As a roadmap author with a roadmap written under the single Done, I want a
  migration that turns verdict-backed Done into Verified and claim-backed Done
  into Completed, shows me each change and its evidence first, and refuses a
  roadmap that is already finished, so that I can upgrade without hand-editing
  or losing history.
- As an operator running coordinators on several hosts, I want the release to
  tell me what to upgrade before any roadmap moves to the new schema, so that
  no coordinator misreads a migrated roadmap.
- As a shirabe maintainer, I want one definition of what each status means for
  dependencies, closing, delivery and rendering, so that the shell scripts, the
  validator and populate can't disagree about Dropped or about spellings again.

## Requirements

Terms used below. A **pass** is one iteration of the coordinator's loop, from
reading facts to its next pick. A milestone's work is **finished** when its last
pull request has merged, or, for a milestone with nothing to merge, when the
coordinator records the `landed` tick it records today for a unit that reports
its work done. A **verdict line** is a Progress line in the form the
coordinator's verdict step writes today: `- <date>: <milestone> -- verified`,
`-- verified with follow-ups` or `-- changes needed`, followed by the checker
and the entry. A milestone's **latest verdict line** is the last such line
naming it, in file order, in the roadmap's Progress section. A milestone **owes
a verdict** when it reads Completed and no verified or verified-with-follow-ups
verdict line names it after the line or edit that made it Completed. The
**record** is the coordinator's own run record, as today. A milestone is
**dispatched** when the record holds a worker for it.

### Functional

**Schema and statuses**

- **R1.** A new roadmap schema version, `roadmap/v4`, uses the `## Milestones`
  layout of `roadmap/v3`. Its milestone statuses are exactly Not started, In
  progress, Completed, Verified and Dropped. Done is not a valid milestone
  status on a `roadmap/v4` roadmap.
- **R2.** `roadmap/v1`, `roadmap/v2`, `roadmap/v3` and roadmaps with no
  `schema:` line keep their current statuses, layout and behaviour, measured by
  the validation result, the populate output and the coordinator's picks for
  each of shirabe's existing fixtures, which do not change. The one exception
  is R4's spelling change: a milestone reading Shipped or Closed is read as
  Done by every component.
- **R3.** `shirabe validate` on a `roadmap/v4` roadmap: accepts the five
  statuses; rejects any other milestone status (Done included) naming the
  milestone and the allowed set; rejects the roadmap when its own status is Done
  while any milestone is not Verified or Dropped, naming each such milestone;
  and rejects a milestone whose block Status and Progress table row disagree,
  naming both values. A Delivered line is not required for any status. Setting a roadmap's own status stays the author's edit, as today, and a
  roadmap whose milestones are all Dropped may read Done.

**One shared status definition**

- **R4.** shirabe defines, in one place, every milestone status of every
  roadmap schema with four properties: **satisfies** (a dependent's dependency
  on it is met), **closes** (it counts toward the roadmap being finished),
  **takes work** (the coordinator may dispatch delivery for it), and **renders**
  (its table cell and diagram class). For `roadmap/v4`:

  | Status | satisfies | closes | takes work | renders |
  |---|---|---|---|---|
  | Not started | no | no | yes | unstruck; `ready`, `blocked` or a Needs class, as today |
  | In progress | no | no | yes | unstruck; as Not started |
  | Completed | yes | no | no | unstruck; class `completed` |
  | Verified | yes | yes | no | struck; class `done` |
  | Dropped | no | yes | no | struck; class `dropped` |

  For `roadmap/v1`, `roadmap/v2`, `roadmap/v3` and schema-less roadmaps the
  definition records today's behaviour property by property: Done (and its
  accepted spellings Shipped and Closed) satisfies, closes, takes no work and
  renders struck with class `done`; Dropped does not satisfy, closes, takes no
  work and renders unstruck with no class change. Today's components disagree
  on Dropped only because each asks a different one of these questions, so
  recording the answer per property keeps each of them. They also disagree on
  spellings: the shell reader accepts Shipped, the Rust validator and populate
  accept Closed. The shared definition accepts all three everywhere; this is
  the one deliberate change to existing schemas.
- **R5.** Every shirabe component that asks about milestone status (validation,
  populate, the coordinator's roadmap reader, picker, dispatch check, closeout
  read and progress view) answers from the shared definition. No component
  compares a milestone status against a finished-status word itself.
- **R6.** The roadmap format reference documents the `roadmap/v4` statuses,
  the four-property table in R4, the transition table in R7, and the fields
  that may change in a milestone while its roadmap is Active (Status and
  Delivered by the coordinator; Outcome, Evidence and Left open only in a
  verdict's follow-ups or an author's amendment, as today).

**Transitions on a `roadmap/v4` roadmap**

- **R7.** Milestone status moves only as this table says:

  | From | To | Trigger |
  |---|---|---|
  | Not started, In progress | Completed | the milestone's work is finished |
  | Not started, In progress, Completed | Verified | a verified or verified-with-follow-ups verdict |
  | Not started, In progress, Completed | In progress | a changes-needed verdict |
  | Completed, Verified | In progress | the coordinator's reopen step, which today's coordinator runs when a clause of a milestone's Evidence is found failing |
  | any except Verified | Dropped | an author's edit with a reason, as today |

  Any other move is refused by the tool that would make it, naming the
  milestone, its status and the trigger. Verified does not wait on the
  milestone's dependencies.
- **R8.** When a milestone's work is finished, the coordinator treats it as
  Completed before its next pick: its dependents whose other dependencies are
  met become pickable, and the milestone takes no new delivery work.
- **R9.** In the same pass the coordinator records Completed and the finished
  work's pull requests in Delivered: in the roadmap edit it already has
  pending, or, when none is pending, in a new roadmap edit it opens.
- **R10.** A milestone that owes a verdict is a unit the picker offers to the
  coordinator's verdict step. Apart from refusing new delivery work for that
  milestone itself (R8), it is never a reason to refuse a dispatch for another
  milestone, a successor's brief, or a dependent.
- **R11.** A verdict keeps today's checker rule: it is refused when its checker
  is the session that delivered the work.
- **R12.** When a changes-needed verdict or a reopen moves a milestone to In
  progress, the coordinator prints one line per dependent that is dispatched,
  Completed or Verified, naming the dependent and the milestone, in the format
  the reopen path prints its held dependents today; dependents not yet
  dispatched stop being pickable until the milestone is Completed again.
- **R13.** Every roadmap edit that changes a milestone's status changes its
  block Status and its Progress table row together.
- **R14.** A coordinator taking up a `roadmap/v4` roadmap lists, as verdicts to
  give, every milestone that owes a verdict and that its record doesn't already
  list.

**What readers see**

- **R15.** Populate renders each `roadmap/v4` status as R4 says, and the
  dependency diagram of a `roadmap/v4` roadmap declares the `completed` and
  `dropped` classes beside today's classes.
- **R16.** The coordinator's progress view lists a Completed milestone in its
  own row with the status text `landed, verdict owed`, never as ready to
  assign, and a pull request whose head has passed its checks reads
  `checks passed, ready to merge` (with today's held and paused variants
  reworded to match) instead of using the word "verified".

**Migration**

- **R17.** `shirabe roadmap migrate <roadmap> [--dry-run]` moves a
  `roadmap/v3` or `roadmap/v2` roadmap to `roadmap/v4`. With `--dry-run` it
  writes nothing and prints one line per milestone, as
  `<milestone>: <old status> -> <new status> (<latest verdict line>)`, with
  `no verdict line` in the parentheses when there is none. Without it, it
  rewrites the file in place, all or nothing (a failed write leaves the
  original file), and prints the same lines.
- **R18.** The migration maps Done, Shipped and Closed to Verified when the
  latest verdict line for that milestone is verified or verified with
  follow-ups, and to Completed otherwise. Every other status is kept. It reads
  a verdict line naming `Feature N` as naming `Milestone N`, converts a
  `roadmap/v2` `## Features` layout to `## Milestones`, and writes each new
  status to the block and the Progress row.
- **R19.** The migration checks, in this order: a file already on `roadmap/v4`
  exits 0 printing `already roadmap/v4` and changes nothing; a `roadmap/v1` or
  schema-less file exits non-zero naming the schema; a roadmap whose own status
  is Done exits non-zero naming the reason; a milestone block it can't parse
  exits non-zero naming the milestone. Each refusal changes nothing.

### Non-functional

- **R20.** The release that adds `roadmap/v4` says, in its notes and in the
  format reference, to install it on every host that runs a coordinator before
  migrating any roadmap, because a coordinator from an earlier release reads a
  `roadmap/v4` roadmap as having no milestones.

## Acceptance Criteria

**Validation (R1, R3)**

- [ ] A `roadmap/v4` fixture with milestones at each of the five statuses passes
  `shirabe validate` with exit 0.
- [ ] The same fixture with one milestone at Done fails, and the message names
  that milestone and the five allowed statuses.
- [ ] A `roadmap/v4` fixture with status Done fails while one milestone reads
  Completed and another In progress, naming both; it passes once both read
  Verified or Dropped.
- [ ] A `roadmap/v4` fixture whose block reads Completed and whose Progress row
  reads In progress for the same milestone fails, naming both values.

**No change to existing schemas (R2)**

- [ ] For every `roadmap/v1`, `v2`, `v3` and schema-less roadmap fixture in
  shirabe's tests, validation output, populate output and the picker's output,
  captured on the default branch before the change, are byte-identical after
  it.
- [ ] A `roadmap/v3` fixture with one milestone at Shipped and one at Closed
  reads both as Done in validation, populate and the picker.

**Shared definition (R4, R5, R6)**

- [ ] For each status in R4's table and each existing-schema status, the shared
  definition's tests assert the four property values the table gives.
- [ ] A fixture where Milestone 2 depends only on a Dropped Milestone 1 shows
  Milestone 2 blocked in populate's output and not pickable in the picker's
  output, on `roadmap/v3` and on `roadmap/v4`.
- [ ] Running `git grep -nE "(==|=~|\bcase\b|starts_with|eq_ignore_ascii_case|test\().*(Done|Shipped|Closed|Completed|Verified)" -- skills crates`
  lists only lines in the shared definition and its tests, and lines that
  compare the status of a PLAN, PRD, DESIGN or BRIEF document rather than a
  roadmap milestone.
- [ ] The format reference has the R4 table, the R7 table and the list of
  fields that may change while a roadmap is Active.

**Coordinator behaviour (R7 to R14)**, each in coordinate's script test suite on
a `roadmap/v4` fixture where Milestone 2 depends on Milestone 1:

- [ ] After Milestone 1's last pull request merges, the picker's next output
  lists Milestone 2 as pickable, the dispatch check refuses a new worker for
  Milestone 1, and the roadmap edit pending at that point (or a new one, when
  none was pending) sets Milestone 1 to Completed in block and Progress row and
  lists the pull request in Delivered.
- [ ] With nothing to merge, recording the `landed` tick for Milestone 1 has the
  same three effects.
- [ ] Dispatching a successor brief while Milestone 1's verdict is owed exits 0,
  and the successor's picker output lists the owed verdict as a unit.
- [ ] A verified verdict sets Milestone 1 Verified; a verified-with-follow-ups
  verdict does the same and adds its follow-ups; a verified verdict on
  Milestone 2 sets it Verified while Milestone 1 is still Completed; a verified
  verdict on a Not started milestone sets it Verified.
- [ ] A verdict whose checker is the delivering session is refused.
- [ ] A changes-needed verdict on Completed Milestone 1, with Milestone 2
  dispatched, sets Milestone 1 In progress in block and row and prints one
  held-dependent line naming Milestone 2; with Milestone 2 not yet dispatched,
  the picker stops offering it.
- [ ] Reopening a Verified milestone, and reopening a Completed one, sets each
  In progress in block and row.
- [ ] Moving a Verified milestone to Dropped, or a Dropped milestone to any
  status, is refused naming the milestone and its status; moving a Completed
  milestone to Dropped with a reason is accepted.
- [ ] A changes-needed verdict on a Verified milestone, and a Not started to
  Completed move with no finished work, are each refused naming the milestone,
  its status and the trigger.
- [ ] A coordinator taking up a fixture with a Completed milestone and an empty
  record lists that milestone as a verdict to give.

**What readers see (R15, R16)**

- [ ] Populate on the five-status fixture renders the Completed row unstruck
  with class `completed`, its dependent with class `ready`, the Verified row
  struck with class `done`, the Dropped row struck with class `dropped`, and
  declares both new classes; `shirabe validate` passes on the result.
- [ ] The progress view on a record with a Completed milestone shows a row
  reading `landed, verdict owed` for it, and on a record with a passing pull
  request shows `checks passed, ready to merge`, a held one `checks passed;
  merge held by your direction` and a paused one `checks passed; held by pause
  <id>`; no line in the view's pull-request section contains the word
  "verified".

**Migration (R17 to R19)**

- [ ] `--dry-run` on a `roadmap/v3` fixture with Done milestones A, B and C,
  where A's latest verdict line is verified, B's is verified with follow-ups
  and C has none, prints A Verified, B Verified, C Completed with the verdict
  line or `no verdict line` for each, and the file's checksum is unchanged.
- [ ] Without `--dry-run`, the same fixture becomes `roadmap/v4` with those
  statuses in block and Progress row, every other status unchanged, and passes
  validation; a second run prints `already roadmap/v4`, exits 0 and changes
  nothing.
- [ ] A milestone whose latest verdict line is changes needed after an earlier
  verified one migrates to Completed.
- [ ] When the migration's write fails partway (the test makes the target
  read-only after the first write), the original file is unchanged.
- [ ] A `roadmap/v2` fixture with a `## Features` layout, a Shipped milestone and
  a verdict line naming `Feature 2` migrates to a `roadmap/v4` `## Milestones`
  layout with Milestone 2 Verified and the Shipped milestone mapped by its own
  verdict line.
- [ ] A `roadmap/v1` fixture, a schema-less fixture, a `roadmap/v3` fixture
  with status Done, and a fixture with an unparseable milestone block each exit
  non-zero with the reason R19 names, and each file's checksum is unchanged.

**Rollout (R20)**

- [ ] The format reference and the release notes of the release that adds
  `roadmap/v4` each state the install-before-migrate order.

## Out of Scope

- A status workflow a workspace or roadmap configures (its own states,
  transitions or approvals). The shared definition is the seam for it; building
  it is later work.
- Changing `roadmap/v1`, `roadmap/v2`, `roadmap/v3` or schema-less roadmaps,
  including giving them Completed. They gain the new states only by migrating.
- How verdicts are written, who may write or review them, or what an Evidence
  clause must say.
- Statuses of PLAN, PRD, DESIGN, BRIEF and issue documents.
- Limits on how many milestones may be in flight.
- Consumers outside shirabe that count statuses by name; they need their own
  change before they read a `roadmap/v4` roadmap.

## Known Limitations

- A shirabe release that predates `roadmap/v4` validates such a roadmap only
  with a skip notice, and its coordinator sees no milestones in it. The
  feature can't change released versions; R20's rollout order is the
  mitigation.
- A dependent started on a Completed milestone may need rework if that
  milestone's verdict comes back changes needed. R12 makes that visible; it
  doesn't prevent it.
- Recording Completed in the file adds roadmap edits. R9 folds it into the
  edit already pending when there is one, so the file lags the coordinator's
  own view only until that edit merges.
- A Dropped milestone does not satisfy its dependents' dependencies, as today,
  so dropping one still strands its dependents until they are amended.

## Decisions and Trade-offs

- **Keep the words Completed and Verified.** Verified matches the verdict names
  checkers already record. Accepted is the status of approved BRIEFs, PRDs and
  DESIGNs, and Confirmed is the coordinator's word for the step that confirms a
  roadmap edit, so each alternative collides with something closer. The one
  harmful collision, "verified" meaning a passing pull-request check in the
  progress view, is removed by R16.
- **Completed is written to the roadmap, not derived.** A derived Completed is
  invisible to anyone reading the file and to populate, which never reads the
  coordinator's record, and the migration has to write Completed for
  claim-backed rows anyway. The coordinator still acts at once (R8), so the
  roadmap edit costs latency in the file, not in the work.
- **In progress gets no new writer.** The coordinator already knows what it has
  dispatched. In progress is written only by the edits that already happen and
  need it: a changes-needed verdict and a reopen (R7, R12).
- **A new schema version, not new words on `roadmap/v3`.** Released validators
  fail unknown statuses on `roadmap/v3`, and released coordinators would read a
  Verified milestone there as open. On `roadmap/v4` the same releases skip or
  see nothing, which is quieter but leaves `roadmap/v3` roadmaps untouched for
  a fleet that hasn't upgraded.
- **Dependents start on Completed.** The alternative, only Verified unblocks,
  keeps today's waits. Rework when a dependency fails its verdict is accepted
  and made visible (R12).
- **Verified ignores dependencies.** A verdict judges a milestone's own
  Evidence. Holding a verified milestone behind an unverified dependency hides
  a true result; a dependency that later breaks a dependent's clause is a
  reopen.
- **Finished roadmaps aren't migrated.** Most milestones on an already finished
  roadmap predate verdicts and would become Completed, which a `roadmap/v4`
  roadmap at Done forbids. Leaving them on their old schema keeps their history
  as written.
