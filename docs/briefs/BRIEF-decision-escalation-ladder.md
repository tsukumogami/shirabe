---
schema: brief/v1
status: Draft
problem: |
  When a session can't settle a question, what happens next depends on
  instructions it has to remember, and long-running sessions forget them.
  Questions reach the person unexamined, or get lost while the person is
  away, and nothing shows what is waiting on them across their sessions.
outcome: |
  A person opens any session in a reporting chain, sees what is waiting on
  them with a recommendation and justified alternatives, and answers there.
  Questions an agent can settle never reach them, and an answer given once
  carries through the chain.
motivating_context: |
  The author runs multi-session efforts and kept typing the same paragraph
  to coordinators that reported sessions blocked on them: have the owning
  session decide first, answer what you can, and bring me only the rest in
  a fixed shape. It worked each time and lapsed within hours.
---

# BRIEF: Decision Escalation Ladder

## Status

Draft

## Problem Statement

A person who runs work across several agent sessions gets told, often, that a
session is blocked on them. Usually the session that hit the question did no
work on it first. A worker's brief asks it to list one-line questions in its
report, so the session that knows the problem best contributes the least, and
whoever is above it has to rebuild the options from a sentence.

Much of what gets reported as blocked on the person isn't theirs. A session
that is outside what it was told it may do tends to say "blocked on the
person" when the call belongs to the coordinator above it. The person reads a
list where the few items that need them are mixed with many that don't.

The rules that would prevent both exist as prose: run a structured decision
before asking, settle what you're entitled to settle, and ask the person only
in a turn they started. Coordinators carry those rules as text copied from
brief to brief, and they stop applying them partway through a long session.
Typing the instruction again fixes it for a few hours. The author's experience
is that the instruction is worth following: while it holds, a good share of
the items get settled before reaching them, and most of what does reach them
only needs the recommendation confirmed.

A question that does reach the person has no durable home. It sits in a
question prompt held open in one session, or in a file a coordinator keeps by
hand. If that session is restarted, or loses its context, the options are
gone and nobody can show the person the same question again. A session that
opens a question prompt when nobody is there stops, and has stopped other
sessions with it.

Two things follow that the person feels directly. They can't ask, at any
moment, what is waiting on them across a chain of sessions or under one part
of it. And an answer they give to one session stays there, so the next
session with a similar question asks again.

## User Outcome

The person opens a session, at whatever level of the reporting chain is
convenient, and asks what is waiting on them. They get each question with its
context, the problem, the question itself, a recommendation and the
alternatives with a reason for each. They answer in the terminal, in the
question prompt they already use, and nothing more is asked of them: no other
level has to approve, forward or re-ask.

What reaches them is what needs them. A session that hits a question tries to
decide it first, and a question that belongs to a coordinator goes to that
coordinator. Resolving a question with the top coordinator is the normal path,
because what the person says there flows down to everything beneath it.
Answering a worker directly is the shortcut for when that's faster, and the
answer still reaches the coordinators above so a second worker with a similar
question settles it from what the person already said.

Being away costs nothing. A question raised while the person is absent waits,
the session keeps working on whatever doesn't depend on it, and the question
is shown again exactly as written when the person next opens a session, even
after the session has lost and rebuilt its context several times. This holds
for a worker running alone as much as for one under a manager and a director.

Everything decided is on the record with who decided it, so the person, or a
tool reading on their behalf, can list what is open and what was settled for a
whole chain or for any part of it.

## User Journeys

### A worker running alone raises a question while the person is away

A person starts a worker on a task and leaves. The worker hits a choice it
can't settle from what it has. It tries to decide, can't, records the question
with its recommendation and alternatives addressed to the person, and carries
on with the parts of the task that don't depend on the answer. The person
opens the worker the next day and asks what's pending. The worker shows the
question as it was written, the person picks an option, and the worker
continues. No coordinator existed and none was needed.

### A worker's question is settled before it reaches the person

A worker under a manager hits a question about which of two approaches fits
the feature. It attempts a decision and finds the evidence it has is enough,
so it decides, records the decision as its own, and goes on. A second worker
hits a question that is outside what it was told it may do. It addresses the
question to its manager, who settles it from the scope the person gave. The
person's list of open questions never shows either one, and the record shows
both with who decided.

