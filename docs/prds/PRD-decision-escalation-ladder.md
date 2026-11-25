---
schema: prd/v1
status: Draft
problem: |
  A person running work across agent sessions is told sessions are blocked on
  them when the owning session did no work on the question, or when the
  question belongs to a coordinator in between. The rules that prevent this
  are prose that long-running sessions stop applying. A question that does
  reach the person has no durable home, nothing lists what is waiting on
  them, and an answer given to one session does not stop the next from asking.
goals: |
  A session that hits a question tries to settle it before anyone else sees
  it, and the workflow prompts it to at that moment. Every question and every
  decision is on the record with who decided. The person can open any session
  in a reporting chain, see what is waiting on them, answer in the terminal,
  and have that answer take effect and carry through the chain.
upstream: docs/briefs/BRIEF-decision-escalation-ladder.md
---

# PRD: Decision Escalation Ladder

## Status

Draft

## Problem Statement

A person who runs work across several agent sessions gets told, often, that a
session is blocked on them. Usually the session that hit the question did no
work on it first. A worker's brief asks for one-line questions in its report,
so the session that knows the problem best contributes the least, and whoever
is above it rebuilds the options from a sentence.

Much of what gets reported as blocked on the person isn't theirs. A session
outside what it was told it may do says "blocked on the person" when the call
belongs to the coordinator above it. The few items that need the person arrive
mixed with many that don't.

The rules that would prevent both exist as prose. Coordinators carry them as
text copied from brief to brief and stop applying them partway through a long
session. The workflow templates that drive a worker let it stop at roughly a
dozen points with nothing but a free-text reason, and neither the structured
decision skill nor the lightweight decision protocol can do anything but pick
an option or assume one.

A question that does reach the person has no durable home. It sits in a
question prompt held open in one session, or in a file a coordinator keeps by
hand. When that session restarts or loses its context the options are gone. A
session that opens a question prompt when nobody is there stops, and has
stopped other sessions with it.

So the person cannot ask what is waiting on them across a chain of sessions,
and an answer they give one session stays there: the next session with a
similar question asks again.

## Goals

- A session that hits a question attempts to settle it before it stops or
  passes the question up, and is prompted to by the workflow at that moment
  instead of by an instruction it has to remember.
- A question goes to whoever it belongs to. What reaches the person is what
  needs the person.
- Every question, and every decision made about one, is recorded with who
  decided, so what is open and what was settled can be read for a whole chain
  of sessions, for part of one, or for one person.
- The person opens a session at any level, sees what is waiting on them with
  a recommendation and reasoned alternatives, and answers in the terminal.
  The answer takes effect with no further step from anyone.
- An answer the person gives is available to the rest of the chain, so a
  similar question later is settled from it.
- Nothing waiting is lost while the person is away or when a session loses
  its context.

## User Stories

**US1. A worker running alone, while the person is away.** As a person who
started a worker and left, I want it to try to decide a question itself, and
if it can't, to keep the question for me and carry on with what doesn't depend
on it, so that when I open it later I'm shown the question as it was written
and my answer is all it needs.

**US2. A question settled before it reaches me.** As a person running a
manager with several workers, I want a worker to decide what its evidence
supports and to send what it may not decide to its manager, so that my list of
open questions shows neither, and the record shows both with who decided.

**US3. Resolving with the top coordinator.** As a person running a director
over managers and workers, I want a question nobody below me may settle to
reach me once, with the recommendation the worker wrote, so that I answer it
at the director and it holds for everything in that lane.

**US4. Answering in the worker.** As a person who happens to be in a worker's
session, I want it to show me its questions, including one already passed up
to the director, and to accept my answer there, so that I don't have to switch
sessions and nobody above has to approve what I said.

**US5. A later worker reusing my answer.** As a person who already answered a
question, I want another session in the same chain to find that answer before
raising a similar one, so that I'm not asked the same thing twice.

**US6. Asking what is pending.** As a person returning to a coordinator after
time away, I want to ask it for everything pending at and below it and resolve
those in that session, so that I don't have to reconstruct the list from
reports.

