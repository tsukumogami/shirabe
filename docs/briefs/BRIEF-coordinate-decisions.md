---
schema: brief/v1
status: Accepted
problem: |
  A worker can hand a choice straight to the human, new evidence goes back to the human
  as a bare "decide", and a coordinator can list a choice with no recommendation even when
  the evidence settled it inside its own authority. The human ends up doing the
  coordinator's judgment, and a decision doesn't survive the coordinator's restart.
outcome: |
  The person running an effort only sees a decision the coordinators under them couldn't
  settle, one at a time, in the order they can answer it in one pass: what's being decided,
  why it's theirs, then the question with the recommendation first and its reason. Evidence
  and worker questions reach a coordinator's verdict before anything reaches the person.
motivating_context: |
  In tsukumogami/niwa#330 a worker got an option approved through `/decision`. The human
  then ran a check the decision had marked untested and got a mixed result. The worker
  handed that result straight to the human as "decide", and a coordinator listed it in its
  status table as "decide whether to ship" with no recommendation, though the evidence had
  settled the question within the coordinator's authority. The human had to catch it.
  tsukumogami/shirabe#435 asks for the fix to be structural, and a comment on it adds the
  shape a decision takes when it reaches a person, asked for three times in one session.
---

# BRIEF: Decisions and escalation in the coordinate skill

## Status

Accepted

This brief frames the fifth piece of the coordinator work: how a coordinator holds a
decision, judges it, and escalates it. The record, the dispatch path and reconcile are
framed by their own briefs.

## Problem Statement

A coordinator exists so the person above it doesn't have to follow every unit of work. Its
most valuable output is judgment: settling what it can, and bringing up only what it can't,
with its own recommendation attached. The `/coordinate` skill says this in prose. It says a
decision that is the human's is asked once, with one recommendation, and that direction
comes only through the dispatcher's channel. Nothing in the workflow holds a coordinator
to it.

Four things go wrong, and niwa#330 showed all of them in one sequence:

- **A worker addresses the human directly.** A worker's brief names the coordinator as its
  only source of direction, but a worker that meets a choice can still address the person
  instead: in the report it sends up, which a coordinator then passes along as it stands,
  or in its own session, where a person watching reads it. Either way the coordinator
  never judges the question, so it never answers it or adds a recommendation.
- **New evidence skips the coordinator.** A decision that was settled can be reopened by
  what happens next: a check a person ran, a measurement, a worker's report. Today that
  evidence goes back to whoever is nearest, usually the human, as a fresh question. The
  coordinator's judgment, which is what the evidence should feed, is skipped.
- **A choice reaches the human without a recommendation.** A coordinator can put "decide
  whether to ship" in its status table with no recommendation and no reason, even when the
  evidence settled the question inside its own authority. The table is the one place the
  human reads, and nothing stops a row like that.
- **The question arrives in the wrong order.** When a decision does belong to the human,
  it helps only if they can answer it in one pass. Asked without context, the answer comes
  back as a question about what the options mean. Asked in a batch, the decisions blur.
  The operator in the session behind the comment on shirabe#435 asked three times for the
  same shape: the context, then the problem and why the coordinator can't settle it, then
  the question with the recommendation first.

A decision also doesn't survive a restart. A coordinator that crashes while a decision is
with the human comes back with no trace of it: it either drops the question or asks it
again as new. GitHub can't tell a successor the decision exists, because nothing about it
is in a pull request or an issue, and the coordinator's record says nothing about
decisions at all.

In this workspace coordinators nest: a roadmap coordinator is dispatched by a workspace
coordinator, which carries decisions up to the human. So "the human" in a coordinator's
rules is sometimes another coordinator, and a decision that is with the coordinator above
shouldn't be shown to the person as a question they must answer.

## User Outcome

The person running an effort sees fewer decisions, and each one they see is ready to
answer. A decision reaches them only after a coordinator has judged it and found it isn't
its own to settle. It arrives alone, not in a batch, as a paragraph of context, a paragraph
saying what's unresolved and why the coordinator can't settle it, and then the question,
with the recommended option first and the reason for it. They answer once.

