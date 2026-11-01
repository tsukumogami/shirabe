---
schema: prd/v1
status: Draft
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
upstream: docs/briefs/BRIEF-director-alignment-review.md
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

Draft

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
- As the **owner**, I want to list every merge or recommendation with the
  call made for its head, and to see a merge that skipped the director
  reported as unreviewed at the next director start, so that a gap is visible
  rather than absorbed.
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
reports ready or landed in its lane. An **alignment call** is the director's
recorded judgment of one lane pull request at one head. The **plan sources**
of a lane pull request are the roadmap and its milestone Evidence, the
strategy, and the owner's recorded decisions that bear on the pull request's
scope.

### Functional

- **R1. The director's review is for alignment.** For every lane pull request,
  the director judges whether it fits its plan sources: whether it does what
  the roadmap, the strategy and the recorded owner decisions say the work is
  for, without contradicting any of them. The director doesn't re-review the
  code, doesn't launch correctness reviewers and doesn't repeat the worker's
  review round or the manager's land step. Code quality stays with them.
- **R2. A call names what it was judged against.** Each alignment call names
  the plan sources the director read for it: the roadmap clause or clauses,
  the strategy passage, and each recorded owner decision it compared the pull
  request against, or `none` where a pull request touches none of them. A
  call that couldn't read a source it needed says which and is not a fitting
  call.
- **R3. Two depths of reading.** The director gives a lane pull request a full
  read when any of these holds: it is a milestone verdict pull request or
  otherwise marks a roadmap unit done, reopened or dropped; it changes the
  roadmap or strategy text; or it touches the subject of a recorded owner
  decision. A full read compares the pull request against each plan source it
  names. Any other lane pull request gets a one-line call: one line of reason
  saying it touches no plan source and fits. The skill states this line in
  one place.
- **R4. Three call values.** An alignment call is one of `fits`, `fits with
  follow-ups` or `diverges`. `diverges` means the pull request contradicts or
  falls short of a plan source it names. `fits with follow-ups` names each
  follow-up, which is filed or proposed the way the land step's follow-ups
  are today.
- **R5. Every merge or recommendation has a call for its head.** The director
  records an alignment call for the exact head commit of a lane pull request
  before it merges it, recommends it to its own reviewer, or tells a manager
  it may proceed. A new head needs a new call: a call for one head never
  covers another.
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
  that would merge or recommend that pull request reads it, so none of them
  can land it or pass it up as ready while the hold stands. The director tells
  the manager in its next message.
- **R8. The manager reports the hold.** A manager whose lane pull request is
  held reports the hold in its next report and every report after it until
  it lifts, naming the pull request, the reason, the director as the one it
  waits on and the release. It reworks through its existing rework route
  (sending the work back to its worker with the reason), never by merging
  around the hold or by asking a different session to land it.
- **R9. A hold lifts only on a new head and a director re-read.** A director's
  hold on a lane pull request lifts when both hold: the pull request's head
  is not the head the hold was placed on, and the director recorded a `fits`
  or `fits with follow-ups` call for the new head. A push alone doesn't lift
  it. A re-read that still calls `diverges` keeps it and updates nothing but
  the call. A person may lift any hold, as a person may today; that lift is
  recorded with who lifted it. While held, the pull request shows as held at
  every director start.