## Requirements

Terms used below. A **session** is one agent session running a workflow. A
**coordinator** is a session that dispatched other sessions. The **person** is
the human running the work. A **question** is anything a session cannot settle
itself and needs someone else for. To **raise** a question is to record it for
someone else; to **pass up** is to change who a raised question is addressed
to. A **reporting chain** is a session, the sessions it dispatched, and so on
down. A **position** in a chain is a session or the dispatch anchor of one,
together with the successors the workflow engine has confirmed for it.

### Sorting and authority

**R1. Sorting by addressee.** Before a session reports anything as waiting on
someone, it classifies the item as its own to settle, as belonging to the
coordinator above it, or as belonging to a person. The addressee is recorded
as data that distinguishes a person from a position, never only as wording.

**R2. Settle unless reserved.** A session settles a question itself when its
evidence, an answer the person already gave, or the scope it was given covers
it, including cases it judges similar to one already answered. It passes a
question up only when settling it would: contradict an answer the person gave;
change the scope of the work; take an action that is irreversible,
outward-facing or spends money; or take a step the person reserved.

**R3. Who is above.** A session whose recorded dispatcher is another session
addresses that session. A session with no dispatcher, or whose dispatcher is a
person, addresses the person. A session whose dispatcher link was not recorded
addresses the person and marks the question as raised from an unlinked
session.

**R4. A coordinator applies the same rule.** A coordinator that is addressed
a question settles it under R2 or passes it up. Passing up does not create a
second question.

### Deciding first

**R5. The workflow prompts the attempt.** At every point where a worker
workflow lets the agent itself declare that it cannot continue or that a
question must go up, the workflow delivers the decide-first procedure at that
moment and does not accept the exit until the session has recorded either a
decision or a raised question for it. This covers the agent-declared exits of
`/work-on`, `/execute` and `/scope`. Stops the workflow decides mechanically,
such as a failed check or a refused merge, are unchanged.

**R6. Coordinators too.** A coordinator cannot pass a question up or present
it to the person without a recorded attempt to settle it. A need that involves
no choice (R12) is exempt.

**R7. A decision can end undecided.** The structured decision skill and the
lightweight decision protocol each gain an outcome in which no option is
chosen. That outcome carries the question, a recommendation, each alternative
with its reason, and what was missing to decide. The research behind it stays
available to whoever answers. Skills that call a structured decision accept
this outcome without failing.

**R8. Unattended, by cost to reverse.** When no person is present and a
session's evidence gives no clear answer, the session judges whether the
choice is cheap or costly to undo. Cheap: it decides, records the decision as
provisional, and continues. Costly: it raises a question and continues with
work that does not depend on the answer. Provisional decisions are listable as
a group for review.

**R9. Precedent before asking.** Before raising a question, a session reads
the answers the person has already given in its reporting chain. When it
judges that one covers the case, it settles its question from that answer and
records which answer it relied on.

### The record

**R10. One question, one identity.** Each question has one identity from the
moment it is raised. One read returns its whole history: who raised it, its
content, every addressee it has had, its answer, who answered, where, and
whether a person was present when it was raised and when it was answered.

**R11. Content.** A raised question carries its context, the problem, the
question itself, a recommendation with its reason, each alternative with its
reason, why the raiser may not settle it, and the work items waiting on it.
The content does not change after it is raised, and is at most 16 KiB.

**R12. Needs that are not decisions.** A credential only the person holds, a
step the person reserved, or an action outside the session's reach is recorded
in the same way as a question, with its kind and what is needed, and is
counted, listed and restored like one. It skips R5 and R6 and is presented as
a request. A credential need records that a credential was requested and
supplied, never the credential.

**R13. Every decision has a decider.** Every outcome of this procedure, a
session's own decision, a coordinator's, a person's, or a provisional one, is
recorded with what kind of decider made it.

**R14. What is open, in one read.** The workflow engine answers "what is
open" directly: a single read, with no joining by the caller, that returns the
open questions at and below a position, and another that returns the open
questions addressed to a given person. A question that has been passed up is
returned once. With about a thousand sessions in the store, on the storage
backend in use, each read returns within five seconds.

