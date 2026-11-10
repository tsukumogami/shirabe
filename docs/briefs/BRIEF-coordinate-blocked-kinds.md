---
schema: brief/v1
status: Draft
problem: |
  The coordinate skill's progress table has one blocked kind, `Blocked on
  you`. For a coordinator another coordinator dispatched, that kind means
  "blocked on my dispatcher", so a person who reads its table sees rows that
  wait on the chain above it listed as theirs to act on.
outcome: |
  A person reading a coordinator's table can tell what waits on them from what
  waits on the chain above the coordinator, and each chain-blocked row names
  who or what it waits on.
---

# BRIEF: Coordinate Blocked Kinds

## Status

Draft

This brief restates issue #1670, which the design below was written against.

## Problem Statement

The coordinate skill's progress table has one blocked kind, `Blocked on you`.
The skill's Glossary defines "the human" as whoever dispatched the
coordinator, and when that's another coordinator, everything addressed to the
human goes to that coordinator instead. So for a bound coordinator, `Blocked
on you` means "blocked on my dispatcher", and the row text never says that.

That breaks as soon as a person talks to a bound coordinator directly. The
person asks for status, the coordinator prints its table, and every row under
`Blocked on you` reads as something the person has to act on. In practice
those rows were waiting on the coordinator above, such as a release it was
cutting or a fix another lane was landing, not on the person. The person
can't tell what actually needs them from what is already moving somewhere up
the chain.

## User Outcome

The person needs both lists, kept apart. Anything blocked on the chain is
something they can choose to step in and resolve, but only if they can see
that it's the chain's and not theirs.

The kind of a row comes from who it waits on, not from who the report is
addressed to, so the same table reads correctly when a person reads it and
when the dispatching coordinator does.

## User Journeys

### A person asks a bound coordinator for status

A person talks to a coordinator that another coordinator dispatched and asks
it for status. The table it prints lists only what waits on that person under
the person-blocked kind, and lists what waits on the chain above under a
separate kind that names who it waits on.

### The dispatching coordinator reads the same table

The coordinator that dispatched it reads the same table and finds it just as
correct for its own reading, since a row's kind follows who the row waits on.

## Scope Boundary

**In scope:**

- A row blocked on the person reading the table, and only those, under a kind
  that says so.
- A row blocked on the chain above the coordinator under a separate kind that
  names who it waits on: the dispatching coordinator, another lane, a release,
  a fix in flight.
- A bound coordinator puts what its dispatcher owes under the chain kind,
  unless the row is an escalated decision entry that has to reach a person.
- `skills/coordinate/scripts/progress-view.sh`: the row kinds, the `--blocked`
  flag and its check against the facts.
- `skills/coordinate/SKILL.md`, Reporting: the progress table's kinds and the
  `Blocked on you` wording.

**Out of scope:**

- What a root coordinator's table shows for what its human dispatcher owes. A
  root coordinator, whose dispatcher is a person, keeps the person-blocked
  kind for it, unchanged.

## Downstream Artifacts

- `docs/designs/DESIGN-coordinate-blocked-kinds.md`, the design that picks
  this framing up.

## References

- Issue #1670, which reports the problem and lists the table's requirements
  and acceptance criteria.
