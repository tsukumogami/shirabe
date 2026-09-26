---
schema: brief/v1
status: Accepted
problem: |
  shirabe encodes the task rung (`/work-on`) and the story rung (`/deliver`)
  as skills, but not the session above them that hands work to other
  sessions and keeps track of it. Every such coordinator is started from a
  prose brief that describes the job from scratch, and those descriptions
  drift, accrete rules, and carry things the toolchain already does.
outcome: |
  A person starts a coordinator with a scope and the decisions they have
  already made, and nothing else. The session knows its loop, its words,
  what it never does, and where its record lives, the way a `/work-on`
  session knows its job from an issue number.
---

# BRIEF: coordinate-skill

## Status

Accepted

Written as the first hop of a `/scope` run and accepted after both
Phase 4 reviewers passed it. The downstream PRD owns the requirements,
including the record's required fields; the design owns where the record
lives and whether any step of the loop needs a workflow-engine gate.

## Problem Statement

shirabe's delegation ladder is two rungs tall. `/work-on` takes one issue
to a ready pull request, and `/deliver` takes one feature from framing to
merged work by running `/scope` and then `/execute`. A person starts either
with a single argument, and the session knows its job: its terms were
invented, its process lives in a skill, and it leaves durable artifacts
behind so a later session can pick up where it stopped.

Above those two rungs sits a third kind of session: a coordinator. It
drives an effort bigger than one feature, such as a roadmap or a standing
area like CI health or releases, by handing units of work to other
sessions and keeping track of what comes back. It decides what happens
next, writes the context a worker needs to start cold, checks what the
worker pushed, and lands finished work or puts it in front of a person.
It implements nothing itself.

That session has no skill. Every coordinator is started from a prose
description of the job, written again each time by whoever starts it.
The cost shows up in three ways:

- **The job is re-described on every start.** The person starting a
  coordinator spends the brief explaining how to coordinate instead of
  what to coordinate, and each explanation differs a little from the last.
- **The descriptions accrete.** A long-lived prose protocol grows with
  every incident, collects workarounds for tool defects that were later
  fixed, and nobody notices when a rule has stopped being true. It also
  picks up instructions the toolchain already carries out, so a session
  is told to do something that has already been done for it.
- **The shape isn't shared.** Coordinators interviewed separately describe
  the same loop in the same order (reconcile, pick, brief and dispatch,
  wait, verify, land, record), but the loop, its failure branch and its
  vocabulary (holding, deferral, rotation) exist only as each
  coordinator's own local invention. A successor or a restored session
  has nothing common to read them against.

The gap isn't that coordinators can't be run. It's that the one session
whose context is the scarcest in the workspace, because it runs longest,
is the one that has to be told its job in prose every time.

## User Outcome

A person who wants an effort coordinated starts a session with
`/shirabe:coordinate` and a scope, either a roadmap document or a named
discipline, plus whatever decisions they have already made. They don't
describe how to coordinate, and they don't re-explain it after a
restart. What comes back to them is claims they can trust, because the
session checked each one against what was pushed before repeating it,
and only the steps the workspace reserves for a person: the merges it
won't let a session make, and the decisions that are theirs. Everything
the workspace already lets a session do, the coordinator does.

A successor, a sibling coordinator or the person themselves can read the
coordinator's record on GitHub and understand what it holds, what it
deferred and why it reversed anything, using the same words the skill
uses. When a coordinator is restarted, it re-checks what it inherited
before acting on it rather than trusting its own last report.

## User Journeys

### Journey 1: Starting a roadmap coordinator

A maintainer has an Active roadmap with four features and wants them
built without driving each one by hand. They start a session with
`/shirabe:coordinate docs/roadmaps/ROADMAP-<name>.md` and a short note of
two decisions already taken. The session reads the roadmap's feature
table, finds the first unblocked feature, writes a worker brief, and
dispatches a `/deliver` run for it in its own session. It records the
dispatch in its record straight away. The maintainer's starting note
contained no description of the coordinator's job.

### Journey 2: A discipline rotation

A maintainer wants someone watching CI health for the week. They start
`/shirabe:coordinate --discipline ci-health`. There is no roadmap and no
end date for the discipline itself, so the session opens a record for
this rotation, reconciles whatever the previous rotation handed off
(including deferrals it must dispose of before its first dispatch), and
works the loop against red builds and flaky jobs. At the end of the
rotation it closes its record with a dated handoff for the next one.

### Journey 3: Restart after a crash

A coordinator's session dies mid-effort with two workers in flight and
one merge attempted but never confirmed. The maintainer who started it
notices and starts a new session with the same scope, expecting it to
pick up where the old one stopped rather than replay or skip work. Before doing anything else it reconciles: it reads the
record, treats each claim as a snapshot from a known date, re-checks the
pull requests, branches and CI on GitHub and the dispatched sessions on
the host, and reports what changed and what it still holds. It confirms
whether the merge landed before deciding anything about it.

### Journey 4: A worker reports "done"

A worker messages the coordinator that its pull request is green. The
coordinator doesn't relay that. It reads the PR's head, each CI job and
how many steps it ran, the file list, and the remote branch, then tells
the maintainer what it verified and what it didn't. Where the workspace
denies sessions the merge, it hands the maintainer a table of ready PRs in
merge order with the reason; where the workspace allows it, it merges
and then reads the files on main to confirm.

## Scope Boundary

**IN:**

- A skill that carries the coordinator's loop in order, its failure
  branch, a bound on workers in flight, and what a coordinator may
  dispatch without asking.
- What a coordinator never does, stated plainly, including that it
  implements nothing, keeps its own context for judgment, and takes
  finishing steps only as far as the workspace's declared permissions
  allow.
- The coordinator's vocabulary, defined once and used consistently.
- The record's shape and a template for it, carried as prose.
- A template for the brief a coordinator writes for each worker, and a
  checklist for verifying what a worker reports.
- Two invocations: one scoped to a roadmap, one scoped to a discipline
  rotation.

**OUT:**

- Tooling that writes, renders or gates the record. This version carries
  the record as prose; a later feature gives it tooling.
- A mechanised reconcile step. Here reconcile is a procedure the skill
  walks a session through.
- Tooling for the dispatch path, including whether the workflow engine
  can carry a worker's result back to the coordinator.
- Detecting whether a session is still running, detecting that two
  coordinators hold the same effort, and accounting for load a
  coordinator puts on other efforts.
- Any change to koto or to the workspace manager.
- Fixing how PR ownership or merge order are decided in coordinated
  execution (issues #395 and #396). The skill depends on the fixed
  behaviour those issues describe and names them as known limitations.
- Rules about who may send a coordinator a message. Sender identity
  belongs to the harness and the workspace.