**R15. No question is invisible.** A question addressed to a person is
returned by the read for that person whether or not the session that raised it
has any recorded link to another session.

**R16. Lifetime.** An open question stays readable until it is answered, even
if the session that raised it has ended or been replaced. A person's answers
stay readable as precedent for as long as any session in the chain they were
given in is still live.

### Presenting and answering

**R17. Only when the person started the turn.** A session presents a question
to the person only in a turn the person started. In any other turn the
question waits on the record, the session continues with work that does not
depend on it, and when nothing else is left it ends its turn idle. It never
waits inside a question prompt.

**R18. Presented from the record.** What the person is shown comes from the
recorded question: its context, the problem, the question, the recommendation
first, and each alternative with its reason. The prompt can be understood
without any text printed before it.

**R19. Together, by impact.** A session presents everything pending for the
person, up to four questions per prompt, and continues until none are left.
Questions are ordered by the number of work items recorded as waiting on each,
most first, and oldest first among equals. A question that depends on another
pending question's answer is held until that one is answered.

**R20. Ask any session.** The person can ask any session what is pending at
and below it, and what is pending for them, and resolve those questions in
that session.

**R20a. One command, in any session.** A single command runs the whole
procedure on demand in any session, whether or not a workflow drives that
session: it reads what is pending at and below the session, applies R2 to each
question addressed to that session, and presents what remains for the person
under R17 to R19. A coordinator that carries its rules as brief text gets the
procedure this way; only the automatic prompting of R5 and R6 is absent for
it.

**R21. Answer anywhere, no ratification.** The person can answer a question
in any session that can read it, including one that neither raised it nor is
its current addressee. The answer takes effect when it is recorded: no other
session approves, forwards or re-asks it. It is recorded with the person as
decider and the session it was given in.

**R22. The asker finds the answer.** A session whose question was answered
elsewhere learns of the answer at its next workflow step, without relying on a
relayed message. A session that had ended can be resumed with the answer.

**R23. The person's answer is the one in effect.** When a person and a
session have both answered a question, every read returns the person's answer
as the one in effect. The session's answer stays on the record, and a session
cannot put its own back.

**R24. Answers reach the coordinators above.** An answer the person gave in a
worker is readable by every coordinator above that worker as an answer from
the person, by the same read R9 uses.

**R25. Exact restore.** A waiting question can be presented again, in the
session that raised it or in another, after that session has lost and rebuilt
its context. The presented question is byte-for-byte identical to what would
have been presented before.

**R26. Free-text answers.** When the person answers in their own words
instead of choosing an option, that text is recorded as their answer.

**R27. Guard on the question prompt.** A question prompt cannot open in a
turn the person did not start. An attempt to open one is refused and the
session falls back to R17. Where a turn's origin cannot be established, the
guard uses whether a person is attending the session. Question prompts that a
skill opens in a turn the person started behave as they do today.

**R28. Independent of the answering surface.** Recording an answer requires
only the question's identity, the answer, and who gave it. It does not depend
on running inside the session that raised the question or on that session's
harness.

### Shapes, compatibility and delivery

**R29. Session shapes.** Everything above holds for a worker with no
coordinator, a worker under one coordinator, a worker under two, and a worker
a person dispatched by hand, which is treated as having a person above it.

**R30. No change for sessions that raise nothing.** A session that never
reaches a point covered by R5 or R6 runs as it does today: no added prompts,
no added steps, and no change to its result.

**R31. Rules this supersedes.** The documents and directives that state the
following are changed to match this PRD, so no two rules disagree: an
unattended run follows its own recommendation and continues without waiting;
an unattended run with no coordinator stops when a question must go to a
person; a coordinator releases one question to the person at a time, oldest
first; a coordinator re-words and re-opens a question at each level; and
direction reaches a session only through the channel of whoever dispatched it.
Text relayed in a report or a pull request is still not the person's answer;
an answer the person gave in a session is.

