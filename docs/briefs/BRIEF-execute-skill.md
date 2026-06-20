---
schema: brief/v1
status: Draft
problem: |
  An author whose plan spans several coordinated pull requests has to drive each
  unit to merged code by hand and loses their place when interrupted, because no
  single coordinator carries a whole plan to merged code at the implementation
  altitude. The strategic and tactical chains each give a coherent parent-skill
  experience; the implementation altitude does not.
outcome: |
  An author finishes a plan and hands the whole thing off in one move, getting
  the same parent-skill rhythm the other two chains provide: one conversation
  that holds state, delegates each unit, and reports progress against the whole.
  A single-unit plan runs straight through; a coordinated multi-unit plan walks
  its merge order to a single done-signal; an interrupted run resumes where it
  left off, even on a different branch.
motivating_context: |
  The strategic chain (/charter) and tactical chain (/scope) already ship as
  single-agent parent skills in a shared pattern. The implementation altitude is
  the remaining gap in that trio, and a new coordinated plan shape now gives a
  multi-unit plan a durable coordination home worth orchestrating against.
---

# BRIEF: execute-skill

## Status

Draft

This brief frames the implementation-altitude coordinator and stops before
requirements. The downstream PRD owns the requirements articulation; the
downstream design owns the technical call of whether this is a new skill or an
in-place evolution of the existing implementation flow.

## Problem Statement

shirabe gives authors two coherent parent-skill experiences. The strategic chain
walks an author from thesis to sequenced features as one held conversation; the
tactical chain walks a feature from framing to a finished plan the same way. In
both, the author talks to one coordinator that holds state across steps, delegates
each step to a child, and inspects only what it needs to before moving on.

At the implementation altitude — taking a finished plan and turning it into merged
code — that coherence is missing. An author can drive one unit of work to a merged
pull request, but nothing holds the picture *across* units for a plan whose units
land as several coordinated pull requests. There is no coordinator that knows what
has merged, what is blocked behind what, what comes next, and whether the whole
coordinated set is finished. The author carries that picture in their head, drives
each unit by hand, and — because the picture lives only in the session — loses it
entirely when the session ends or the work spans more than one sitting.

The gap is felt most on exactly the plans where coordination matters most: work
whose units must merge in a particular order, across one or more pull requests,
where "done" is a property of the whole set rather than any single unit.

## User Outcome

An author who has finished a plan hands the entire plan off in a single move and
then experiences the implementation altitude the way they already experience the
other two chains. One conversation holds the state. Each unit of work is delegated
and driven to merged code without the author dispatching it by hand. Progress is
reported against the whole plan — what has merged, what is in flight, what is next —
so the author never reconstructs that picture themselves.

A plan that is a single unit of work simply runs straight through to a merged pull
request. A plan whose units are coordinated walks its merge order on the author's
behalf and arrives at a single, unambiguous signal that the whole set is done. When
the author steps away and comes back — even on a different branch, even in a new
session — the coordinator resumes exactly where it left off, because the plan's own
durable coordination state is the source of truth rather than anything held in the
session.

## User Journeys

### Author ships a single-unit plan

A feature author has just finished a plan that describes one unit of work. They
hand the plan to the implementation coordinator in one move. The coordinator runs
that single unit through the existing implementation flow to a merged pull request
and reports the plan complete. The author never leaves the parent-skill
conversation and never dispatches the unit by hand.

### Author ships a coordinated multi-unit plan

An author has a plan whose units land as several coordinated pull requests that
must merge in a defined order. They hand the whole plan to the coordinator. It
walks the merge order, delegating each unit to the existing implementation flow,
surfacing progress against the whole as units land, and signaling the plan done
only when the coordinated set has fully merged. The author tracks one conversation,
not a wall of pull requests.

### Author resumes an interrupted execution

An author started executing a coordinated plan, then closed the session partway
through — or picked the work back up on a different branch. They re-invoke the
coordinator against the same plan. Rather than starting over or asking the author
where things stood, it reads the plan's durable coordination state, recognizes
which units have merged, and picks up at the next unit.

## Scope Boundary

### In

- A single implementation-altitude coordinator that completes the parent-skill
  trio alongside the strategic and tactical chains, in the same single-agent shape.
- Taking a finished plan and carrying it to merged code: both single-unit plans
  and coordinated multi-unit plans.
- Delegating each unit of work to the existing implementation flow, used unchanged.
- Inspecting each unit only through its status surface, and reporting progress
  against the whole plan.
- Resuming from the plan's own durable coordination state, including across
  branches and sessions, with a single done-signal for the whole coordinated set.

### Out

- Changing the internal machinery of the existing implementation flow. The
  coordinator sits above it and leaves it as-is; reworking its internals is
  separate, substrate-gated work.
- Building the shared coordination substrate the coordinator relies on for
  cross-session, cross-branch state. The coordinator consumes a durable
  coordination home when one exists; providing that substrate is a separate piece
  of amplifier work.
- The review-time redirect mechanism (changing course mid-execution in response to
  a human's redirect). That is a separate downstream feature.
- Plans whose units have no durable coordination home (ad-hoc multi-pull-request
  fan-out with no coordination record). The coordinator targets single-unit and
  coordinated plans, not unstructured fan-out.
- The technical call of whether this is a brand-new skill or an in-place evolution
  of the existing implementation flow, and the exact state and resume mechanics.
  Those are downstream design decisions.

## Open Questions

- Whether the implementation-altitude coordinator is a new skill or an in-place
  evolution of the existing implementation flow. The downstream design owns this
  call, based on how much of the current surface survives the restructure.
- Exactly which durable coordination state the coordinator reads, and how it binds
  to a coordinated plan's on-pull-request state. The downstream PRD and design own
  the precise contract.

## References

- `docs/designs/current/DESIGN-shirabe-progression-authoring.md` — the parent-skill
  progression pattern this feature extends to the implementation altitude.
- The `/charter` (strategic) and `/scope` (tactical) skills — the precedent parent
  skills whose single-agent shape and metadata-only child inspection this feature
  mirrors.
- tsukumogami/shirabe#196 — the coordinated execution-mode work that gives a
  multi-unit plan a durable coordination home worth orchestrating against.