- **R10. A merge with no call is reported as unreviewed.** At every director
  start (a new run, a resume, a takeover or a successor's first run), the
  director lists each lane pull request merged since the last director start
  of its run whose merged head has no alignment call, and reports each as
  unreviewed, naming the pull request and the head. A call recorded later for
  that head says it was recorded after the merge, so the list of merges keeps
  showing that the review came late. A run's first start covers merges since
  each lane was dispatched.
- **R11. The calls can be listed.** The owner can list every alignment call a
  director's run recorded, newest last, each with the pull request, the head,
  the call, the plan sources and the reason, through one read the skill
  names. The same read lists the run's merges and recommendations with the
  call for each one's head, or `unreviewed` where there is none.
- **R12. A lane's question goes to the owner once, through the director.** A
  manager never asks the owner directly; a question it can't settle goes to
  its director. Before asking the owner, the director checks whether the same
  question already waits on the owner, from any of its lanes. If it does, the
  director adds the asking lane to it and asks nothing new. When the record
  already holds the owner's answer to it, the director answers the lane from
  that record and asks nothing. Otherwise it asks the owner once and records
  the question with the lanes waiting on it and the time it was asked.
- **R13. A relayed owner quote is checked against the recorded text.** When a
  manager, a worker or any other session relays "the owner said X" as grounds
  for an action, the director looks for the owner's recorded text on that
  subject before it acts on the relay. When the recorded text says X, the
  director may act on it and names the record it checked. When the recorded
  text says something else, or there is none, the director declines to act on
  the relay, shows the relayed text and the recorded text (or says none is
  recorded) side by side in its reply and its report, and asks the owner only
  if the question isn't already waiting (R12).
- **R14. No director blocks on the owner.** A director never waits on the
  owner from a turn the owner didn't start. It asks in a message, records the
  question as waiting, and keeps every lane that doesn't depend on the answer
  moving. A lane that does depend on it waits on that question alone. Each
  director report lists every question waiting on the owner with its age and
  the lanes waiting on it, and the director asks again on the skill's existing
  re-ask rule, never as a second question from another lane.

### Non-functional

- **R15. One new entry kind at most.** The alignment call and the hold reuse
  what the coordinator record already has: its append-only log entries and
  its hold rows. The feature adds at most one new entry kind, and no new
  record section. Nothing it adds is ever rewritten in place: a later call is
  a new entry.
- **R16. The call is a record other tools read.** An alignment call has stable,
  named fields, at least the pull request, the head, the call value, the plan
  sources and the reason, in a fixed grammar the skill documents and a
  checker refuses to break. A tool other than the coordinate skill can read
  every call of a run without parsing prose.
- **R17. No authority comes from the review.** Recording a call or a hold
  grants and withholds no merge, close or release authority and defines no
  grant or level. Who merges a lane pull request after the director's call
  stays with the workspace's authority configuration, read as the reviewer
  concept reads it today: a director without the merge grant sends the call
  and its own reading up to its reviewer, and the merge is taken by whoever in
  its calling hierarchy holds the grant, at the head the call names.
- **R18. Roles stay where they are.** Nothing in this feature changes a
  session's role. This feature treats a role as changing only on an
  intervention from a session above it in its calling hierarchy, or from a
  person, and adds no such intervention: a hold, a call, a declined relay and
  a lane's question are none of those. It leaves the named roles' rules on
  how a role is set and kept, a succession keeping its role included, as they
  are.
- **R19. It runs before provenance.** A director can do all of the above with
  skill text and the record as it is plus the one new entry kind, before
  standing-rule provenance gives entries a source. Where the relay check of
  R13 reads recorded owner text, it reads the record's existing owner-decision
  rows; the later provenance work may change where that text is read from,
  and the design names where.

## Acceptance Criteria

- [ ] A director supervising two lanes is handed a lane pull request that
  contradicts a recorded owner decision. It records a `diverges` call for the
  pull request's head naming that decision, and a hold on the pull request
  whose recorded reason names the decision, whose receiver is the lane's
  manager and whose release is a new head re-read by the director. (R1, R2,
  R4, R7)
- [ ] With that hold standing, the manager's land check reports the pull
  request as held and no merge of it at the held head succeeds through the
  skill's merge step. (R7)
- [ ] The held lane's manager's next report names the held pull request, the
  hold's reason, the director as the session it waits on, and the release.
  (R8)
- [ ] After a new head is pushed to the held pull request and before the
  director records a call for that head, the hold still stands and a director
  start lists the pull request as held. After the director records `fits` for
  the new head, the hold is lifted and the lift names the head it was lifted
  on. (R9)
- [ ] A director re-read that calls `diverges` again on the new head leaves the
  hold standing. (R9)
- [ ] A lane pull request that touches no plan source and is merged or
  recommended has exactly one recorded call for its merged head, whose reason
  is one line and whose plan sources are `none`. (R3, R5)
- [ ] A milestone verdict pull request that is merged or recommended has a
  recorded call for its head that names, by number, each Evidence clause of
  its milestone it was judged against. (R3, R6)
- [ ] A call recorded for one head is not reported as the call for a different
  head of the same pull request: after a new push, the list read reports the
  new head without a call until one is recorded. (R5, R11)
- [ ] A lane pull request merged with no alignment call for its merged head is
  reported as unreviewed, with its pull request and head, in the report of the
  next director start. A call recorded for that head afterwards is listed as
  recorded after the merge. (R10)
- [ ] The read the skill names lists every alignment call of a run with pull
  request, head, call, plan sources and reason as separate fields, and every
  merge or recommendation of the run with its head's call or `unreviewed`.
  (R11, R16)
- [ ] A checker the skill ships refuses an alignment call entry missing the
  head, the call value or the reason, or carrying a call value outside the
  three. (R4, R16)
- [ ] A manager relays "the owner said X" while the owner's recorded text on
  that subject says Y. The director takes no action grounded on the relay,
  and its reply and its next report show both X and Y. With no recorded text
  on that subject, the reply says none is recorded. (R13)
- [ ] Two lanes raise the same question for the owner. The owner receives it
  once, and the director's record shows one waiting question listing both
  lanes. (R12)
- [ ] A lane raises a question whose answer the owner already recorded. The
  director answers it from the record, naming the record, and the owner is
  not asked. (R12)
- [ ] With a question unanswered by the owner for a day, the director's
  reports list it with its age and the lanes waiting on it, lanes that don't
  depend on it keep being dispatched and landed, and no second lane asks the
  owner the same question. (R12, R14)
- [ ] No turn the owner didn't start ends with the director waiting on an
  interactive question to the owner. (R14)
- [ ] The feature's diff adds at most one entry kind to the record's list of
  kinds and no new record section, and changes no existing entry kind's
  grammar. (R15)
- [ ] No text the feature adds says a role, a call or a hold holds, needs or
  implies a merge, close or release grant, a level, or a right to change a
  session's role. (R17, R18)
- [ ] A director with no merge grant that calls a lane pull request `fits`
  doesn't merge it; it sends the call and its own reading to its reviewer.
  (R17)

## Out of Scope

- **Correctness review of a pull request.** The worker's review round and the
  manager's land step own it; the director doesn't repeat it.
- **Granting merge, close or release authority, or defining levels.** The
  workspace's authority configuration owns that; this feature only reads the
  answer.
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

## Known Limitations

- **The named roles aren't installed yet.** This feature needs the director
  role in the record and the director's expectation list in the skill, which
  the named-roles plan (shirabe#1483) builds and which isn't merged. Until it
  lands, nothing tells a session it is a director, so none of this applies.
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

- **Triage line.** A full read for milestone-marking, plan-changing and
  owner-decision-touching pull requests; a one-line call for the rest (R3).
  Alternatives: a full read for every pull request, which makes the routine
  case cost what a milestone costs and stalls the director; or leaving the
  depth to the director's judgment each time, which leaves no way to check
  that a milestone got a full read. The chosen line is checkable from the pull
  request's holding and its changed files.
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
- **Whether a manager waits for the call is not decided here.** A manager
  holding a merge grant can land its workers' pull requests at its own land
  step before the director reads them; the named roles have it report those
  merges up. This PRD doesn't change that expectation. It requires that every
  merge either had a call for its head or is reported as unreviewed (R10), so
  a merge that went ahead without one stays visible.
- **One new entry kind, not a new section.** The call is a log entry because
  entries are already append-only and already carry the milestone goal-fit
  judgment; a new section would duplicate that machinery. Whether the call is
  the existing goal-fit entry widened or one new kind is the design's choice,
  within R15.
- **How the director finds what a pull request touches.** The requirement is
  that the call names its plan sources (R2) and that the triage line can be
  checked (R3). How the director finds them, from the pull request's holding,
  its changed files and the record's owner-decision rows, is the design's
  question.
