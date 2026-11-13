---
schema: brief/v1
status: Accepted
problem: |
  A coordinator's record holds manager or director, but nothing defines the
  position any session shirabe opens holds, so a fleet view of positions,
  kinds, parents and holders has nothing to build on, and a planned stable
  address would give one position a third name.
outcome: |
  One written definition of seat, holder and role covers every session shirabe
  opens. The shipped coordinator role is part of it unchanged, a reader can
  find any session's seat from what koto already holds, and a coordinator's
  stable address is its seat's name.
---

# BRIEF: Coordinator Seat and Role

## Status

Accepted

## Problem Statement

The named-roles work gave a coordinator a role, manager or director, set at
start and kept in its record
([BRIEF-coordinator-named-roles.md](BRIEF-coordinator-named-roles.md)). It
deliberately named only those two roles and only for coordinators, and it
gave a worker no role at all.

Two pieces of later work need more than that. A view of the whole fleet
wants each session shirabe opens to say which position it fills, what kind of
position that is, which position dispatched it and who holds it now, and it
can't be built until those words mean one thing. And a stable address for a
coordinator, one name that reaches whoever currently runs a lane, needs to
know what it names. Left alone, each piece would define its own position and
its own role list beside the shipped one, and the same session would be
described two or three ways.

## User Outcome

Someone reading koto can take any session shirabe opened and learn its seat
(the position it fills), the seat's role (director, manager or worker), the
seat that dispatched it, the session holding the seat now, and the unit of
work it's on. A successor is a new holder of the same seat, so a lane that
changes hands keeps one name. The manager and director roles a coordinator
already carries keep working exactly as they do, and a role still says only
what a session owes, never what it's allowed to do.

## User Journeys

- A person looking at the fleet sees a lane's coordinator, its role and the
  workers under it, each with the unit it's on.
- A coordinator hands over to a successor, and the seat keeps its name while
  its holder changes.
- A lane reports to its coordinator's seat name and reaches whoever holds that
  seat now.
- A person starts a shirabe skill directly, and the session shows as a seat
  with no parent.

## Scope Boundary

In: the definitions of seat, holder, successor and role; which sessions hold
a seat; which roles exist; how a seat's role relates to the role in a
coordinator's record; and what a seat's name is, including its use as the
stable address.

Out: how a seat is shown in a fleet view, any change to how the coordinator
role is passed, stored or carried, grants and merge authority, delivering
messages to a stable address, and any change to koto or niwa.

## Downstream Artifacts

- [DESIGN-coordinator-seat-and-role](../designs/DESIGN-coordinator-seat-and-role.md)
