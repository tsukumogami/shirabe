---
schema: design/v1
status: Draft
problem: |
  When a worker hands its unit to a continuation, nothing records the
  succession, so the continuation rebinds the predecessor's koto session or
  works in the predecessor's checkout, and the predecessor's instance can't be
  torn down until the unit lands.
---

# DESIGN: Worker continuation succession

## Status

Draft

## Context and Problem Statement

A worker that runs out of room partway through a unit hands the unit to a
continuation: a new assistant session that picks the work up where the first
one stopped. shirabe has no route for that handover on the worker side, so
continuations do whatever the tools in front of them allow. Two things happen.

The continuation takes over the predecessor's koto session with
`koto session rebind`. koto's own refusals point there:
`execution_anchor_mismatch` and `execution_anchor_unresolvable` name rebind as
the fix. Rebind was built to repair a checkout that moved, not to pass a unit
between sessions. The result is one session name and id with many holders,
and no record of who came before or after (#1738).

The continuation also tends to work in the predecessor's checkout instead of a
checkout of its own. The handover carries a local path rather than a branch and
a head, and moving to a new checkout means a rebind, which breaks things:
- `test-change.sh` keeps classifying the old checkout (#1540);
- `skill-session.sh open` refuses `branch_mismatch` (#1648, #1571);
- `session/branch` keeps the old worktree's value (#1486);
- a verified suite result doesn't carry across.

Working in place avoids all of that, but the predecessor's instance then holds
live work after its session has stopped, and it can't be torn down until the
unit lands (#1748).

The coordinator side has the same hole: coordinate has no continuation route
for a worker handing over at its context limit (#1527).

koto already has a succession model, and shirabe's coordinator takeover uses
it: `koto init <new> --continues <old> --supersede` creates a new session with
a predecessor link and fences the old one, so that writes to the old session
are refused with a pointer to the new one. Nothing in koto restricts it to
coordinators. As it stands, though, it doesn't fit a worker:
- A request leg bound to the predecessor can't move to the successor.
- The successor starts at the template's initial state.
- A fenced predecessor still counts as running.
- The predecessor's children aren't re-parented.

The question this design answers is what passes from a worker to its
continuation, and how the continuation takes over the unit's state, so that
three things hold:
1. The predecessor holds nothing once it stops, and can be torn down at once.
2. Each session's history stays its own, and the chain from one to the next
   can be followed.
3. What the unit needs to resume survives the move. That means a verified
   suite result, review state and the handover itself.

It covers work-on, execute, scope and the skill-session openers, and how
coordinate's dispatch route fits. It says which parts belong in shirabe,
which in koto, and which in both. For koto it specifies only the contract
shirabe relies on, and leaves koto's internals to koto's own design.

### Out of scope

- Migrating sessions already rebound under today's practice.
- Removing `koto session rebind`. It stays as the repair verb for a checkout
  that moved on the same host.
- Compacting a worker's context in place. It's weighed as an alternative, not
  taken as the route.

## Decision Drivers

- **The predecessor holds nothing.** Once a worker stops after a handover, no
  live work, checkout or koto anchor in its instance is needed by anyone, so
  teardown can reap it before the unit merges.
- **Own history, followable chain.** Each assistant session writes to its own
  koto session. A reader can walk from any session in the chain to the newest
  one and back.
- **Resume state survives.** Anything the unit needs to resume is keyed to
  something that survives a new checkout on a new host: the branch, the pushed
  head and the session chain. A verified suite result may be reused only when
  it is provably about the same tree.
- **Nothing host-local.** The handover works when the continuation runs on
  another host. Today several pieces of state are host-local, and the design
  has to say which.
- **Leg-bound units keep working.** A unit dispatched by a coordinator is
  bound to a request leg. The handover must not strand that leg, open a second
  one or lose the unit's result.
- **No repair verb as a route.** `koto session rebind` stays what it is, a
  repair for a checkout that moved, and stops being the route a continuation
  reaches for.
- **One model.** Coordinator takeover and worker continuation should use the
  same succession model, unless a difference is argued.
- **Contained koto cost.** koto changes are acceptable where shirabe can't get
  the behaviour otherwise, and are specified as a contract.

## Considered Options

Pending: written once the remaining decisions are settled.

## Decision Outcome

Pending: written once the remaining decisions are settled.

## Solution Architecture

Pending: written once the remaining decisions are settled.

## Implementation Approach

Pending: written once the remaining decisions are settled.

## Security Considerations

Pending: written once the remaining decisions are settled.

## Consequences

Pending: written once the remaining decisions are settled.
