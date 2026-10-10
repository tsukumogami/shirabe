---
schema: prd/v1
status: Done
problem: |
  The roadmap format says a milestone is Done only on a verification verdict
  from the coordinator that dispatched the work or a person, but the
  coordinator's status write-back and the completion cascade still set Done
  when work merges, the coordinator's goal-fit judgment never reads the
  milestone's Evidence, a milestone that produces no pull request has no route
  to a verdict, and a Done milestone that later fails its Evidence has no way
  back to In progress. Coordinators and roadmap owners can't trust Done.
goals: |
  A coordinator driving a milestone roadmap closes every milestone, with one
  pull request, several or none, on a verdict it records naming who checked,
  and the milestone reads Done only after a verified verdict of either kind. Each pull
  request's goal fit names the Evidence clause it advances, a post-Done
  failure returns the milestone to In progress where the picker offers it
  again, and no tool sets a milestone Done because something merged.
---

# PRD: milestone verdicts

## Status

Done

The feature's brief was folded into this PRD while it was scoped and never
landed on its own; its framing is carried in Absorbed Brief.

## Absorbed Brief

The feature exists because a milestone roadmap's one promise, that Done
means someone other than the builder checked the work against its
Evidence, isn't kept by the tools. The brief framed four gaps: the
coordinator's status write-back and the completion cascade set Done when
work merges; the coordinator judges each pull request against its brief,
never the milestone's Evidence; a milestone whose Evidence is host state or
a walkthrough produces no pull request and so has no route to a verdict;
and a Done milestone later found short of its Evidence has no way back, so
the gap is filed as new work or forgotten while the roadmap keeps saying
Done.

The cost lands on whoever reads the roadmap to decide what comes next: a
dependent milestone starts on a capability that isn't there, the owner
judging the roadmap's bet counts outcomes that never arrived, and the
rework surfaces later, attached to whatever tripped over it.

The outcome the brief set: a coordinator closes every milestone the same
way, with one pull request, several or none, by checking its Evidence and
recording a verdict that names who checked; Done follows only from that
verdict; each landed pull request's goal fit names the Evidence clause it
advances; and a roadmap owner who finds a Done milestone failing can have
it returned to In progress and offered again, so the gap is fixed in the
milestone that promised it. Its boundary kept out verdict consumption by a
separate reviewing session, roadmap migration, merge ownership, plan
format, cost capture, and any change to koto or niwa.

## Problem Statement

A roadmap in milestone form (schema `roadmap/v2`) promises its reader that a
milestone reads Done only after someone other than the session that built it
checked the shipped work against the milestone's Evidence and recorded a
verdict. `skills/roadmap/references/roadmap-format.md` states that rule and
says, in the next paragraph, that no tool enforces it. The format work that
introduced milestones deferred the enforcement to this feature.

Today the tools contradict the rule in four ways:

- **Done on merge.** When the coordinator ticks `landed` for a unit, its
  `roadmap_status` state runs `roadmap-status.sh --unit`, which opens a pull
  request setting the feature's Status to Done. The `merge_confirm` and
  `merged_facts` guidance also suggests dispatching a worker for a
  "status-line pull request" when a feature lands. The completion cascade
  (`run-cascade.sh`) sets a feature Done when the finishing PLAN is named on
  a `**Downstream:**` line, and on a milestone roadmap, which has no such
  line, it reports `partial` and halts `/execute` instead.
- **Goal fit ignores Evidence.** The coordinator's `goal_fit` judges each pull
  request against the brief it wrote, and its rationale stays in the local
  koto log. Nothing records which Evidence clause a pull request advanced.
- **No route for work without a pull request.** A worker that reports a
  milestone finished with no pull request is sent back to name one. A
  milestone whose Evidence is the state of a host or a walkthrough a person
  follows can only be closed by a hand edit nobody can trace.
- **No way back.** Nothing records that a Done milestone's Evidence no longer
  holds, nothing returns it to In progress, and the status writer refuses a
  milestone that already reads Done.