**R32. One word for one thing.** The procedure's documents and prompts say
"raise a question" and "pass up". The existing decision-block status
`escalated`, which means a decision was handed to the heavier decision skill,
keeps its meaning.

**R33. Delivery order.** The workflow engine's part is released before any
skill depends on it, and the minimum engine version the skills check for is
raised to that release. Sessions already running when the skills change keep
their existing behaviour until they are restarted.

**R34. Dogfooding before done.** The feature is not done until it has been
used on real work in the tsukumogami organization, in one reporting chain with
a worker under a manager and a director, plus one unattended worker with no
coordinator. The run takes place on released versions of the engine and the
skills, and its record shows each of the following: a question settled below
the person; a question the person answered in a worker; a question the person
answered at the top coordinator; a waiting question restored after a loss of
context; and a question raised by the solo worker and answered when the person
returned. The loss of context may be induced. Each finding from the run is
fixed or filed as an issue before the feature is called done.

## Acceptance Criteria

Criteria marked **(checked)** are verified by automated tests. Criteria marked
**(observed)** depend on an agent's judgment, which no test in the repository
exercises, and are verified in the dogfooding run (R34).

### Sorting and authority

- [ ] (checked) A recorded question's addressee can be read as either a
  person or a position, and the two are distinguishable without parsing prose.
  (R1)
- [ ] (checked) A session with a recorded session dispatcher raises to that
  session; a session with no dispatcher, a person dispatcher, or an unrecorded
  link raises to the person, and the unlinked case is marked. (R3, R29)
- [ ] (checked) A question a coordinator passes up keeps its identity and is
  returned once by the open reads. (R4, R14)
- [ ] (observed) In the dogfooding run, no question addressed to the person
  is one a coordinator in the chain could have settled under R2. (R1, R2)

### Deciding first

- [ ] (checked) For each agent-declared exit of `/work-on`, `/execute` and
  `/scope` that this PRD covers, the exit is refused when no decision or raised
  question is recorded for it, and accepted when one is. (R5)
- [ ] (checked) The decide-first procedure text is delivered by the workflow
  on arrival at each such point. (R5)
- [ ] (checked) Mechanically decided stops take the same path, with the same
  result, as before this change. (R5, R30)
- [ ] (checked) A coordinator's attempt to pass a question up or present it
  without a recorded attempt is refused; a need with no choice is accepted.
  (R6)
- [ ] (checked) A structured decision and the lightweight protocol can each
  end with no option chosen, and that outcome carries the question, a
  recommendation, every alternative with a reason, and what was missing. (R7)
- [ ] (checked) `/design` and `/explore` each continue without error when a
  structured decision they started ends undecided. (R7)
- [ ] (checked) A decision recorded as provisional is returned by a listing
  of provisional decisions. (R8)
- [ ] (observed) In the dogfooding run, the solo unattended worker records at
  least one provisional decision or raised question, and continues other work
  instead of stopping. (R8, R17)
- [ ] (checked) A decision settled from an earlier answer records which
  answer it relied on, and that link can be read back. (R9)
- [ ] (observed) In the dogfooding run, at least one question is settled from
  an answer the person gave earlier in the same chain. (R9, R24)

### The record

- [ ] (checked) One read of a question returns its raiser, content, each
  addressee it has had, its answer, the answering decider and session, and
  whether a person was present at raise and at answer. (R10, R13)
- [ ] (checked) A raised question missing any of context, problem, question,
  recommendation with reason, alternatives with reasons, or the reason it is
  not the raiser's to settle is refused. (R11)
- [ ] (checked) Content over 16 KiB is refused, and content cannot be changed
  after the question is raised. (R11)
- [ ] (checked) A need that is not a decision is recorded with its kind, is
  returned by the open reads, and no field of a credential need holds a
  secret. (R12)
- [ ] (checked) A single engine read returns the open questions at and below
  a position, and a single engine read returns those addressed to a named
  person; neither requires the caller to combine results. (R14)
- [ ] (checked) With 1,000 sessions in the store on the storage backend in
  use, each open read returns within five seconds. (R14)