A coordinator can no longer let a decision bypass its own judgment. When evidence arrives
after a decision, it re-judges the decision before anything reaches the person. When a
worker asks a question, the coordinator is the one who receives it. When a decision is with
the coordinator above, the status the person reads says so rather than asking them. A
coordinator that restarts neither loses a decision nor asks it twice. Replayed against the
workflow, the niwa#330 sequence ends with no question put to the human at all.

## User Journeys

### A worker asks the human to decide

A worker running `/deliver` under a roadmap coordinator hits a choice it can't make and
writes, in its report, "please decide whether to ship with the mixed result". The trigger
is the report reaching the coordinator. The outcome: the question lands with the
coordinator as an open decision, which it answers for the worker or escalates with its own
recommendation. The human hears nothing from the worker.

### Evidence arrives after a decision was settled

A decision was settled when the worker's chosen option was approved. Then the human runs a
check the decision had marked untested and tells the coordinator the result is mixed. The
trigger is that evidence. The outcome: the decision reopens and goes to the coordinator's
verdict, not to the human. The coordinator reads the evidence, finds the question is inside
its authority, and settles it with a recorded reason. This is the niwa#330 sequence ending
the way it should have.

### A decision that really is the human's

A coordinator finds that the evidence points to dropping a feature from the roadmap, which
changes the effort's scope. The trigger is the coordinator's own verdict that the decision
isn't its to make. The outcome: the human receives one message about one decision, with the
context, the problem and why it's theirs, and the question with the recommended option
first. The status table shows the same decision as blocked on them, with the recommendation.

### A roadmap coordinator under a workspace coordinator

A roadmap coordinator was dispatched by the workspace coordinator. Its verdict on a
decision is that it needs a person. The trigger is that escalation. The outcome: the
decision goes to the workspace coordinator in the same shape, and the workspace coordinator
judges it in turn, settling it or carrying it up. The roadmap coordinator's status table
shows the decision as with the workspace coordinator, not as a question for whoever reads
it.

### A coordinator restarts with a decision open

A coordinator crashes while a decision is waiting on the human. The trigger is its restart.
The outcome: the new run adopts the record and finds the decision still open, with its
recommendation and who it's waiting on, so it neither drops the decision nor asks it a
second time as new.

## Scope Boundary

**In:**

- Where a coordinator holds an open decision so it survives a restart, and the states a
  decision moves through: proposed, the coordinator's verdict, escalated with a
  recommendation and its reason, settled.
- The rule that evidence (a check a person ran, a measurement, a worker's report) reopens a
  decision to the coordinator's verdict, never straight to the human.
- A check on everything the human reads that asks for a decision: the escalation message
  and the progress table's rows. It refuses a decision with no recommendation, no reason, no
  context or no statement of the problem, and it keeps the order context, problem, question
  with the recommendation first, one decision at a time.
- Escalation to another coordinator by the same rules as escalation to a person, and a
  progress table that says a decision is with that coordinator.
- A check that a worker's question addressed to the human becomes a decision for its
  coordinator instead, wherever that question can be caught: in what the worker sends up,
  and in whatever part of the worker's own run a check can reach.
- A replay of the niwa#330 sequence against the workflow, ending with the coordinator's
  verdict recorded before anything reaches the human.

**Out:**

- The `/decision` skill. A worker that runs it still does so as today; this work covers
  what happens when its outcome, or evidence against it, comes back to a coordinator.
- Changing the worker skills themselves (`/work-on`, `/execute`, `/deliver`, `/scope`) as
  a given. Whether the worker-side check needs them, or can live where every worker report
  already arrives, is a design question.
- Controlling what a worker's session prints for a person who happens to be watching it.
  No coordinator runs that session; the work covers what a check can reach, and the design
  says which parts those are.
- niwa, and any change to koto. Engine limits this work meets are named and proposed, not
  built.
- Deciding for the coordinator. A classifier may suggest whether a decision is within the
  coordinator's authority, in shadow first, but the verdict stays the coordinator's.
- The dispatch path and reconcile, which are separate features; this work builds on the
  report and brief they carry and doesn't reopen them.