Coordinators that apply the rule today do it by hand, declining the tools'
own suggestions and keeping verdicts somewhere the tools never read. Roadmap
owners reading Done can't tell whether anyone checked.

## Goals

- A coordinator closes each milestone on a recorded verdict that names who
  checked, through one step that works whether the milestone produced one
  pull request, several, or none.
- A milestone reads Done only after a verified or verified-with-follow-ups
  verdict; no merge, landing or finished PLAN sets it.
- Each pull request the coordinator lands for a milestone carries a goal-fit
  judgment, in the record, naming the Evidence clause it advances.
- A failure recorded against a Done milestone returns it to In progress, and
  the coordinator's picker offers it again.

## User Stories

- **As a coordinator** whose worker's last pull request for a milestone has
  merged, I want the milestone to stay In progress and the run to ask me for
  a verdict, so that I check each Evidence clause before anything reads Done.
- **As a coordinator** driving a milestone whose Evidence is host state or a
  walkthrough, I want to close it through the same verdict step when its work
  is reported finished, so that a milestone with nothing to merge is recorded
  the same way as one that merged code.
- **As a coordinator** landing a pull request partway through a milestone, I
  want my goal-fit judgment to name the Evidence clause it advances and be
  recorded where others can read it, so that a pull request that advances
  nothing the milestone needs is visible at landing rather than at the
  verdict.
- **As a roadmap owner** who re-runs a Done milestone's Evidence check and
  sees it fail, I want to tell the coordinator and have the milestone go back
  to In progress and be offered again, so that the gap is fixed in the
  milestone that promised it.
- **As a coordinator** closing out a milestone roadmap, I want close-out to
  wait while any verdict is owed or a reopened milestone's edit is pending,
  so that a roadmap never reads finished with a milestone still unjudged.
- **As a delivery session** finishing the PLAN under a milestone, I want the
  completion cascade to leave the milestone's status alone and report
  success, so that `/execute` doesn't halt on `partial` and the verdict stays
  the coordinator's.

## Requirements

### Definitions

- **Tag**: a milestone's heading label, such as `Feature 2` in
  `### Feature 2: <title>`.
- **Milestone roadmap**: a roadmap whose frontmatter declares
  `schema: roadmap/v2`. A **feature roadmap** is any other roadmap.
- **Verdict**: one of `changes needed`, `verified with follow-ups` or
  `verified`, as the roadmap format reference defines them. The two
  **verified verdicts** are `verified` and `verified with follow-ups`.
- **Record body** and **entry**: the coordinator's record keeps its state in
  the record issue's body, which only the coordinator's record scripts
  rewrite, and its trail as comments on that issue, each an entry. An entry
  is referred to by its comment URL.
- **Holding**: the record body's row tying a dispatched unit to the worker
  (its dispatch topic) that holds it.
- **Pending roadmap edit**: a roadmap pull request the coordinator's status
  writer opened and recorded in the record body, until it is confirmed or
  dropped. **Confirmed** means the coordinator's confirm step read the
  default branch and found the Status the edit set.
- **Verdict owed**: a record-body mark on a milestone, written when the
  coordinator ticks `landed` for it on a milestone roadmap and cleared when
  its verdict's roadmap edit is confirmed.

### Verdict rules

| Verdict | Clause lines | Strategy fit | Follow-ups | Changes needed | Status after the edit |
|---|---|---|---|---|---|
| verified | every clause held | fits | none | none | Done |
| verified with follow-ups | every clause held | fits | at least one | none | Done |
| changes needed | at least one not held (or all held, with does not fit) | fits or does not fit | any | not none | unchanged (In progress) |

### Functional

**R1. No merge-driven Done on milestone roadmaps.** On a milestone roadmap:
ticking `landed` never runs the merge-driven status write
(`roadmap-status.sh --unit` in its Done-on-landing form); the `merge_confirm`
and `merged_facts` guidance never suggests a status-line pull request; the
completion cascade never edits the roadmap (R11); and nothing writes a
milestone's Delivered line except the verdict's roadmap edit (R4). Feature
roadmaps keep every one of these behaviours unchanged.