- [ ] (checked) A question raised by a session with no recorded links is
  returned by the read for the person it is addressed to. (R15)
- [ ] (checked) An open question is still returned after the session that
  raised it has ended and after it has been replaced by a successor. (R16)
- [ ] (checked) A person's answer is still returned as precedent after the
  session it was given in has ended, while another session in that chain is
  live. (R16)

### Presenting and answering

- [ ] (checked) In a turn not started by the person, an attempt to open a
  question prompt is refused, and the question remains open on the record.
  (R17, R27)
- [ ] (checked) A question prompt a skill opens in a turn the person started,
  with no recorded question behind it, opens as it does today. (R27, R30)
- [ ] (checked) The rendered presentation of a question contains its context,
  problem, question, the recommendation first, and every alternative with its
  reason. (R18)
- [ ] (checked) With six questions pending, they are presented four and then
  two, in descending order of recorded waiting work items, oldest first among
  equals; a question recorded as depending on another is not presented before
  that one is answered. (R19)
- [ ] (checked) A session asked for what is pending returns the open
  questions at and below it and those addressed to the person. (R20)
- [ ] (checked) The command of R20a, run in a session that no workflow
  drives, lists the open questions at and below it, records a settle or a
  pass-up for each one addressed to that session, and presents the remainder
  only when the person started the turn. (R20a)
- [ ] (checked) An answer recorded in a session that did not raise the
  question, and is not its addressee, closes it: it is no longer returned by
  any open read, with no further write from any other session. (R21)
- [ ] (checked) The answer records the person as decider and the session it
  was given in. (R21)
- [ ] (checked) After a question is answered in another session, the raising
  session's next workflow step reports the answer. (R22)
- [ ] (checked) With both a session's answer and a person's answer recorded,
  reads return the person's as the one in effect, the session's is still
  readable, and a later answer from a session does not displace the person's.
  (R23)
- [ ] (checked) An answer the person gave in a worker is returned by the
  precedent read run from each coordinator above it. (R24)
- [ ] (checked) The presentation rendered from the record after the raising
  session's working state is discarded is byte-identical to the one rendered
  before. (R25)
- [ ] (checked) A free-text answer is stored verbatim. (R26)
- [ ] (checked) An answer can be recorded given only the question's identity,
  the answer and who gave it, from a process that is not the raising session.
  (R28)

### Shapes, compatibility and delivery

- [ ] (checked) The sorting, raising, open-read and answering criteria above
  pass in fixtures for a worker with no coordinator, with one coordinator, and
  with two. (R29)
- [ ] (checked) A run of each affected workflow that reaches no covered exit
  produces the same states and result as before this change. (R30)
- [ ] (checked) None of the superseded statements in R31 remains in the
  skills' documents, references or directives. (R31)
- [ ] (checked) The procedure's documents and prompts do not use "escalate"
  for raising or passing up a question. (R32)
- [ ] (checked) The skills refuse to run the new steps on an engine older
  than the release that carries the engine's part. (R33)
- [ ] (observed) The dogfooding run of R34 has taken place on released
  versions, and the record output for each of its five events, all from one
  chain plus the solo worker, is attached to the pull request or issue that
  closes the work. (R34)
- [ ] (observed) Every finding from the dogfooding run has a linked commit or
  a filed issue. (R34)

## Out of Scope

- Any way of answering other than the terminal question prompt. Answering
  from a dashboard or another interface is expected later; R28 is what keeps
  the record usable for it.
- The status view that will display open questions. A separate effort builds
  that reader; this work defines what it reads.
- Reads that span more than one machine.
- Changing how a structured decision researches a question, produces
  alternatives or runs its adversarial review. Only how it can end changes.
- Detecting "blocked on you" said in conversation with no workflow step
  behind it. It would run on every turn and guess at wording.
- Recording which session dispatched which. Position reads use the links the
  engine already records; adding links for more ways of starting a session is
  another effort's work.
- Bringing coordinators that run outside a workflow session onto one. Such a
  coordinator gets the on-demand command of R20a and the guard of R27, but not
  the automatic prompting of R5 and R6.
