---
schema: prd/v1
status: Accepted
problem: |
  A director gets its lanes' finished pull requests, most of them marking a
  milestone done, and the coordinate skill gives it no written way to judge
  their fit with the roadmap, the strategy and the owner's recorded decisions.
  A divergent pull request can land unnoticed, a merge leaves no trace of a
  judgment, a lane's question can reach the owner twice or arrive misquoted,
  and a director can stall every lane on an owner who never opened the
  conversation.
goals: |
  A manager whose pull request diverges sees a hold naming its reason, its
  receiver and its release, and sees it lift only after a new head that the
  director read again. The owner can list every merge or recommendation with
  the alignment call recorded for its head, and a merge that skipped the
  director shows up at the next director start. A lane's question reaches the
  owner once, through the director, with relayed words checked against what
  the owner wrote, and no director blocks on an owner who didn't start the turn.
absorbed:
  - docs/briefs/BRIEF-director-alignment-review.md
motivating_context: |
  Named roles give the workspace a director: a coordinator session over the
  managers that run its lanes. The reviewer concept already makes each
  coordinator the reviewer of the work it dispatched and has a director send
  up its own reading. What that reading is for, what it does when the answer
  is no, and where the answer is kept were never written down, and the first
  director runs as soon as named roles are installed.
---

# PRD: Director Alignment Review

## Status

Accepted

Absorbed [BRIEF-director-alignment-review](docs/briefs/BRIEF-director-alignment-review.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed why this feature exists: a director's review of a lane's
finished pull request asks whether the work fits the roadmap, the strategy
and the owner's recorded decisions, not whether the code is right, and the
coordinate skill never said how it asks that, what it does with a no, or
where the answer goes. Its four gaps (a divergent pull request with no stop,
a merge that leaves no judgment behind, owner questions that multiply and
drift, and a director that stalls on the owner) are this document's Problem
Statement, and the timing it gave, that the first director runs as soon as
named roles are installed, closes it.

The outcome it asked for is what the manager, the director and the owner each
see once this lands: a held pull request whose hold names its reason,
receiver and release and lifts only after a new head and a re-read; a list of
every merge or recommendation with the call for its head, a milestone
verdict's call naming its Evidence clauses, and an uncalled merge surfacing at
the next director start; and a lane's question reaching the owner once, with
relayed words checked and no director waiting on an absent owner. Those are
this document's Goals. Its five journeys (holding a pull request that
contradicts a recorded decision, a new head on a held pull request, a
one-line call and a milestone verdict call, a merge that skipped the
director, and a mismatched relay alongside an unanswered question) are
carried in the User Stories and exercised by the Acceptance Criteria.

Its scope boundary is carried as the Requirements (in: the purpose of the
review, the hold and its release, the recorded call, the unreviewed-merge
report, the single route to the owner with the relay check, and no blocking
on the owner) and the Out of Scope list (out: correctness review, granting
authority, standing-rule provenance and its neighbours, defining the named
roles, succession telemetry, and implementation).

## Problem Statement

A manager drives one lane of work and hands its finished pull requests up to
the director that dispatched it. Almost every one of them closes a roadmap
milestone or moves one forward. The director has to decide whether each
should land or go back. Its question isn't whether the code is right: the
worker's own review round and the manager's land step already ask that. Its
question is whether the pull request does what the roadmap, the strategy and
the decisions the owner recorded say the work is for.

The coordinate skill names that question today and stops there. It makes a
director the reviewer of each manager it dispatched, has it send its own
reading up when it may not merge, and says the reading is about alignment.
It says nothing about how the director judges a pull request against the
plan, what it does when the answer is no, or where the answer goes. Four gaps
follow:

- **A divergent pull request has no stop.** A lane can finish a pull request
  that quietly contradicts a recorded owner decision. The director has no
  written way to hold it, say why, say who has to act and say what lifts the
  hold. If the lane pushes a new head, nothing says whether the old judgment
  still stands.
- **A merge leaves no judgment behind.** Once a pull request lands, nobody can
  tell whether a director judged its fit, what it concluded or against which
  clause. A merge that skipped the director looks the same as one it checked.
- **Questions to the owner multiply and drift.** Two lanes can ask the owner
  the same thing, and a lane can act on "the owner said X" when the owner
  wrote something else. Nothing makes the director the single route to the
  owner or checks a relayed quote against the recorded text.
- **A director can stall on the owner.** A director that treats an owner
  question as a gate stops every lane on someone who never opened the
  conversation.