**R2. The verdict step.** Ticking `landed` for a unit on a milestone roadmap
takes the run to a verdict step, and the run doesn't leave that step until a
verdict entry passing R3's check is recorded for the milestone or the
coordinator defers it, leaving the run's other work to go on while the
milestone keeps its verdict-owed mark and the step can be reached again. The
step's guidance has the coordinator read the milestone's Evidence from the
roadmap on the default branch and check each clause against the shipped
result and the roadmap's strategy. The coordinator ticks `landed` when the
milestone's last pull request has merged, or, for a milestone with nothing
to merge, when a worker reports the work finished with no pull request or
the coordinator itself sees the last piece done. A worker's report that a
milestone on a milestone roadmap is finished with no pull request is not
sent back to name one.

**R3. The verdict entry and its check.** A verdict entry has these labelled
lines, in this order: `Verdict: <tag> -- <verdict>`, `Checked by:`,
`Checked on:` (a date no later than today), `Source: <roadmap path> at
<commit>`, `Work checked:` (pull requests as `owner/repo#n`,
comma-separated, or `none`), then one line per Evidence clause numbered as
the roadmap orders them, reading `<n>. held -- <what showed it>` or
`<n>. not held -- <what showed it>`, then `Strategy fit: <fits|does not
fit> -- <why>`, `Follow-ups:` (`none`, or items `new: <title>` or `amend
<tag>: <what>` separated by `; `) and `Changes needed:` (`none`, or what
must change). A check script refuses, naming the line, an entry that breaks
this shape, whose clause count differs from the milestone's Evidence at
`Source`, whose verdict breaks the verdict rules table, or whose `Checked
by` contains the dispatch topic of the worker that holds the milestone in
the record body (compared case-insensitively). The exact wording of each
refusal is the design's.

**R4. Done follows the verdict.** Recording a verdict entry that passes R3
is followed, in the same step, by the coordinator's status writer opening a
roadmap pull request that adds a dated Progress line naming the milestone,
the verdict, who checked and the entry's URL, and adds the work checked to
the milestone's Delivered line (nothing for `none`). For a verified verdict
it also sets the Status to Done and removes any Needs line; for verified
with follow-ups it does that and adds each follow-up in the same change
(a `new:` follow-up as a new milestone heading under an unused tag, whose
Outcome, Evidence, Left open and Dependencies the coordinator supplies; an
`amend` follow-up as an edit to the named milestone); for changes needed it
leaves the Status unchanged. The writer records the pull request as a
pending roadmap edit and never merges.

**R5. Writer edge cases.** The status writer refuses, naming the reason, a
verdict edit for a milestone that already reads Done; one whose `Source`
commit's Evidence for the milestone differs from the default branch's (the
coordinator re-checks against the current Evidence); a `new:` follow-up
whose tag another heading already uses, or an `amend` follow-up naming a tag
the roadmap doesn't have; and any second roadmap edit (verdict or reopen)
for a milestone that already has a pending roadmap edit, so a second
failure recorded while a reopen edit is pending opens nothing. A pending
roadmap edit of either kind whose pull request is closed unmerged can be
dropped, after which the edit can be opened again from the same entry.

**R6. Nothing is re-dispatched while a verdict is owed.** The picker never
offers a milestone with a verdict-owed mark, whether or not its holding has
been retired. When a changes-needed verdict's edit is confirmed the mark
clears, the milestone (still In progress) is offered again once no holding
covers it, and its next brief carries the verdict's Changes needed line and
each not-held clause.

