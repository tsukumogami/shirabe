---
schema: prd/v1
status: Done
problem: |
  Under `/coordinate`, a worker can put a choice straight to the human, evidence that arrives
  after a decision goes back to the human as a bare "decide", and a coordinator can list a
  choice in its status table with no recommendation even when the evidence settled it
  inside the coordinator's own authority. Nothing holds a decision until the coordinator
  has judged it, a decision that does reach a person arrives without the context needed to
  answer it in one pass, and an open decision doesn't survive the coordinator's restart.
goals: |
  A decision reaches a person only after a coordinator has judged it and found it isn't its
  own to settle, one at a time, as context, problem, and question with the recommendation
  first. Evidence and worker questions reach a coordinator's verdict before anything
  reaches a person, coordinators nest by the same rules, and open decisions survive a
  restart. Every refusal is a deterministic check with a passing and a failing test.
source_issue: 435
absorbed:
  - docs/briefs/BRIEF-coordinate-decisions.md
---

# PRD: Decisions and escalation in the coordinate skill

## Status

Done

Absorbed [BRIEF-coordinate-decisions](docs/briefs/BRIEF-coordinate-decisions.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed why this feature exists: a coordinator's value is its judgment, and
nothing in the `/coordinate` workflow made a coordinator exercise it before a decision
reached a person. It was written after tsukumogami/niwa#330, where a worker's approved
option met a mixed result from a check a person ran, the worker handed it back as
"decide", and a coordinator listed "decide whether to ship" with no recommendation although
the evidence settled it within the coordinator's authority. Its four gaps (workers
addressing the human, evidence bypassing the verdict, choices with no recommendation, and
questions in the wrong shape), plus decisions lost on a restart and the nesting of
coordinators, are this document's Problem Statement.

The outcome it asked for is that the person running an effort sees fewer decisions, each
judged first and arriving alone as context, problem, and the question with the
recommendation first, and that a coordinator can no longer let a decision bypass its own
judgment. Those are this document's Goals. Its five journeys (a worker's question,
evidence after a settled decision, a decision that really is the person's, nested
coordinators, and a restart) survive as the User Stories, and its boundary, including the
`/decision` skill, niwa and koto, and what a session prints outside the workflow, survives
as Out of Scope.

## Problem Statement

A coordinator exists so the person above it doesn't have to follow every unit of work,
and its most valuable output is judgment: settling what it can and bringing up only what
it can't, with a recommendation. The `/coordinate` skill states this in prose ("ask each
such decision once, with a recommendation"), and nothing in its workflow holds a
coordinator to it.

In tsukumogami/niwa#330 a worker got an option approved through `/decision`. The human then
ran a check the decision had marked untested and got a mixed result. The worker handed that
result straight to the human as "decide". A coordinator listed it in its status table as
"decide whether to ship" with no recommendation, though the evidence had settled the
question within the coordinator's authority. The human had to catch it.

Four gaps let that happen, and a fifth makes it worse after a restart:

- **Workers address the human.** A worker's brief names the coordinator as its only source
  of direction, but a question the worker puts to the human, in its report or in its own
  session, is never judged by the coordinator.