### The person resolves a question with the top coordinator

A worker under a manager and a director raises a question neither coordinator
is entitled to settle. It travels up as one question, not three. The person
opens the director, asks what's pending underneath, and sees it once, with the
recommendation the worker wrote. They answer there. The worker finds the
answer and continues, and the director now holds that answer for everything
else in its lane.

### The person takes the shortcut and answers in the worker

The same question is pending at the director, but the person happens to be in
the worker's session. They ask it for its questions and it shows that one too,
because it is still the worker's question. They answer it there. Nobody above
has to ratify it. When the manager and director next look, the question is
closed with the person as the decider, and the answer is available to them as
something the person said.

### A second worker benefits from an answer the person already gave

A week later another worker in the same lane reaches a similar choice. Before
raising it, the worker looks for an answer the person already gave in this
chain, finds the earlier one, judges that it covers the case, and settles its
own question from it, citing the earlier answer. The person is not asked
again.

## Scope Boundary

### In scope

- Sorting a question by who it is addressed to (the session itself, the
  coordinator above it, or a person) before it is called blocked on the person
- Workers and coordinators trying to settle a question before they stop or
  pass it up, without that depending on remembered instructions
- A structured decision being able to end without a choice and hand the
  question back with its recommendation and alternatives
- A durable record of each question, from when it is raised to the answer and
  who gave it
- Reading what is open and what was decided, by position in a reporting chain
  and by who is being asked
- Presenting a question to the person only in a turn they started, from the
  record, and writing the answer back to the record; otherwise leaving it to
  wait while work continues
- Showing a waiting question again exactly, in any session the person opens
- The person's earlier answers serving as precedent that sessions in the chain
  consult before asking
- The person asking any session what is pending at and below it, and
  resolving it there
- The session shapes this has to hold for: a worker with no coordinator, a
  worker under one coordinator, and a worker under two
- Whatever the underlying workflow tooling has to gain for the above to hold

### Out of scope

- Any way of answering other than the terminal question prompt. Answering from
  a dashboard or another interface is expected later; this work only has to
  avoid a record that would need remodelling for it.
- The status view that would display open questions. A separate effort builds
  that reader. This work writes what it will read.
- Reading a chain whose sessions run on more than one machine. No single read
  spans machines today, and that is a larger problem than this feature.
- Changing how a structured decision researches a question, generates
  alternatives or runs its adversarial review. Only how it ends changes.
- Making the remembered rules longer or more prominent in skill prose.
  Instructions that sessions forget are the cause, so more of them is not a
  fix.
- Recording which session dispatched which. Chain and subtree reads depend on
  those links, and another effort is adding them.

## Open Questions

- How far may an agent settle a question from its sense of what the work is
  for, as opposed to what the person explicitly told it? Coordinators today
  may not extend a decision the person supplied; the instruction that
  motivated this brief lets them answer from intent.
- Should an unattended worker pass a contested call up, or record an
  assumption and continue as it does today?
- Should the person be shown pending questions one at a time or together?
- Should "open" be something the workflow engine can answer directly, or a
  rule each reader applies to the record?
- Should questions that aren't decisions, such as a credential or a step only
  the person can take, share the record or bypass the decide-first step?
- Is catching a question asked in conversation, with no workflow step behind
  it, part of this feature?

None of these blocks the brief. Each is a requirements choice for the
downstream PRD.

## References

- `skills/coordinate/SKILL.md`: the coordinator's existing verdict, escalation
  grounds and question-prompt rule, which this feature generalizes
- `skills/decision/SKILL.md`: the structured decision that would gain an
  undecided ending
- `references/decision-protocol.md`: the lightweight decide-and-record
  protocol most blocking questions fall under
- `references/decision-presentation.md`: the convention for presenting a
  decision to a person
- `docs/briefs/BRIEF-coordinate-blocked-kinds.md`: the adjacent framing of
  what "blocked on you" means for a coordinator under another coordinator