**R7. Goal fit against Evidence.** When the coordinator lands a pull request
for a milestone on a milestone roadmap, the goal-fit step shows it the
milestone's numbered Evidence clauses from the default branch, and the
judgment is posted as an entry naming the pull request, the milestone, and
the clause numbers it advances (each a clause number of that milestone's
Evidence) or the words `advances none`; a check script refuses a goal-fit
entry naming a clause number the milestone doesn't have. `advances none`
doesn't block landing on its own; the existing goal-fit outcomes still
decide that.

**R8. Recording a post-Done failure.** The coordinator records a failure
against a milestone that reads Done as an entry with the labelled lines
`Failure: <tag>`, `Reported by:`, `Seen on:` (a date no later than today),
`Clause: <n>` (a clause number of the milestone's Evidence on the default
branch) and `What was seen:`. A check script refuses an entry that breaks
this shape, names a clause number out of range, or names a milestone that
doesn't read Done. A passing entry is followed by the status writer opening
a roadmap pull request that sets the Status to In progress and adds a dated
Progress line naming the failure and the entry's URL, recorded as a pending
roadmap edit. Any person or the coordinator itself may be the reporter. `shirabe
validate` accepts a milestone whose Status went from Done back to In
progress.

**R9. A reopened milestone is offered again.** Once the reopen edit is
confirmed, and while no holding or pending roadmap edit covers the
milestone, the picker lists it as not done and offers it like any other
unblocked milestone, and the next brief for it carries the failure entry's
clause and what was seen. Milestones that depend on it read blocked again; a
dependent that already holds a worker is listed in the output of the step
that records the failure, so the coordinator can decide what to do with it.

**R10. Close-out waits.** The coordinator's close-out refuses to close a
roadmap, naming the milestone, while any milestone has a verdict-owed mark
or a pending reopen edit, and closes it as today once neither stands.

**R11. The completion cascade on a milestone roadmap.** When a PLAN
completes under a milestone roadmap, the cascade closes out the PLAN's own
chain as today; leaves the roadmap file byte-for-byte unchanged; never
transitions or deletes it; records its roadmap step as `skipped` with a
reason that names the milestone Done rule; and reports `completed` when no
other step failed. On a feature roadmap the cascade behaves as today,
`**Downstream:**` lookup included.

**R12. The documents say what the tools do.** The roadmap format reference
no longer says the Done rule is unenforced or that the completion cascade
or the coordinator updates a milestone's status on merge, and it says a
post-Done failure returns a milestone to In progress through the
coordinator. The coordinate skill's documentation describes the verdict
step, the verdict, goal-fit and failure entries, and reopening.

### Non-functional

**R13. Bash floor.** Every script this feature adds or changes runs on bash
3.2 and is listed in `scripts/check-bash-floor.sh` for its skill, as are the
existing coordinate tests of scripts it changes.

