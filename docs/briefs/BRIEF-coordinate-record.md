---
schema: brief/v1
status: Draft
problem: |
  A coordinator can open a second record after a restart, dispatch past a predecessor's
  deferral, or land work on a head nobody verified, because `/coordinate` is prose: each
  check it asks for can be skipped or satisfied by saying it was done, and the record is
  hand-written markdown that nothing finds or renders.
outcome: |
  A coordinator started with `/coordinate` moves through its loop as a workflow whose record
  checks it can't pass by assertion. A restart adopts the record it already has, a
  predecessor's deferrals are disposed of before anything is dispatched, and a land step only
  proceeds on a head the workflow read from the pull request and its CI board itself.
motivating_context: |
  The first version of `/coordinate` shipped as prose on purpose, as the spec for this one.
  Its "What This Version Leaves for Later" section names the record's tooling as the next
  piece, and the container question it left open (an issue at roadmap scope, a pull request
  per rotation) was settled when that version was reviewed, and this work records the
  answer in the skill. Running the loop as a koto workflow is how every
  other shirabe skill that must not skip a step already works.
---

# BRIEF: The coordination record and the coordinator's workflow

## Status

Draft

This brief frames the second piece of the coordinator work: the record's tooling and the
koto workflow that carries the coordinator's loop. The dispatch tooling and a mechanised
reconcile are separate later work, each framed by its own brief when it starts.

## Problem Statement

A coordinator is the longest-running session in a workspace. It hands work to other
sessions, checks what comes back, and lands it or puts it in front of a person. The
`/coordinate` skill that tells it how to do that is a prose document, and prose can only
ask.

Four of the things it asks for are the ones that go wrong when a coordinator is in a hurry,
restarted, or new to an effort:

- **The record has to exist, once.** The record is where a coordinator writes what GitHub
  can't tell a successor: which workers it dispatched, what it deferred, what it attempted
  and never confirmed, and why it reversed a decision. Today the coordinator finds it by
  running a listing by hand and opens it by hand. A coordinator restarted just after opening
  its record, or one that searched instead of listing, opens a second record, and the two
  drift.
- **A predecessor's deferrals come first.** A rotation or a restarted coordinator inherits
  deferrals that someone must act on. The skill says to dispose of them before the first
  dispatch. Nothing stops a coordinator that doesn't.
- **Nothing lands on a head nobody verified.** The skill says to read the pull request's head,
  every CI job's runner and step count, and the remote ref before relaying "green" or
  merging. A coordinator can write a head sha into its record without having read the board
  at that sha, and nothing can tell the difference.
- **A green board can be empty.** A job that ran on no runner, or whose steps were all
  skipped, shows green. The skill describes the read that catches it; the read is only as
  good as the coordinator's decision to run it.

Each of these is a claim the coordinator makes about its own work, checked by nobody. The
first two are about the record and the last two about the land step; this brief calls them
the four checks.

The record is also written from scratch each time from a template in a reference file, so
its four sections drift in shape between writes, and a successor reading it has to parse
whatever the last writer produced.

Two of the coordinator's steps are judgment rather than checks: which unit of work to pick
next, and whether a worker's report means done, blocked, or needs a fix. Nothing records
those calls in a form anyone could compare against a mechanical answer, so there's no way
to learn whether either could ever be made automatically.

## User Outcome

Someone who starts a coordinator gets one that can't skip the four checks, whatever it
decides about the rest. They start it the way they start any other shirabe workflow, with a
scope and their decisions. From there, the coordinator's first act is to find the record
it already has, or open exactly one. It can't dispatch anything while a predecessor's
deferral is still open, and it can't reach a land step until the workflow has read the pull
request's head and a real CI board at that head and recorded both.

The person reading the record on GitHub, whether that's the human, a sibling coordinator, or
a successor, finds the same four sections in the same shape every time, and a restart
continues from the same record instead of starting a parallel one.

## User Journeys

### A person starts a roadmap coordinator

A maintainer has an Active roadmap and wants its features driven to done without typing the
job into a prompt. They run `/coordinate docs/roadmaps/ROADMAP-<name>.md` with their
decisions. The workflow checks the roadmap is Active, reads the workspace's permission
posture, and finds or opens the record issue in the roadmap's repository before any
dispatch. The maintainer can read the record on GitHub from the first minute.

### A coordinator restarts after a crash

A coordinator's session dies mid-effort. Someone starts `/coordinate` again on the same
roadmap. The workflow finds the existing record issue by its exact title, adopts it, and
reports its holdings, deferrals and unconfirmed side effects as dated claims to re-check.
No second record appears, even when the first one was opened a minute before the crash.

### A rotation successor inherits deferrals

A discipline rotation ends with two open deferrals in its handoff. The next rotation starts.
The workflow opens the new rotation's record and carries the deferrals in, and then refuses
to leave for the first dispatch until each is filed as an issue, closed, or carried forward
with a reason. The successor can't forget them, because nothing moves until they're handled.

### A worker reports green

A worker messages that its pull request is done and CI is green. The coordinator moves to
verification. The workflow reads the pull request's head from the remote, reads the CI board
at that head, and records the head as verified only when the board shows real work on every
job it expects. The land step, whether that's a merge the
workspace permits or a merge-order table for a person, can't be reached without that
recorded head, and the coordinator can't supply it by typing one in.

## Scope Boundary

**In:**

- Running the coordinator's whole loop, from start through the rotation close-out at
  discipline scope, as a koto workflow, so the four checks are enforced where the loop
  reaches them and can't be passed with a value the coordinator supplies.
- Tooling, with tests, for the record: finding or opening it, writing its four sections in
  one shape, and rewriting them whole.
- Recording the two judgment calls (the next unit, a report's meaning) alongside an
  automatic answer that doesn't act, so a later change can decide whether to trust it.
- A `/coordinate` skill file that says how to start, advance and read the workflow, with
  each step's guidance delivered when the coordinator reaches that step.

**Out:**

- The dispatch tooling: compiling a worker's brief, recording a dispatch automatically, and
  binding a worker's result back to the workflow. The dispatch state follows the prose
  procedure until that work lands.
- A mechanised reconcile beyond what the record checks need. The reconcile state follows the
  prose procedure.
- Any change to koto or to the workspace manager; deciders in auto mode; session liveness;
  detecting that an effort is held by two coordinators.
- Any permission rule of the skill's own. What a coordinator may merge, close or tear down
  stays the workspace's declared posture, read at start.
