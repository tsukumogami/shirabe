---
schema: brief/v1
status: Accepted
problem: |
  On a milestone roadmap, one word, Done, has to say both "the work landed"
  and "someone who didn't build it checked it". Until the check lands, a
  finished milestone reads In progress, so readers can't see work that has
  shipped and coordinators hold dependents and successors behind the check.
outcome: |
  A roadmap reader sees, per milestone, when its work landed and,
  separately, when it was verified. Dependent work starts once the work
  lands, Verified keeps its strict meaning, and the status set stays fixed
  and read through one shared definition.
---

# BRIEF: Completed and Verified milestone states

## Status

Accepted

## Problem Statement

A milestone roadmap (`roadmap/v2` or `roadmap/v3`) closes a milestone on a
verdict, not on a merge. When the milestone's last pull request merges, the
coordinator records that a verdict is owed, and the milestone keeps reading In
progress until a checker who didn't deliver the work judges it against each
Evidence clause and a separate roadmap pull request carrying that verdict
merges. That rule exists for a good reason: milestones marked Done on the day
their work merged turned out, often enough to matter, not to meet their
Evidence.

The cost is that one status word has to carry two different facts. "The work
landed" and "the work was checked" happen at different times, sometimes days
apart when a clause needs a walkthrough in a sandbox, and the roadmap can show
only the second. Someone reading the roadmap sees a milestone whose pull
requests all merged a week ago still reading In progress, next to one nobody
has started. Progress looks stalled while work is in fact landing, and the only
way to tell the two apart is to go read pull requests.

The coordinator reads the same gap as a block. A milestone with a verdict owed
gets no worker, and its dependents stay blocked until the verdict's roadmap
edit is confirmed, even though the code they build on is already on the default
branch. When a lane's only open unit is a verdict owed, the rule refuses even
the brief for the coordinator's own successor. Rows also drift:
a verdict lands in the milestone block while the Progress table keeps the old
status for days.

Underneath, the tools disagree on what Done means. Whether a milestone is
finished is decided in several separate places, in shell and in Rust, and they
don't agree on whether Dropped counts or which spellings are accepted. Adding a
second state by editing each of those places would multiply the disagreement.

## User Outcome

A person reading a milestone roadmap sees, for each milestone, whether its work
has landed and, separately, whether it has been verified, and each shows up the
day it happens. Finished work that is waiting on its check is visible as
finished, so the roadmap is an honest picture of where an initiative stands
without opening a single pull request.

A coordinator driving the roadmap starts dependent milestones as soon as the
work they depend on has landed, instead of waiting for the verdict. A pending
verdict is work to do, not a gate: it never stops a successor from starting.

Verification keeps its meaning. A milestone reads Verified only on a verdict
from a checker who didn't deliver the work; a changes-needed verdict sends it
back to In progress, a clause found failing later reopens it, and a roadmap
counts as finished only when every milestone is Verified or Dropped. Someone
reading Verified can trust it as much as they could trust Done.

Maintainers of the tools get one place that says what each status means.
Every reader asks that one definition instead of comparing words, so the status
set can grow later, even toward a workflow a workspace configures for itself,
without hunting down every reader again.

## User Journeys

### A roadmap reader checks where an initiative stands

A maintainer opens a milestone roadmap to answer "how far along are we?". They
see three milestones Verified, two Completed with their merged pull requests
listed and a verdict pending, one In progress and the rest Not started. They
can say what has shipped and what has been checked without reading pull
requests, and the Completed rows tell them where verification effort is owed.

### A coordinator lands a milestone and moves on

A coordinator merges the last pull request of a milestone. The milestone reads
Completed. The coordinator dispatches the milestones that depend on it in the
same pass, and its own successor, started an hour later, picks up the pending
verdict as one more unit of work instead of refusing to start.

### A checker records a verdict

A checker who didn't build the milestone walks its Evidence clauses. When every
clause holds, the milestone reads Verified. When one doesn't, the milestone goes
back to In progress with the verdict's text as its rework, and its dependents
already running are named so their authors know their base may change. Weeks
later a clause fails in use; the Verified milestone is reopened the same way.

### An author moves an existing roadmap to the new states

A roadmap author upgrades a roadmap written under the old single Done. Each
milestone that reads Done on a recorded verified verdict becomes Verified; each
that reads Done on someone's claim, with no verdict behind it, becomes
Completed and joins the verification queue. The author can see which rows
changed and why.

## Scope Boundary

**IN:**

- Two milestone states, Completed and Verified, replacing Done on milestone
  roadmaps, with Not started, In progress and Dropped unchanged.
- What sets each state and what moves a milestone back: the last merge (or work
  seen done with nothing to merge), a verified verdict, a changes-needed
  verdict, a reopen.
- Dependents start on Completed; the Completed milestone itself takes no new
  delivery work until its verdict; Verified does not wait on dependencies.
- A roadmap is finished only when every milestone is Verified or Dropped.
- One shared definition of the statuses and what each means for readers
  (finished for dependencies, counted toward closing, how it renders), used by
  every tool that reads status.
- A way to move an existing milestone roadmap onto the new states, mapping
  verdict-backed Done to Verified and claim-backed Done to Completed.

**OUT:**

- A status workflow a workspace or roadmap configures for itself (its own
  states, transitions or approvals). The shared definition leaves room for one;
  building it is separate, later work.
- `roadmap/v1` roadmaps and roadmaps with no schema line. Their Done keeps
  meaning the work landed, set on merge, and they move to the new states only
  if and when they migrate to a milestone schema.
- Changing how verdicts are written, who may write them, or what an Evidence
  clause must say.
- Status for documents other than roadmap milestones (PLAN, PRD, DESIGN and
  issue statuses).
- Limits on how many milestones may be in flight at once.