**R14. Checked by script suites and CI.** Every acceptance criterion below
is checked by a script suite that runs offline against a test roadmap and
record in a `mktemp` directory or scratch repository (GitHub and koto
replaced by the suites' stand-ins, never a real record), and every such
suite runs in a CI workflow. Skill evals aren't the definition of done.

**R15. An entry alone changes nothing.** Setting Done, clearing a
verdict-owed mark, re-offering a milestone and closing a roadmap depend on
the record body and the roadmap on the default branch, never on an entry
alone, because any session with the coordinator's GitHub login can post a
comment. For the same reason an entry's author is read from its
`Checked by:` or `Reported by:` line, never from the comment's GitHub
author.

## Acceptance Criteria

Each criterion runs against a test milestone roadmap with two milestones,
one whose work is a pull request (with two Evidence clauses) and one whose
Evidence is host state, starting from an empty record.

- [ ] A suite records a verdict for each test milestone through the verdict
  check and the record scripts, and the record holds two verdict entries,
  each passing the check and each with a `Checked by:` line naming the
  coordinator's session.
- [ ] After the PR-bearing milestone's PLAN completes in a scratch
  repository, the cascade's output reports `completed` with the roadmap step
  `skipped`, the roadmap file's hash is unchanged, and it isn't deleted.
- [ ] On a feature roadmap, the cascade still sets the named feature Done
  through its `**Downstream:**` line.
- [ ] Ticking `landed` on the test milestone roadmap leaves the GitHub
  stand-in's log with no call from the merge-driven status write and the run
  at the verdict step; on a feature roadmap the same tick opens the Done pull
  request as today.
- [ ] The rendered `merge_confirm` and `merged_facts` guidance for a unit on
  the test roadmap doesn't suggest a status-line pull request.
- [ ] A worker report that the host-state milestone is finished with no pull
  request reaches `landed` handling and isn't answered with a request to
  name a pull request.
- [ ] The verdict check accepts one well-formed entry of each verdict, and
  refuses: a missing or reordered line; a clause count that differs from the
  milestone's Evidence; a verified verdict with a clause not held, with
  `does not fit`, with a follow-up, or with changes named; verified with
  follow-ups and no follow-up; changes needed with every clause held and
  `fits`, or with `Changes needed: none`; a future `Checked on`; and a
  `Checked by` containing the holding worker's topic in any letter case.
- [ ] A verified verdict produces a roadmap pull request that sets Done,
  adds the Progress line with the entry's URL, adds the work to Delivered
  and removes Needs; verified with follow-ups also adds each `new:`
  milestone and changes each `amend` target in the same change; changes
  needed adds the Progress line and leaves Status and Delivered unchanged;
  the GitHub stand-in's log shows no merge call.
- [ ] The writer refuses a verdict edit for a milestone that reads Done, one
  whose Evidence changed since `Source`, and a second edit while one is
  pending; after a pending edit's pull request is closed and dropped, the
  same verdict's edit opens again.
- [ ] Deferring at the verdict step leaves the milestone's verdict-owed
  mark in place and the picker not offering it, and the verdict step is
  reached again on the next `landed` tick for it.
- [ ] The writer refuses a `new:` follow-up under a tag already used and an
  `amend` naming a tag the roadmap lacks.
- [ ] Between `landed` and the verdict edit's confirmation the picker
  doesn't offer the milestone, with its holding present and after it is
  retired; after a changes-needed edit is confirmed, with no holding, the
  picker offers it and the next brief carries the Changes needed line and
  the not-held clauses.
- [ ] Landing a pull request for the PR-bearing milestone posts a goal-fit
  entry naming that pull request and clause numbers that exist in the
  milestone's Evidence, and the goal-fit check refuses an entry naming
  clause 3; a pull request judged to advance nothing posts
  `advances none` and still lands when the goal-fit outcome allows.
- [ ] A failure entry against the Done host-state milestone passes its
  check and produces a roadmap pull request setting it In progress with the
  Progress line; the check refuses a failure against a milestone not Done,
  a clause number out of range, and a malformed entry; a second failure
  while the reopen edit is pending opens no second pull request; and
  `shirabe validate` passes on the reopened roadmap.
- [ ] While the reopen edit is pending the picker doesn't offer the
  milestone; once confirmed it lists it not done and offers it, and the
  next brief carries the clause and what was seen; a dependent milestone
  reads blocked, and a dependent holding a worker is named in the output of
  the step that recorded the failure.
- [ ] Close-out refuses the test roadmap while a verdict is owed and while a
  reopen edit is pending, naming the milestone, and closes it once every
  milestone reads Done with neither standing.
- [ ] A verdict entry or a failure entry posted on the record with no
  matching record-body change sets nothing Done or In progress, clears no
  mark, re-offers nothing and doesn't let close-out pass.
- [ ] The roadmap format reference contains no sentence saying the Done
  rule is unenforced or that the cascade or coordinator sets a milestone's
  status on merge (a grep for "unenforced" and for "updates it as
  downstream plans land" finds nothing), and the coordinate skill's
  documentation has a section on verdicts covering the verdict step, the
  three entries and reopening.
- [ ] Every script added or changed is in `scripts/check-bash-floor.sh`'s
  list for its skill and passes there on bash 3.2, and each suite above is
  run by a CI workflow.
- [ ] `shirabe validate` passes on every changed document, and every CI job
  on the head each pull request is reported ready at is green; a pull request body names any suite
  not re-run locally.

## Out of Scope

- How a separate reviewing session or a pre-review sort consumes verdicts;
  this feature makes verdicts exist and readable, and that review has its own
  owner.
- Rewriting existing roadmaps into milestone form, or moving roadmaps a
  coordinator is already driving; that migration depends on this feature.
- Who merges pull requests, and any coordinator above a single coordinator.
- The functional-step format of plans under a milestone, and capturing time
  and token cost per unit.
- Feature roadmaps: they keep merge-driven Done, and the cascade's
  `**Downstream:**` lookup on them is unchanged.
- Retiring a milestone roadmap once every milestone is verified; the cascade
  stops deleting it, and how a finished milestone roadmap ends is left to the
  roadmap's own lifecycle.
- A failure against a milestone whose roadmap's coordinator record is already
  closed. The owner records it by editing the roadmap by hand or by starting
  a coordinator on the roadmap again, whose new record then takes it.
- A milestone roadmap with a milestone that has no Evidence clause; the
  validator already refuses it.
- Any change to koto or niwa.

## Known Limitations

- The verdict's honesty rests on the checker. The entry check proves the
  shape and the internal consistency of a verdict, not that the checker
  looked; that stays the coordinator's or the owner's responsibility.
- A dependent of a reopened milestone that already holds a worker keeps
  running; the failure step lists it and the coordinator decides.
- The completion cascade's `**Downstream:**` lookup keeps its known problems
  on feature roadmaps.
- Goal fit's clause naming is the coordinator's judgment; the suites can
  check that the named clauses exist, not that they're the right ones.

## Decisions and Trade-offs

**Milestone roadmaps are recognised by schema, not content.** Alternatives:
detect the `**Outcome:**`/`**Evidence:**` fields; apply the rule to every
roadmap. Some older feature roadmaps carry `**Outcome:**` lines that record
merged pull requests, so a content test would misread them, and the
validator's milestone check already gates on `schema: roadmap/v2`. Applying
the rule to feature roadmaps would leave their coordinators unable to close
anything, since a feature has no Evidence to judge.

**Feature roadmaps keep merge-driven Done.** This closes the brief's open
question. The milestone format scoped the Done rule to milestones and left
version 1 untouched; taking merge-driven Done away from feature roadmaps
would strand their coordinators with no verdict to give.

**Advancing no clause is recorded, not blocking.** The goal-fit step
already has outcomes that block or pass a pull request; naming the clauses
makes a pull request that advances none visible in the record, and the
coordinator's existing judgment decides what to do about it.

**After changes needed the milestone is offered again with the changes.**
The milestone stays In progress, and the verdict-owed mark clears when the
edit is confirmed, so the picker treats it like any unfinished milestone,
and the next brief carries what the verdict said must change.

**The verdict hangs off `landed`.** Alternatives: trigger on `merged`; add a
separate event. `landed` is already the coordinator's own judgment that a
unit's work is finished, separate from any merge, and its guidance already
covers a spike or design whose acceptance call was made, so one event serves
milestones with and without pull requests.

**The cascade reports skipped, not a new status.** A new `cascade_status`
value would stall `/execute`, whose gates match three literal values, and be
refused by `/work-on`. The cascade's own design defines `skipped` for a step
deferred on state it doesn't control, which is what a milestone's status is.

**Decisions live in the record body; entries are the readable trail.** Any
session with the coordinator's GitHub login can post an entry, including a
worker, so gating Done, re-offering or closing on entries alone would let the
delivering session close its own milestone. The guarded body write carries
the state, and the entries carry what a reader needs to follow it.

**A post-Done failure reopens the milestone rather than filing new work.**
This is the roadmap format's rule: the gap is fixed in the milestone that
promised it, judged against the same Evidence.
