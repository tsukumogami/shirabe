---
schema: brief/v1
status: Accepted
problem: |
  A coordinator hands over to its successor through the same dispatch path
  it uses for workers, and that path was built for workers. It needs a unit
  pick can hand out, and it only recognizes a successor by a roadmap
  positional. A lane owing a verdict can't hand over, and a director's successor starts as a manager.
outcome: |
  Either role, at either scope, can dispatch its successor whenever it needs
  to hand over, and the successor starts in the role its predecessor's
  record holds. A reviewer can see that from the successor's brief and its
  first report, with nothing describing the role from scratch.
motivating_context: |
  A milestone verdict on the coordinator named-roles work found that neither
  role reached a successor in a sandbox run: the manager's successor brief was
  refused because its only unit owed a verdict, and the director's handover
  never reached a dispatch. Issues #1861 and #1862 record the two failures.
---

# BRIEF: Coordinator Successor Dispatch With Its Role

## Status

Accepted

Framed from issues #1861 and #1862, which a milestone verdict on the
coordinator named-roles work grouped together as one unit of rework.

## Problem Statement

A coordinator that reaches its handover line has to start a successor
that continues its run. Today the only scripted way to start any session
is the worker path: `pick_facts` lists the units, `pick` chooses one,
`dispatch_check` checks the topic, and `dispatch-worker.sh` renders the
brief and launches it. The successor goes through that path dressed as a
worker, with an entry point of `coordinate` and a grant of `own`. Two
things about that path don't fit a successor, and each one stops a role
from handing over.

The first is the unit. Every new dispatch must name a unit that
`pick_facts` listed in this pass, and `dispatch-worker.sh` refuses one
whose verdict is owed (exit 10, "a verdict is owed on this milestone").
That refusal is right for a worker: nobody should start new work on a
milestone waiting to be judged. A successor isn't new work on the
milestone, though. It's the session that will give the verdict. A lane
whose only open unit owes a verdict has nothing pick can hand out, so its
successor brief is refused (#1862). The same lane with no open unit at
all hits the same wall by another route.

The second is how the script knows the brief starts a successor. It
treats a `coordinate` brief as the run's own successor only when the
brief's first positional is a roadmap whose scope slug matches the run's
own. Only then does it read the role from the record's Run `role` row.
Anything else is taken for a new lane and gets `manager`. A discipline
run has no roadmap positional: it's started with `--discipline <name>
--host <owner/repo>`, so its successor brief is read as a new lane and
renders `role=manager` (#1861). The brief renderer also refuses those
flags in a `coordinate` brief's arguments, so the brief can't even be
written in the shape the discipline opener takes. The named-roles design
left this open on purpose: it says no brief starts a discipline
coordinator yet and names a discipline route as a follow-up.

Both failures land in the same place. A run's role holds while one
session runs, and is lost or blocked at the first handover. That handover
is the one event the role split depends on.

## User Outcome

A coordinator in either role, over a roadmap or a discipline, can hand
over at any point its handover rules call for. That includes a lane
whose open work is a verdict it owes and a run with no open unit. The
successor starts with the role the predecessor's record holds, and says
so on its first report's record line. Nobody writes a paragraph
explaining the role to it: the role travels as the record's value, the
successor's opener checks it against the record it continues, and a
mismatch is refused rather than adopted.

Someone reviewing a handover can confirm it from two places: the
successor's brief, whose invocation line carries the role, and the
successor's first report, whose record line names the same role as the
predecessor's record.

## User Journeys

### A manager lane that owes a verdict hands over

A roadmap lane coordinator running as a manager has merged its last
milestone's work. The milestone's verdict is owed, and that is the only
open unit left. The session reaches its handover line before it gives the
verdict. It dispatches its successor, and the dispatch isn't refused for
the verdict owed. The successor's brief names `--role manager`. The
successor starts, reconciles, reports with "Role: manager" on its record
line, and then gives the verdict the predecessor left owed.

### A discipline director hands over mid-rotation

A discipline coordinator started with `--role director` is partway
through its rotation when it reaches its handover line. It dispatches its
successor with the discipline and host its own run was opened with. The
brief's invocation line carries `--role director`, read from the record's
Run `role` row. The successor's opener continues the same rotation's
record, its role check passes, and its first report says "Role:
director".

### A record with no role row

A manager or a director whose record has no Run `role` row tries to dispatch its
successor. The dispatch is refused before anything is written or
launched, and the refusal names the command that sets the row. That's
the same refusal a roadmap successor gets today. No successor ever starts
with a default role it didn't inherit.

### A reviewer checks the handover

A reviewer of the milestone asks whether each role reached a successor.
They read the successor's brief and find the role on its invocation line,
then read the successor's first report and find the same role on its
record line. That matches the predecessor's Run `role` row. No prose in
either describes what the role means.

## Scope Boundary

**In:**

- How a coordinator dispatches its own successor, at roadmap scope and at
  discipline scope, in both roles.
- Which of the worker dispatch checks a successor dispatch is subject to:
  the unit requirement, the verdict-owed refusal, pauses and decisions
  parking a unit.
- How the dispatch recognizes a successor and where it reads the role
  from, for a run with no roadmap positional.
- How a discipline successor brief carries the run's discipline and host
  so the opener takes it.
- What a reviewer reads to confirm that a successor's brief and first
  report name the predecessor's role.

**Out:**

- A discipline successor refusing a predecessor opened from an older
  template (#1860). That's a separate unit that follows this one.
- The goal-fit wording in reports (#1863), which has already landed.
- The merge seat's teardown step and the text of the coordinator handoff
  brief, both held for a ruling. This framing doesn't change either.
- Starting a discipline coordinator as a new lane from a brief. A lane
  the coordinator dispatches is still a roadmap manager, and a route for
  dispatching discipline lanes is separate work.
- Changing a role at handover. A successor keeps its predecessor's role,
  and a role change still goes through a re-brief from above.