- **Evidence bypasses the verdict.** A settled decision can be reopened by what happens
  next (a check someone ran, a measurement, a worker's report). That evidence goes to
  whoever is nearest as a fresh question, and the coordinator's judgment is skipped.
- **Choices reach the human without a recommendation.** The progress table's "Blocked on
  you" row takes free text. Nothing refuses "decide whether to ship" with no
  recommendation and no reason.
- **The question arrives in the wrong shape.** Asked without context the answer comes back
  as a question about what the options mean; asked in a batch the decisions blur. The
  operator behind the comment on shirabe#435 asked three times for one shape: context,
  then the problem and why the coordinator can't settle it, then the question with the
  recommendation first, one decision at a time.
- **Decisions don't survive a restart.** The coordinator's record holds holdings,
  deferrals, side effects in flight and reversals, and nothing about a decision. A
  coordinator that restarts while a decision is with the human either drops it or asks it
  again as new, and GitHub can't tell a successor it exists.

Coordinators nest in practice: a roadmap coordinator is dispatched by a workspace
coordinator, which carries decisions up to a person. The skill's glossary already says that
"the human" means whoever dispatched the coordinator, so the same rules must hold when that
is another coordinator, and a decision that is with the coordinator above must not be shown
to a person as a question for them.

## Goals

The person running an effort sees fewer decisions, and each one is ready to answer: it has
been judged by a coordinator and found not to be the coordinator's, and it arrives alone as
a paragraph of context, a paragraph stating what's unresolved and why the coordinator can't
settle it, and then the question with the recommended option first and its reason.

A coordinator can't let a decision bypass its own judgment. Evidence arriving after a
decision is re-judged before anything reaches a person; a worker's question is received by
the coordinator; a decision with the coordinator above is shown as such; a restart neither
loses a decision nor asks it twice. Replayed against the workflow, the niwa#330 sequence
ends with the coordinator's verdict recorded and no question put to the human.

These properties hold because checks the coordinator can't talk its way past enforce them,
not because the skill asks nicely: every refusal is a deterministic check with a passing
and a failing test.

## User Stories

- **A worker's question.** As a roadmap coordinator, when a worker's report asks the human
  to decide whether to ship with a mixed result, I want the question to land with me as an
  open decision, so that I answer the worker or escalate with my own recommendation and the
  human hears nothing from the worker.
- **Evidence after a settled decision.** As a coordinator, when the human tells me a check
  the decision marked untested came back mixed, I want the decision to reopen to my verdict
  rather than to the human, so that I read the evidence, find the question is inside my
  authority, and settle it with a recorded reason. This is niwa#330 ending the way it
  should have.
- **A decision that really is the human's.** As the person running an effort, when a
  coordinator finds the evidence points to dropping a feature from the roadmap, I want one
  message about one decision with its context, the problem and why it's mine, and the
  question with the recommended option first, so that I can answer it in one pass; and I
  want the status table to show the same decision as blocked on me, with the
  recommendation.
- **Nested coordinators.** As a roadmap coordinator dispatched by the workspace
  coordinator, when my verdict is that a decision needs a person, I want it to go to the
  workspace coordinator in the same shape, which judges it in turn, and I want my status
  table to show the decision as with the workspace coordinator rather than as a question
  for whoever reads it.
- **A restart.** As a coordinator restarted after a crash while a decision was waiting on
  the human, I want to find the decision still open with its recommendation and who it's
  waiting on, so that I neither drop it nor ask it a second time as new.

## Requirements

### Terms

- **The dispatcher**: whoever started the coordinator, a person or another coordinator.
  This is what the skill's glossary calls "the human"; this PRD says "the dispatcher" for
  that sense and "a person" only for a person.
- **Entry**: one decision the coordinator holds, with the fields of R1.
- **Evidence**: a fact bearing on an entry that arrives after it was opened: a check a
  person ran, a measurement, a worker's report, or an answer that arrives after the entry
  was withdrawn (R9).
- **Decider**: koto's automatic classifier on an evidence field, whose answer is recorded
  beside the agent's.

### The decision record

- **R1. Entries are recorded where a successor finds them.** A coordinator holds one entry
  per decision it has opened in its scope, in the same durable store its successor reads on
  start. An entry carries a stable identifier, unique in the scope and never reused; the
  question; the options; the state; the source (the worker topic or the coordinator and
  entry it came from, when it came from one); the recommendation and its reason; the
  context and the problem; the grounds that make it not the coordinator's (R3); the
  target it's escalated to; when the escalation was sent; every item of evidence recorded
  against it, in order, each with its source and time; the outcome, its reason and who
  decided, once settled; and when it last changed. None of these is something GitHub can
  recompute: every one is the coordinator's judgment or a fact about a message. An entry's
  identity, and the order of its evidence, survive a restart and a second coordinator run
  against the same record: nothing that identifies an entry or an evidence item is local to
  one run. The record stays within its size ceiling: a settled entry that owes nothing is
  compacted to its question, outcome and decider, and a write that would still exceed the
  ceiling is refused by a check rather than failing on GitHub.
- **R2. Four states, fixed transitions.** An entry's state is `proposed`,
  `coordinator-verdict`, `escalated`, or `settled`. The only transitions are:
  1. `proposed` to `coordinator-verdict`, when the coordinator takes it up;
  2. `coordinator-verdict` to `settled`, with a settle verdict (R3);
  3. `coordinator-verdict` to `escalated`, with an escalate verdict (R3), when no other
     entry is escalated (R8);
  4. `escalated` to `settled`, with an answer (R11);
  5. any state to `coordinator-verdict`, when evidence is recorded (R4); for an entry
     already in `coordinator-verdict` the state stays and the evidence is appended.

  Every other transition is refused by a check and leaves the stored entry byte for byte
  as it was. No entry reaches `escalated` without a verdict made in `coordinator-verdict`.
- **R3. A verdict carries its reasons.** Leaving `coordinator-verdict` requires a verdict,
  and a verdict missing any part is refused:
  - settle: the outcome and its reason;
  - escalate: a recommendation that is one of the options, its reason, a context statement
    (what is being decided and why it matters now), a problem statement (what is
    unresolved and why the coordinator can't settle it), and at least one of four grounds:
    it changes the effort's scope; it reverses or extends a decision the dispatcher
    supplied; it is a choice whose options need a step the workspace reserves for a
    person; or it is outside the coordinator's scope.

  A text field counts as empty when it is empty after trimming whitespace. The coordinator
  may instead hold its verdict, with a reason naming what it waits on (a fact a worker is
  finding, a measurement, an answer from elsewhere). A held entry stays in
  `coordinator-verdict`, blocks no dispatch and no other step, and comes back for a verdict
  when evidence or an answer arrives for it or the coordinator takes it up again; the hold
  is recorded on the entry with its reason.
- **R4. Evidence reopens to the verdict, never to the dispatcher.** Recording evidence
  against an entry in any state appends it to the entry's evidence and moves the entry to
  `coordinator-verdict`. No transition goes from evidence to `escalated`; an escalation
  after evidence needs a new verdict under R3.
- **R5. Adoption and canonical form.** A record written before this feature, holding no
  entries, is still adopted unchanged. A record with entries is adopted only when it is in
  canonical form (rendering what was parsed reproduces it byte for byte, the rule the
  record already has); an entry with an unknown state, a duplicate identifier, or a
  missing required field makes the record non-canonical.
- **R6. Taking entries over.** On a restart, and at a rotation's start, the successor
  takes over every entry that isn't settled, before its first dispatch: a `proposed` entry
  is taken up (R2 transition 1); a `coordinator-verdict` entry is resumed as it stands; an
  `escalated` entry whose escalation was sent stays escalated and isn't sent again (R7),
  and one whose escalation was never sent (a crash between the verdict and the message)
  has its message rendered and sent then, once. A rotation's handoff carries
  every entry that isn't settled; settled entries are not carried. A roadmap record can't
  close while any entry isn't settled; the close then reports what it waits on and returns
  to waiting for events, so an unanswered escalation never loops the run.

### What reaches the dispatcher

- **R7. One escalation message, rendered from the verdict, once.** The message that puts a
  decision to the dispatcher is produced by the workflow from the entry's recorded verdict,
  not composed by the coordinator, and delivered through the channel the coordinator
  reports on. It carries exactly one decision, in this order: the context paragraph; the
  problem paragraph; then the question with its options, the recommended option first,
  with its reason. The rendering is refused when the recommendation, its reason, the
  context or the problem is empty, when the recommendation isn't one of the options, or
  when the entry's escalation was already sent for this verdict. A restart never renders
  it again.
- **R8. One decision at a time.** At most one entry is `escalated` at a time. An entry
  whose verdict is to escalate while another is escalated waits in `coordinator-verdict`
  with that verdict recorded, and the oldest waiting one is escalated when the escalated
  entry is settled or withdrawn. Its verdict is checked again under R3 at that point. A
  withdrawn entry is back in `coordinator-verdict` and escalates again only with a new
  verdict.
- **R9. A reopened escalation is withdrawn.** When evidence reopens an `escalated` entry,
  the workflow renders a withdrawal notice to the dispatcher naming the decision and
  saying no answer is needed. An answer that arrives for a withdrawn escalation is
  recorded as evidence on the entry, not as a settlement.
- **R10. The progress table shows decisions only from entries.**
  - A "Blocked on you" row that asks for a decision is rendered only from the escalated
    entry, and shows its question, recommendation and reason. The renderer refuses the
    row when the recommendation or reason is empty.
  - A free-text "blocked on you" need is refused when it matches the closed list of
    decision phrasings, so a row like "decide whether to ship" can't be written by hand.
    A need that isn't a choice among options (a credential; a step the workspace reserves,
    such as running a release) is accepted as text. The list is defined in one place, used
    by R10, R15 and R17 alike, and comes with fixtures of at least three refused and three
    accepted phrasings, including an accepted need whose wording resembles a decision.
  - An entry escalated to a coordinator is shown as with that coordinator, naming it, in
    a row that asks the reader nothing.
  - An entry in `coordinator-verdict` whose escalation waits (R8) is shown as with the
    coordinator; a held entry is shown with what it waits on.
  - Every other free text the table can carry (the "next or needs" text for any row) is
    held to the same phrasing check, and the free-text "Waiting on the human" section of a
    report gives way to the table's rows, so no human-facing surface of the workflow can
    carry a decision that didn't come from an entry.
- **R11. An answer settles an escalated entry.** An answer names the entry and gives one
  of its options, or a new outcome with its reason; either settles the entry, recording
  the outcome and who decided. An answer for an entry in any other state is recorded as
  evidence (R4, R9), which reopens it to the coordinator's verdict. An answer
  that reverses or extends a decision the dispatcher supplied is also recorded as a
  reversal, as today. The coordinator records the answer as it was relayed on its
  dispatcher's channel; this skill doesn't vet who sends a message.

### Nesting and the way back down

- **R12. The escalation target is the dispatcher, fixed for the run.** A run is started
  either reporting to a person, the default, or reporting to a named coordinator. Every
  escalation of that run goes to that target under R7, whichever it is.
- **R13. An escalation from below is the receiver's own decision.** A coordinator that
  receives an escalation from a coordinator it dispatched records it as a `proposed` entry
  whose source is that coordinator and its entry identifier, and runs it through its own
  verdict. When the receiver's entry settles, whether by its own verdict or by an answer
  from above, the workflow renders an answer to the source coordinator naming the source
  entry, the outcome, its reason and who decided; the source coordinator records it under
  R11, so the lower entry settles with the final decider named.
- **R14. The answer reaches the worker.** When an entry whose source is a worker settles,
  the workflow renders the outcome and its reason to that worker as a message, the same way
  a rebrief reaches it.

### Worker questions

- **R15. What counts as a worker's question.** A worker's report has a Questions part in a
  fixed shape the brief defines: numbered items, each optionally citing an entry
  identifier. The questions of a report are those items, plus every line outside the part
  that ends with a question mark or matches the closed decision-phrasing list (R10).
- **R16. Every question becomes the coordinator's.** Each question of a report becomes a
  `proposed` entry with the worker as its source, or, when it cites the identifier of an
  existing entry, evidence on that entry (R4). An uncited question is never matched to an
  existing entry by judgment. Nothing in a report reaches the dispatcher except through an
  entry's verdict.
- **R17. A question addressed to a person is refused and re-routed.** A question that
  matches the decision-phrasing list or addresses a person (by the patterns that list
  names, such as "the human", "you decide", "your call") is refused as addressed: the
  report itself is accepted, the question is recorded as an entry under R16 with the
  refusal noted, and the workflow renders a reply to the worker saying its questions go to
  the coordinator, which answers them or escalates them with a recommendation. The check
  runs at a point every worker report passes; the design names it and says why a worker
  can't route around it.
- **R18. The brief states the channel.** Every rendered brief carries a fixed sentence
  telling the worker that its questions go to the coordinator in the Questions part,
  numbered, and never to a person, and that the coordinator answers them or escalates them
  with a recommendation. It also tells the worker to repeat, in each report, any question it
  has had no answer to, so a question lost between the report and its record comes back.

### Deciders, the skill file, engine limits

- **R19. Deciders never act.** A decider may classify whether a decision is within the
  coordinator's authority, or what a worker's report asks. Its answer is recorded beside
  the coordinator's and no transition depends on it; making it act is out of scope. Each
  declared decider has at least one fixture per answer. Every refusal in this PRD is a
  deterministic check.
- **R20. The template is the source of truth.** The koto template carries the decision
  flow, its states and its checks. Every state and check name the skill file mentions
  exists in the template, and the skill file states no transition or refusal condition of
  the decision flow that the template doesn't.
- **R21. Engine limits and dependencies.** The design names what checks running in the
  caller's environment (koto#261) leaves open. Implementation starts from a default branch
  that contains the dispatch path (shirabe#404) and reconcile (shirabe#406), and targets
  the koto floor shirabe declares at that point (0.14.0 once shirabe#457 has landed); it
  doesn't wait on shirabe#457 itself.

### Tests

- **R22. Every check has a passing and a failing test.** At least one of each for: every
  transition R2 permits and a sample of those it refuses, including `proposed` to
  `escalated` and evidence to `escalated`; each missing part of a settle and an escalate
  verdict (R3); evidence in each of the four states (R4); adoption of a pre-feature record
  and refusal of a record with a malformed entry (R5); take-over of each state (R6); each
  empty field, a recommendation outside the options, and a second rendering (R7); a second
  escalation while one is outstanding (R8); a withdrawal and a late answer (R9); each
  progress-table rule with the phrasing fixtures (R10); an answer on an escalated, a
  withdrawn and a settled entry (R11); the target for each start mode (R12); a
  three-level round trip (R13); the answer reaching a worker (R14); a cited, an uncited and a person-addressed question,
  and a question-shaped line outside the Questions part (R15 to R17); the brief sentence
  (R18); and the skill-file check (R20). The suite runs in CI.
- **R23. The niwa#330 replay.** A test drives the template through the niwa#330 sequence: a
  decision's option approved and the entry settled; a check the decision marked untested
  returns a mixed result as evidence; the worker's report then asks a person to decide
  whether to ship. The test passes only when the coordinator's verdict is recorded before
  any escalation is rendered, and when no progress table rendered during the sequence
  holds a decision row without a recommendation. It fails when replayed against a variant
  of the template that routes evidence straight to escalation.

## Acceptance Criteria

- [ ] A record fixture with entries in each state renders and parses back byte for byte;
  a successor run started against it loads each entry that isn't settled with its state,
  recommendation, target and sent time unchanged.
- [ ] Each of the five permitted transitions succeeds, and `proposed` to `escalated`,
  `settled` to `escalated`, and evidence to `escalated` are refused with the stored entry
  byte for byte unchanged.
- [ ] A settle verdict without an outcome or without a reason is refused; with both it
  passes.
- [ ] An escalate verdict is refused for each of: empty recommendation, empty reason, empty
  context, empty problem, a whitespace-only field, a recommendation outside the options,
  and no ground; with every part present it passes, including with the `outside-scope`
  ground alone.
- [ ] A held verdict without a reason is refused; with one, the entry stays in
  `coordinator-verdict`, a dispatch after the run's first goes ahead, the run reaches the
  wait hub, and evidence on the entry brings it back for a verdict.
- [ ] A second coordinator run against a record the first run wrote, replaying the same log
  sequence numbers, records its own report's questions as new entries and never mistakes
  the first run's evidence for its own.
- [ ] A write that would take the record past its size ceiling is refused by the check with
  its own verdict, and a settled entry that owes nothing is compacted at the next write.
- [ ] Evidence recorded against an entry in each of the four states leaves it in
  `coordinator-verdict` with the evidence appended after any earlier evidence, source and
  time included.
- [ ] A record written before this feature is adopted; a record whose entry has an unknown
  state, a duplicate identifier, or a missing required field is refused as non-canonical.
- [ ] After a restart, a `proposed` entry is taken up, a `coordinator-verdict` entry is
  resumed, an `escalated` entry whose message was sent stays escalated with no second
  message rendered, and an `escalated` entry with no sent time has its message rendered
  once, all before the first dispatch.
- [ ] The escalation message for a fixture entry is one decision: the context paragraph,
  then the problem paragraph, then the question with the recommended option first and its
  reason; rendering it a second time for the same verdict is refused.
- [ ] With one entry escalated, a second escalate verdict leaves the second entry in
  `coordinator-verdict` with its verdict recorded; settling the first escalates the
  second.
- [ ] Evidence on an escalated entry renders a withdrawal notice; an answer arriving
  afterwards is recorded as evidence, not a settlement.
- [ ] The progress table renders an escalated entry's row with its question,
  recommendation and reason; refuses the row with an empty recommendation or reason;
  refuses each refused phrasing fixture as free text, including "decide whether to ship",
  in a blocked need and in any row's next-or-needs text; and accepts each accepted fixture.
- [ ] A roadmap close with every feature done and one entry escalated and sent reports what
  it waits on and returns to the wait hub, without looping.
- [ ] An entry escalated to a coordinator renders as with that coordinator, by name, and
  its row contains no question to the reader.
- [ ] An answer naming an option settles the escalated entry with the outcome and who
  decided; an answer that reverses a supplied decision also adds a reversal; an answer for
  a settled or withdrawn entry is appended as evidence and leaves it in
  `coordinator-verdict`.
- [ ] A run started reporting to coordinator X renders its escalations addressed to X; a
  run started with no such setting addresses a person.
- [ ] In a three-level fixture (person, workspace coordinator, roadmap coordinator), the
  roadmap coordinator's escalation becomes a `proposed` entry at the workspace coordinator
  with its source; settling it there renders an answer that settles the roadmap
  coordinator's entry naming the final decider.
- [ ] A settled entry whose source is a worker renders a message to that worker with the
  outcome and reason.
- [ ] A report with an uncited question yields a new `proposed` entry; with a question
  citing an existing identifier, evidence on that entry; with "please decide whether to
  ship" addressed to the human, a refusal noted on a new entry and a rendered reply to the
  worker; with a question-shaped line outside the Questions part, an entry.
- [ ] Every rendered brief contains the fixed channel sentence and the instruction to repeat
  unanswered questions, and a report written to the brief's Questions shape is parsed by the
  question check.
- [ ] Each declared decider on the decision flow has at least one fixture per answer, and
  flipping its answer changes no transition.
- [ ] A check over the skill file passes when every state and check name it mentions is
  in the template, and fails on a fixture that names a state the template doesn't have.
- [ ] The design names what koto#261 leaves open, and the declared koto floor is the one
  shirabe declares when implementation starts.
- [ ] Each check listed in R22 has a passing and a failing test, and CI runs the suite.
- [ ] The niwa#330 replay passes against the new template, recording the coordinator's
  verdict before any escalation, with no decision row lacking a recommendation in any
  table rendered along the way; it fails against the variant that routes evidence straight
  to escalation.

## Out of Scope

- The `/decision` skill. A worker that runs it still does so as today; this work covers
  what happens when its outcome, or evidence against it, comes back to a coordinator.
- Changing the worker skills (`/work-on`, `/execute`, `/deliver`, `/scope`), unless the
  design shows the worker-side check can't live at a point every report already passes.
- Controlling what a worker's session prints for a person who happens to watch it, or what
  a coordinator types in its own chat outside the workflow's messages.
- niwa, and any change to koto. Engine limits met here are cited and proposed, not built.
- The dispatch path and reconcile. This work builds on the report and brief they carry and
  doesn't reopen them.
- Letting a decider act. Deciders here classify and are recorded; promotion is later work,
  if ever.
- Showing a person the decisions a coordinator settled on their behalf. The record holds
  them for any reader; a view of them is not part of this feature.

## Known Limitations

- **Checks run in the coordinator's environment (koto#261).** A coordinator that rewrites
  its own tools, or its files, can make any check read what it wants. The checks here hold
  against a wrong submitted value or a skipped step, as the record's do, not against that.
- **What a session prints outside the workflow.** A worker that ignores its brief and asks
  a person watching its session isn't caught by a check the coordinator runs, and a
  coordinator can still type a question to a person in its own chat. The workflow's
  messages and the progress table are what these checks govern; they are also what a
  person reads to follow an effort.
- **The decision-phrasing list is closed.** It catches the phrasings it lists. A missed
  phrasing in a report still can't reach the dispatcher unjudged, since every question
  becomes an entry, but a missed phrasing in a free-text need can reach the progress
  table.
- **Senders aren't vetted.** An answer is recorded as relayed on the dispatcher's channel.
  Who may message a session is the harness's and the workspace's to decide.
- **A gone target.** An entry escalated to a coordinator that no longer exists stays
  escalated until the dispatcher's channel says otherwise; this feature adds no detection
  of a gone target beyond the quiet-worker check that exists.
- **The coordinator's relay.** Questions travel mostly by message, and a message report
  reaches the check as the text the coordinator relayed; a coordinator that drops a
  question from its relay isn't caught. The check holds against the worker.
- **Pull request text.** A worker's pull request body and comments are a durable path to a
  person, linked from the merge-order table, that no check reads.
- **A crash before the record write.** Questions extracted from a report and not yet written
  when the coordinator crashes aren't recovered by the successor, whose log is new; the brief
  asks the worker to repeat unanswered questions, which brings them back at the next report.

## Decisions and Trade-offs

- **The escalation target is the dispatcher, fixed for the run.** The glossary already
  defines "the human" as whoever dispatched the coordinator. A per-decision target would
  let a roadmap coordinator skip the workspace coordinator, reopening the niwa#330 route
  one level up.
- **"Needs your decision" is structural, with a textual backstop.** A decision shows in the
  status table only from an escalated entry, and free text matching the decision-phrasing
  list is refused. The niwa#330 row was free text; a check on free text alone couldn't
  verify a recommendation against a verdict.
- **One escalation at a time, queued.** The operator asked for one decision at a time.
  Queuing the rest in `coordinator-verdict` keeps the four states intact rather than adding
  a fifth.
- **Every worker question becomes an entry, whatever its wording.** Refusing
  person-addressed questions is the check the issue asks for; routing every question to
  the coordinator is what makes a missed phrasing harmless. Matching a question to an
  existing entry needs the entry's identifier, so no judgment call can attach a question to
  a settled decision and hide it.
- **Evidence is append-only.** The niwa#330 replay depends on keeping the first result
  when a second arrives.
- **Where entries live, and where the worker-side check lives, are design questions.** The
  requirements state what must hold (a successor finds open entries; a check every worker
  report passes); the design weighs a record section against session state, and the brief
  against the worker skills against the coordinator's report intake.
