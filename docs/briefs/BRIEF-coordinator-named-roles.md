---
schema: brief/v1
status: Accepted
problem: |
  The coordinate skill talks about a manager over one lane and a director over
  managers only in prose. Nothing at a run's start, in its record, in its
  reports or in a successor's brief says which role a session runs, so briefs
  re-describe the role and the session at the top drifts between names.
outcome: |
  Whoever starts a coordinator names its role, and the record, the first
  report and the successor's brief all carry that name. A reader of the skill
  finds every duty addressed to the role that owes it, and a role changes what
  a session is expected to do, never what it's allowed to do.
---

# BRIEF: Coordinator Named Roles

## Status

Accepted

## Problem Statement

A coordinator either runs one lane of work, dispatching workers and landing
what they push, or runs over other coordinators, dispatching them and reviewing
what they finish. The dispatcher-review requirements (shirabe#1449) name these
roles manager and director, with "coordinator" meaning either, and leave giving
them a place in the run to later work.

Until they have one, nobody can tell from a report or a record which role a
session runs. Each brief that starts a coordinator describes the role in its
own words, the successor picks up whatever wording it was handed, and a lineage
at the top of an effort ends up calling itself by several names. The skill
itself addresses most duties to "the coordinator", though many of them belong to
only one role, and the word "manager" already means the workspace manager
there.

## User Outcome

A person or coordinator starting a session names its role, manager or director,
and sees that name in the session's first report, in its record and in the
brief it later writes for a successor, whose first report names the same role.
The skill defines "coordinator" as a session of either role and addresses each
duty to the role that owes it. A role carries expectations only: grants, merge
authority and who settles a step stay with the workspace's authority
configuration.

## User Journeys

- A person starts a coordinator over one roadmap as a manager, and its first
  report and record say "manager".
- A person starts a coordinator over two lanes as a director; the briefs it
  writes for its two managers each name their role on one line.
- A coordinator hands over to a successor, whose brief and first report name
  the recorded role without describing it again.
- A person continues a lineage started before roles existed, whose briefs used
  several names for the top session, and its successor reports as a director
  and nothing else.

## Scope Boundary

In: naming the role at start, recording it in the existing record, carrying it
through every way a run continues, naming it in reports and in a coordinator's
brief, the Glossary entries, and readdressing one-role duties.

Out: how the role is passed and stored (the design's), grants and merge
authority, the record's container itself, enforcement by a state or gate, and
any third role.

## Downstream Artifacts

- [PRD-coordinator-named-roles](../prds/PRD-coordinator-named-roles.md)