This matters now because named roles turn the workspace's top coordinator
into a director as soon as they're installed, and that session will review
every lane's milestone pull requests from its first run.

## Goals

- A manager whose finished pull request the director judged out of line sees
  a hold on it naming the reason, the receiver and what releases it, reports
  that hold upward rather than working around it, and sees it lift only after
  it pushed a new head and the director read that head again.
- The owner can list every merge or recommendation a director made, each with
  the alignment call recorded for the head that landed or was recommended. A
  milestone verdict pull request's call names the Evidence clauses it was
  judged against. A merge that went past the director with no call shows up
  as unreviewed at the next director start.
- A question from a lane reaches the owner once, through the director. A
  relayed "the owner said X" is checked against what the owner wrote before
  the director acts on it.
- No director waits on the owner from a turn the owner didn't start: the
  question waits with its age while the other lanes keep moving.

## User Stories

- As a **manager** whose finished pull request reverses a decision the owner
  recorded, I want the director's hold to name that decision, me as the one
  who has to act and the release condition, so that my next report can say
  exactly what is held and what releases it instead of guessing.
- As a **manager** that pushed a new head to a held pull request, I want the
  hold to stay until the director has read the new head and recorded that it
  fits, so that a push alone can't slip a still-divergent change past the
  review.
- As a **director** handed a small pull request that touches no roadmap
  clause, I want to record a one-line call for its head and pass it on, so
  that the routine case costs one line while still leaving a trace.
- As a **director** handed a milestone verdict pull request, I want my call
  for its head to name the Evidence clauses I judged it against, so that the
  owner later sees what "done" was measured by.
- As the **session that holds the merge grant** above a director that holds
  none, I want the director's call and its own reading to name the head they
  judged, so that I merge that head and no other.
- As a **successor director** taking over a run, I want my first start to show
  every hold still standing and every lane merge since the last start that
  has no call, so that nothing my predecessor left unreviewed is absorbed by
  the handover.
- As the **owner**, I want to list every merge or recommendation with the
  call made for its head, and to see a merge that skipped the director
  reported as unreviewed at the next director start, so that a gap is visible
  rather than absorbed.
- As the **owner**, I want to lift a director's hold myself when I decide the
  pull request should go ahead, with my lift recorded under my name, so that
  my word can settle a hold without a new head.
- As the **owner**, I want a lane's question to reach me once, through the
  director, and a relayed quote of my words checked against what I recorded,
  so that I answer each question once and nobody acts on words I didn't
  write.
- As a **manager** waiting on an answer the owner hasn't given for a day, I
  want the other lanes to keep moving and my question to wait with its age,
  asked by no second lane, so that one silent question doesn't stop the tree.

## Requirements