- Making the remembered rules longer or more prominent in skill prose.

## Known Limitations

- **Judgment is not tested.** Whether a session picked the right addressee,
  made a real attempt to decide, judged cost to reverse well, or was right
  that an earlier answer covers a case cannot be checked automatically. The
  mechanical halves are tested and the rest is observed in dogfooding.
- **The person is a name the engine does not verify.** The read for a person
  matches a handle exactly, and an agent could claim to be the person. The
  audit trail is the control.
- **Position reads follow recorded links.** A session started in a way the
  engine does not link sits in nobody's subtree. R15 means its questions for
  the person are still found, but a coordinator asking what is pending below
  it will not see them.
- **Running sessions don't change.** A session, including a coordinator, that
  was running when this ships keeps its old behaviour until restarted, and a
  running coordinator cannot be taken over across the change.
- **One machine.** A chain whose sessions run on two machines can be read
  only one machine at a time.
- **An overruled session may have built on its own answer.** R23 says which
  answer is in effect; it does not undo work done under the other one.

## Decisions and Trade-offs

**Agents settle unless a case is reserved.** Alternatives were settling only
what facts decide clearly, and settling everything except reserved steps with
review afterward. The author chose the middle: experience applying the rule by
hand was that most questions reaching the person only needed a recommendation
confirmed. This drops two of today's reasons for sending a question up,
"outside scope" as a category of its own (a scope change is reserved; a
question merely outside the brief is the coordinator's) and "extends an answer
the person gave" (extending to a similar case is allowed; contradicting is
not).

**Unattended contested calls split by cost to reverse.** Always passing up
would queue many small questions; always assuming lets a large assumption be
built on unseen. The author chose to decide cheap ones provisionally and raise
costly ones.

**Everything pending, four at a time, by impact.** One at a time, the current
coordinator rule, takes many round trips for a long list. The author asked for
everything blocked on them. Impact is the count of work items recorded as
waiting, so the order is a fact and not an estimate.

**Needs share the record.** Keeping needs apart, as today, gives the person
two places to look for what is waiting on them.

**"Open" is the engine's to answer.** A convention each reader applies to
write-once entries would ship sooner, but every reader would have to apply the
same rule and the join is slow on a large store. The author chose a
first-class read. This means the engine's own requirements, which declare its
decision kinds and fields closed, change.

**A narrow guard, not chat detection.** A guard on the question prompt closes
the failure where an unattended session stops inside a prompt. Detecting
wording in conversation was rejected for its per-turn cost and false
positives.

**One question, no copies.** Today a coordinator re-words and re-opens a
question at each level. The author asked for no bureaucracy: a question keeps
one identity, passing up changes who it waits on, and the person's answer
anywhere closes it. This PRD requires the identity and the single read and
leaves where entries are stored to the design.

**"Final" means no ratifying step.** It does not mean an answer can never be
overturned; the person can answer again.

**The top coordinator is the preferred place to answer.** Answering a worker
is a shortcut for speed. R24 exists so the shortcut costs the chain nothing.

**Dogfooding is an acceptance criterion.** The author required it. One chain
with two coordinators plus a solo worker was chosen over a week on every
coordinator, which ties done to calendar time, and over one lane, which never
exercises three levels.

**An unlinked session addresses the person.** Refusing to raise until the
link is repaired would strand the question. Addressing the person and marking
it keeps the question visible.

**Coordinators outside a workflow session get one command.** Coordinators in
use today carry their rules as brief text and run in no workflow session, so
nothing can prompt them when a question appears. Leaving them out would change
nothing for them; requiring a workflow session would turn this feature into a
migration. The author chose a command that runs the procedure on demand in any
session.

**Solicited prompts stay as they are.** A skill asking its author to confirm
a step in a turn the author started is not a question under this record, and
R27 leaves it alone. Applying the guard to every prompt would break existing
skills for everyone using the plugin.

**Restore is byte-identical.** "Shown again" without a definition can only be
judged by eye. Identity of the rendered text makes it testable.