Terms. **Manager**, **director** and **coordinator** are used as the named
roles define them: a manager runs one lane, a director runs over managers,
and a coordinator is a session of either role. **The reviewer**, **the land
step**, **own reading** and **bound** are used as the dispatcher-review
requirements (shirabe#1449) define them. **The owner** is the person at the
root of the director's calling hierarchy. A **lane pull request** is one a
manager authors and sends to its director, or a worker pull request a manager
reports ready or landed in its lane. A pull request's **unit** is the roadmap
unit it closes or moves, as the lane's brief or the pull request names it. An
**alignment call** is the director's recorded judgment of one lane pull
request at one head. The **plan sources** of a lane pull request are its
unit's roadmap clauses and milestone Evidence, the strategy, and each recorded
owner decision whose scope covers the pull request's unit or the files it
changes. A **matched record** is the entry or row the director names when it
treats two questions, or a relay and a recorded text, as the same subject.

### Functional

- **R1. The director's review is for alignment.** For every lane pull request,
  the director judges whether it fits its plan sources: whether it does what
  the roadmap, the strategy and the recorded owner decisions say the work is
  for, without contradicting any of them. The director doesn't re-review the
  code, doesn't launch correctness reviewers and doesn't repeat the worker's
  review round or the manager's land step. Code quality stays with them.
- **R2. A call names what it was judged against.** Each alignment call names
  the plan sources the director read for it: each roadmap clause, the strategy
  passage and each recorded owner decision it compared the pull request
  against, or `none` where it found none. When the director can't read a plan
  source it needs (the roadmap, the milestone's Evidence, the strategy or the
  record's owner decisions), it records no call for that head, says in its
  report which source it couldn't read, and neither merges nor recommends the
  pull request until a call is recorded.
- **R3. Two depths of reading.** The director gives a lane pull request a full
  read when any of these holds: its unit is marked done, reopened or dropped by
  it, or it is a milestone verdict pull request; it changes a roadmap or
  strategy document; or the director found a recorded owner decision among its
  plan sources. A full read compares the pull request against every plan
  source the call names. Any other lane pull request gets a one-line call:
  the plan sources it names (or `none`), call `fits`, and a reason of one
  line. The skill states
  this line in one place.
- **R4. Three call values.** An alignment call is one of `fits`, `fits with
  follow-ups` or `diverges`. `diverges` means the pull request contradicts or
  falls short of a plan source the call names. A `fits with follow-ups` call
  names each follow-up, and each is filed or proposed the way the land step's
  follow-ups are today.
- **R5. Every merge or recommendation has a call for its head.** The director
  records an alignment call for the exact head commit of a lane pull request
  before it merges it or recommends it to its own reviewer. A new head needs a
  new call: a call for one head never covers another. When two calls exist
  for the same head, the later one stands and both stay listed.
- **R6. A milestone verdict call cites its Evidence clauses.** The call for a
  milestone verdict pull request names, by number, each Evidence clause of
  that milestone it was judged against and says for each whether the pull
  request meets it.
- **R7. A divergent pull request is held.** When the call is `diverges`, the
  director puts a hold on the pull request that names three things: the
  reason (the plan source it diverges from, quoted or cited, and how), the
  receiver (the manager whose lane the pull request is in) and the release (a
  new head that the director reads again and calls `fits` or `fits with
  follow-ups`). The hold is recorded where the land check of every session
  that would merge or recommend that pull request reads it, the manager's
  included, so none of them can merge it or pass it up as ready while it
  stands. The director's next message to that manager names the hold. A pull
  request that has already merged can't be held; it is reported under R10 if
  it had no call.
- **R8. The manager reports the hold.** A manager whose lane pull request is
  held names the hold in every report from the first after it was placed until
  it lifts: the pull request, the reason, the director as the one it waits on,
  and the release. It reworks through its existing rework route (sending the
  work back to its worker with the reason). It never merges the pull request
  while the hold stands and never asks another session to land it.
- **R9. A hold lifts only on a new head and a director re-read.** A director's
  hold on a lane pull request lifts when both hold: the pull request's head is
  not the head the hold was placed on, and the director recorded a `fits` or
  `fits with follow-ups` call for that head. The lift names the head it was
  lifted on. A push alone doesn't lift it, a push that returns the pull request
  to the held head doesn't count as a new head, and a re-read that calls
  `diverges` again records a new call and leaves the hold standing. The owner
  or another person may lift any hold, as a person may today; that lift is
  recorded with who lifted it. Each hold on a pull request lifts on its own
  terms, and a `diverges` call on a pull request that already holds a
  director's hold adds no second one. Every director start lists each
  standing hold. A held pull request that is closed stays held in the record
  and is listed as closed while held.
- **R10. A merge with no call is reported as unreviewed.** At every director
  start (a new run, a resume, a takeover or a successor's first run), the
  director lists each lane pull request merged since the previous director
  start of its run, or since each lane was dispatched on the run's first
  start, whose merged head had no alignment call when it merged, and reports
  each as unreviewed, naming the pull request and the head. A call recorded
  for that head afterwards says it was recorded after the merge. A merge whose
  head had a call when it merged is not listed.
- **R11. The calls can be listed.** The owner can list every alignment call a
  director's run recorded, oldest first, each with the pull request, the head,
  the call, the plan sources and the reason, through one read the skill
  names. The same read lists the run's merges and recommendations, each with
  the call for its head, `after merge` where the call came later, or
  `unreviewed` where there is none.
- **R12. A lane's question goes to the owner once, through the director.** A
  manager sends a question it can't settle to its director, never to the owner.
  Before asking the owner, the director looks for a matched record: a
  question already waiting on the owner on the same subject, from any of its
  lanes, or an answer the owner already recorded on it. With a waiting
  question it adds the asking lane to it and asks nothing new; with a recorded
  answer it answers the lane from the record and asks nothing. Either way its
  reply names the matched record, so the lane can say the match is wrong.
  Otherwise it asks the owner once and records the question with the lanes
  waiting on it and the time it was asked. When the owner answers, the
  director records the answer, closes the question and tells each waiting
  lane.
- **R13. A relayed owner quote is checked against the recorded text.** When a
  manager, a worker or any other session relays "the owner said X" as grounds
  for an action, the director looks for the owner's recorded text on that
  subject before it acts on the relay. When the recorded text says X, the
  director may act on it and names the matched record. When the recorded text
  says something else, or there is none, the director declines to act on the
  relay, shows the relayed text and the recorded text (or says none is
  recorded) side by side in its reply and its next report, and asks the owner
  only if no question on that subject already waits (R12).
- **R14. No director blocks on the owner.** A director never waits on the
  owner's reply from a turn the owner didn't start: in such a turn it makes no
  ask that holds the turn open until the owner replies. It asks in a message,
  records the question as waiting, and keeps dispatching and landing every
  lane that doesn't depend on the answer. A lane that depends on it waits on
  that question alone. However long a question waits, each director report
  lists it with its age and the lanes waiting on it, and the director asks
  again on the skill's existing re-ask rule, never as a second question from
  another lane.

### Non-functional

- **R15. One new entry kind at most.** The alignment call and the hold reuse
  what the coordinator record already has: its append-only log entries and
  its hold rows. The feature adds exactly one new entry kind, the alignment
  call, leaves every existing entry kind's grammar unchanged and adds no
  record section. Every call, a re-read included, is a new entry; no entry is
  rewritten. A hold is lifted the way holds are lifted today, by recording its
  lift, and never deleted. Whether the heads R9 needs (placed on, lifted on)
  live in the hold row or in the call entries the hold names is the design's
  question.
- **R16. The call is a record other tools read.** An alignment call has five
  named fields, the pull request, the head, the call value, the plan sources
  and the reason, in a fixed grammar the skill documents. The record's write
  check refuses, with a non-zero exit and nothing recorded, a call entry that
  lacks any of the five or carries a call value outside the three. A tool
  other than the coordinate skill can read every call of a run, field by
  field, without parsing prose.
- **R17. No authority comes from the review.** Recording a call or a hold
  grants and withholds no merge, close or release authority and defines no
  grant or level. Who merges a lane pull request after the director's call
  stays with the workspace's authority configuration, read as the reviewer
  concept reads it today: a director without the merge grant sends the call
  and its own reading up to its reviewer, and the session in its calling
  hierarchy that holds the grant merges at the head the call names.
- **R18. Roles stay where they are.** Nothing in this feature changes a
  session's role. This feature treats a role as changing only on an
  intervention from a session above it in its calling hierarchy, or from a
  person, and adds no such intervention: a hold, a call, a declined relay and
  a lane's question are none of those. It leaves the named roles' rules on
  how a role is set, kept and changed as they are.
- **R19. It runs before provenance.** A director can do all of the above with
  skill text and the record as it is plus the one new entry kind, before
  standing-rule provenance gives entries a source. Where the relay check of
  R13 reads recorded owner text, it reads the record's existing owner-decision
  rows and settled decisions; the later provenance work may change where that
  text is read from, and the design names where.

## Acceptance Criteria

Each criterion is checked against a director's record and reports in a test
workspace with two lanes, a fixed clock and a planted roadmap, strategy and
owner decision.

Alignment calls:

- [ ] A lane pull request with no plan source that the director recommends
  has one recorded call for its head with plan sources `none`, call `fits`
  and a one-line reason. (R3, R5)
- [ ] A lane pull request that changes a roadmap document gets a call whose
  plan sources name at least one roadmap clause. (R3)
- [ ] A lane pull request whose scope a planted owner decision covers gets a
  call whose plan sources name that decision. (R2, R3)
- [ ] A milestone verdict pull request that is recommended has a call for its
  head that names, by number, each Evidence clause of its milestone and says
  for each whether it is met. (R3, R6)
- [ ] A `fits with follow-ups` call names each follow-up, and each appears as
  a filed issue or a proposed issue in the director's report. (R4)
- [ ] With the roadmap made unreadable, the director records no call for the
  pull request, its report names the roadmap as unreadable, and the pull
  request is neither merged nor recommended. (R2)
- [ ] After a new push, the list read reports the new head without a call
  until one is recorded; a second call for the same head is listed beside the
  first, with the later one marked as standing. (R5, R11)
- [ ] The record's write check exits non-zero and records nothing for a call
  entry missing any one of the pull request, head, call value, plan sources
  or reason, and for one whose call value is not one of the three. (R4, R16)
- [ ] A script outside the coordinate skill reads every call of a run as
  separate fields with a JSON or line parser, with no free-text matching.
  (R16)

Holds:

- [ ] A lane pull request that contradicts the planted owner decision gets a
  `diverges` call naming that decision, and a hold whose recorded reason names
  the decision, whose receiver is the lane's manager and whose release is a
  new head re-read by the director. (R1, R2, R4, R7)
- [ ] With that hold standing, the manager's land check reports the pull
  request as held, the skill's merge step refuses to merge it, and the
  director's next message to the manager names the hold. (R7)
- [ ] Every manager report from the first after the hold until the lift names
  the held pull request, the reason, the director and the release, and the
  manager's record shows the work sent back to its worker. (R8)
- [ ] After a new head is pushed and before the director records a call for
  it, the hold stands and a director start lists the pull request as held.
  After the director records `fits` for that head, the hold is lifted and the
  lift names that head. (R9)
- [ ] A re-read that calls `diverges` on the new head adds a call and leaves
  the hold standing; a `fits` call recorded for the held head itself leaves
  the hold standing. (R9)
- [ ] A push that returns a held pull request to its held head, followed by a
  `fits` call for that head, leaves the hold standing. A `diverges` call on a
  pull request already held by the director adds no second hold. (R9)
- [ ] A person's lift of a hold on an unchanged head lifts it and records the
  person as the one who lifted it. (R9)
- [ ] A held pull request that is closed is listed as closed while held at
  the next director start. (R9)

Unreviewed merges and the list:

- [ ] A lane pull request merged with no call for its merged head is reported
  as unreviewed, with its pull request and head, at the next director start,
  for each of a new run, a resume, a takeover and a successor's first run. A
  call recorded for that head afterwards is listed as `after merge`. (R10, R11)
- [ ] A lane pull request merged with a call for its merged head is not
  reported as unreviewed. (R10)
- [ ] The read the skill names lists every call oldest first with its five
  fields, and every merge or recommendation with its head's call, `after
  merge` or `unreviewed`. (R11)

Owner questions:

- [ ] Two lanes raise a question on the same subject. The owner receives one
  message for it, the director's record shows one waiting question listing
  both lanes and the time asked, and the reply to the second lane names the
  matched question. (R12)
- [ ] A lane raises a question the owner already answered in the record. The
  director answers it from the record, naming the matched record, and sends
  the owner nothing. (R12)
- [ ] When the owner answers a waiting question, the record shows it closed
  with the answer, and each waiting lane gets a message with it. (R12)
- [ ] A manager relays "the owner said X" while the recorded text on that
  subject says Y. The director takes no action grounded on the relay, and its
  reply and next report show both X and Y. With no recorded text, the reply
  says none is recorded. When the recorded text says X, the director acts and
  names the matched record. (R13, R19)
- [ ] With the clock advanced 24 hours past a question's asking, every
  director report lists it with an age of at least 24 hours and the lanes
  waiting on it; a lane that doesn't depend on it is dispatched and landed in
  that time; and no second message on that subject reaches the owner except
  the re-ask the skill's rule schedules. (R12, R14)
- [ ] In a director turn started by a lane's message, the director issues no
  ask that waits for the owner's reply before the turn ends. (R14)

Boundaries:

- [ ] The feature's change adds exactly one value to the record's list of
  entry kinds and no record section, and every existing entry kind's grammar
  in the record's schema is byte-identical before and after. (R15)
- [ ] Every sentence the feature adds that contains "grant", "level",
  "authority" or "role" is listed in the implementation pull request, and
  none of them says a call, a hold or a role gives, needs or changes a grant,
  a level, an authority or a role. (R17, R18)
- [ ] A director with no merge grant that calls a lane pull request `fits`
  doesn't merge it and sends the call and its own reading to its reviewer;
  the grant holder's merge is at the head the call names. (R17)

## Out of Scope

- **Correctness review of a pull request.** The worker's review round and the
  manager's land step own it; the director doesn't repeat it.
- **Granting merge, close or release authority, or defining levels.** The
  workspace's authority configuration owns that; this feature only reads the
  answer.
- **A fast path that lets a coordinator land its own finished work before its
  dispatcher reviews it.** The dispatcher-review rule that a coordinator's
  finished work goes to its dispatcher before it lands, with or without a
  merge grant, stands as it is. R10 reports whatever lands past the director
  anyway.
- **Standing-rule provenance, a successor restating rules, and moving caps.**
  Separate work owns them. This feature names where it meets them (R19) and
  stops there.
- **Defining the named roles, or how a session's role changes.** The
  named-roles work owns that.
- **Succession telemetry.** Separate observability work may later read the
  alignment call; this feature only keeps the call readable (R16).
- **A routing mechanism for owner questions beyond the record.** The single
  route of R12 is the director's own duty and its record; no queue, service or
  gate outside the coordinator record is built.
- **Directors over directors.** Routing a question through more than one
  director on its way to the owner is not covered; a director's owner is the
  person at the root of its own hierarchy.

## Known Limitations

- **The named roles aren't installed yet.** This feature needs the director
  role in the record and the director's expectation list in the skill, which
  the named-roles plan (shirabe#1483) builds and which isn't merged. Until it
  lands, nothing tells a session it is a director, so none of this applies.
  The named-roles work is also being amended so that a continuation keeps its
  role and a role changes mid-lineage only on an intervention from a session
  above it in its calling hierarchy, or from a person, recorded with who and
  when. R18 relies on that amendment and doesn't restate it.
- **The relay check is only as good as the recorded text.** Until
  standing-rule provenance lands, the director checks a relay against the
  owner-decision rows the record already keeps. An owner decision that was
  never recorded can't confirm or refute a relay, and the director says so.
- **A full read is still a judgment.** The triage line of R3 decides how deep
  the director reads, not whether its conclusion is right. A wrong `fits`
  is visible afterwards in the list of calls, not prevented.
- **Open item: succession telemetry may read the call.** Separate
  observability work on how coordinators hand over may later read the
  alignment calls a run recorded. R16 keeps them readable for it; which
  fields it needs is that work's question.

## Decisions and Trade-offs

- **Triage line.** A full read for pull requests that mark their unit done,
  reopened or dropped, change a roadmap or strategy document, or have a
  recorded owner decision among their plan sources; a one-line call for the
  rest (R3). Alternatives: a full read for every pull request, which makes
  the routine case cost what a milestone costs and stalls the director; or
  leaving the depth to the director's judgment each time, which leaves no way
  to check that a milestone got a full read. The chosen line is checkable from
  the pull request's unit, its changed files and the call's own plan sources.
- **An unreadable source means no call.** A director that can't read a plan
  source it needs records nothing and holds the pull request back (R2),
  rather than recording a fourth call value. Alternative: an `unread` value.
  Rejected: a call that judged nothing would satisfy R5's "a call for every
  head" and hide the gap R10 exists to show.
- **Matching is shown, not hidden.** Whether two questions, or a relay and a
  recorded text, are on the same subject stays the director's judgment, and
  every time it treats them as the same it names the matched record (R12,
  R13). Alternative: an exact-text rule, which two lanes wording one question
  differently would defeat. Showing the match lets a lane say it's wrong.
- **Push-back reuses the rework route.** A hold plus the manager's existing
  rework route (R8), not a new route. Alternative: a director-specific
  push-back that bypasses the manager and rebriefs the worker. Rejected: it
  would make the director implement through the lane's worker and skip the
  manager's land step, which is where correctness is checked.
- **Release needs both a new head and a re-read.** Alternatives: lift on a new
  head alone, which lets an unchanged-in-substance push through; or lift on a
  re-read alone, which lets the director wave through the same head it held
  without anything changing. A person's lift stays available, as it is today.
- **Who merges after a director without the grant.** Unchanged from the
  reviewer concept: the call and the director's own reading go up, and
  whoever in the calling hierarchy holds the grant merges at the called head
  (R17). This feature decides nothing about who holds the grant.
- **A hold reaches the session that would merge.** Each coordinator's land
  check reads only its own record's holds, so a hold kept only in the
  director's record would stop nothing in a manager's land step. R7 therefore
  requires the hold where the merging session's land check reads it, not in
  the director's record alone; how it gets there is the design's question. A
  pull request that already merged can't be held, only reported (R10).
- **Review before landing stays as it is.** A coordinator's finished work
  goes to its dispatcher for review before it lands, with or without a merge
  grant, as the dispatcher-review requirements already say. This feature
  adds no exception to that for routine pull requests; R10 makes visible
  whatever lands past the director anyway.
- **One new entry kind, not a widened goal-fit entry.** The call is a new log
  entry kind because entries are already append-only. The existing goal-fit
  entry doesn't fit: it carries no head, it judges fit against the lane's
  brief rather than the plan sources, and it is written only on milestone
  roadmaps. Widening it would change an existing grammar, which R15 rules
  out. A new record section would duplicate the entries' machinery.
- **How the director finds what a pull request touches.** The requirement is
  that the call names its plan sources (R2) and that the triage line can be
  checked (R3). How the director finds them, from the pull request's unit,
  its changed files and the record's owner-decision rows, is the design's
  question.
