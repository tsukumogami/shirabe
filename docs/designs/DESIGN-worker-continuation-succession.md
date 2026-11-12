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

Four decisions shape the design: the succession model, where a continuation
starts in its template, what it's handed and how resume state survives a new
checkout, and how the route fits coordinate. Each builds on the ones before.

### Decision 1: Worker continuation succession model

koto's succession model fences the predecessor against every append, links
the successor and copies the `--carry` prefixes. As shipped it falls short
for a worker in five ways. A leg binds one child session id and refuses any
other. The successor starts at the template's initial state. A fenced,
non-terminal session still counts as running and can't be cancelled. A
child's completion append to a fenced parent fails. And no read-only surface
names a chain's newest member. Two more facts shape every option: the request
store is host-local and the cloud backend doesn't replicate it, and several
work-on gates read the session's own log, which carry never copies. The
rule-findings ladder counts gate failures from it, the scrutiny gate slices
recorded decisions out of it, and `fix-kind.sh` reads task text from it.

Key assumptions:
- A leg-bound continuation runs on the host that holds the request. Decision 4
  makes that hold for coordinated units, since coordinate launches on its own
  host.
- Reaping a niwa instance leaves koto's session store (`~/.koto/sessions`)
  alone, so a reaped predecessor stays readable as chain history.
- koto fixes the cloud-backend carry failure tracked in koto#560. The leg's
  state moves through the requester, not the carry, so the leg doesn't depend
  on that fix.
- koto takes the contract in Implementation Approach. Until it does, the
  route can't ship for leg-bound units: a fenced predecessor counts as alive,
  and `koto request attach` would accept it.

#### Chosen: Successor session, with the requester replacing the leg

A continuation takes the pushed branch and its head, never a local path, into
a checkout of its own in its own instance. Its opener then runs
`koto init <succ> --continues <pred> --supersede --expect-state <state> --carry <prefixes>`.
The fence happens in the successor, after launch, so everything on the
predecessor's side has to happen, and refuse if it's going to, before launch.
Each assistant session writes its own koto session, the chain can be walked
both ways, and coordinator takeover and worker continuation use one verb.
`koto session rebind` goes back to repairing a checkout that moved on one
host.

For a leg-bound unit, the requester replaces the leg with verbs koto already
has. It opens a new one-leg request before launch. The successor attaches to
it right after the fence, with its own `koto request attach`, since
`--supersede` bars `--koto-leg` on init. Only then does the requester abandon
the predecessor's request, with a rationale naming the successor
(`koto request abandon-request` works on a self-attached leg). That order
means the unit always has a leg. shirabe generalizes the idempotent re-leg
sequence `dispatch-worker.sh` runs for imported runs (`--releg-imported`)
into this path.

The successor carries what the unit needs to resume, keyed to the branch, the
pushed head and the session chain (Decision 3). That includes the log-derived
gate figures: ladder counts, recorded decisions and task text are snapshotted
into carried keys at handover, so the successor's gates continue from the
chain's figures instead of silently resetting. Reading the log across the
chain stays deferred. The templates that rebuild their own session name
(scope, execute, execute-coordinated, deliver) and the readers that find a
unit's session by name resolve the newest chain member instead.

This is the only option that meets "own history, followable chain", "no
repair verb as a route" and "one model" together, and supersede already
fences and links across workspace prefixes under the cloud backend. Between
the two successor variants, requester-side replacement wins on contained koto
cost: koto doesn't build a non-atomic transfer across the session log and the
request log, two stores it locks apart, and its one-child-per-leg rule stays
true for every reader. The price is that a handover reads as an abandonment on
the old request, explained by the rationale, and that coordinate and deliver
both implement replacement.

#### Alternatives Considered

**Rebind into a fresh checkout, with the breakages fixed.** Keep one koto
session, rebind it into the continuation's own checkout, and fix
`test-change.sh`, `session/branch` and the verification result in shirabe.
This was the strongest alternative: it needs no koto change, and the leg
binding, children's completions, liveness and one continuous log all keep
working. It was rejected because it makes the repair verb the route, and a
holder list inside one session is still one shared history. On another host
rebind refuses until the session is imported, and under the local backend it
refuses only ticks from the old anchor, so a predecessor that hasn't fully
stopped can still write the shared log. Its shirabe fixes are kept, since
every option needs them.

**Successor session, with koto moving the leg.** `koto init --supersede`
transfers the leg as a fence-then-transfer step. The leg's history stays in
one request, a handover never reads as an abandonment, and no requester
learns replacement. It was rejected for now because shirabe gets the move with
existing verbs, while the transfer is new koto behaviour across two
separately locked stores, with no cross-host gain while the request store is
host-local. It comes back if requester-side replacement proves too costly;
deliver's re-leg is the first test.

**Keep working in the predecessor's checkout.** No move and no code, and
every piece of resume state stays valid because the tree, path and session
don't change. It was rejected because the predecessor's instance then holds
live work until the unit lands (#1748), a unit with no leg can't move hosts,
and nothing fences a predecessor that hasn't fully stopped. It stays as a
guarded stopgap for execute's stopped batch children until koto can supersede
a `--parent` child: the predecessor's job is finished, its session has had no
event for 600 seconds, and HEAD equals the pushed head on a clean tree.

**Compact in place.** The worker compacts its context and keeps going: no
handover, no predecessor, no koto cost. It was rejected as the route because
the harness decides when compaction happens and what survives, and because it
does nothing for a worker that stopped or crashed, the case this design must
route. A running worker may still compact; nothing in the contract depends on
it.

### Decision 2: How a continuation reaches its predecessor's template state

koto starts a successor at the template's initial state. That suits
coordinate, whose loop works its position out from carried `record/` keys on
every lap, and scope, whose `resume_route` reads the artifact tree. work-on
and execute are linear pipelines where the position is progress: whether the
PR is open, which values earlier states captured (`BRANCH`, `PR_BODY_RULES`,
the probe rules), and which batch execute materialized. Workers don't choose
where they stop; #1738 records handovers at review states, at pre-PR
evidence, at finalization and with a tested but uncommitted tree. In the code,
`init_child_core` already takes an `override_initial_state`, supersede
already reads the predecessor's state for `--expect-state`, captures exist
only as log events (a tick that reads a missing one stops with
`capture_unset`), and `skip_if` runs after the default action and can't read
a context key.

Key assumptions:
- Workers mostly run out of room inside implementation, review rounds and the
  CI fix loop, not at gate-only states.
- The handover pushes work in progress first. No option recovers code that
  only the predecessor's checkout holds.

#### Chosen: koto starts the successor at the predecessor's state

The opener for work-on, execute and scope adds koto's start-at-state request
to the supersede init. The successor's first `koto next` is an ordinary
arrival at the predecessor's state: the default action runs, gates evaluate
against the successor's checkout, and the full directive is delivered, which
is what a fresh agent needs. This replaces the resume path from the initial
state that Decision 1 would otherwise have needed in work-on.

koto starts the successor with the predecessor's declared variables, rebinds
included, and delivered captures, recorded in the successor's own log. That
seeds bindings; it isn't a copy of history, since no evidence or decisions
carry and the epoch starts empty. A materialized batch carries over, so an
execute successor at `spawn_and_await` doesn't materialize a second one. The
start position doesn't bring the gate figures: where this decision's analysis
said the escalation ladder and the decision grading "restart", it describes
the start position alone. The figures themselves arrive through the snapshot
Decision 3 carries.

work-on, execute and scope each declare a COMPAT number, held honest by
`check-template-compat.sh` in CI. The handover refuses `template-incompatible`
before launch when the numbers differ or the state is missing. Re-entry needs
no new work, because koto already re-runs a state's action on every
gate-blocked retry, and `pr_creation` already checks for an existing PR.

Coordinate keeps the initial-state start, since it works out its position on
every lap, and so does deliver, whose successor re-runs `open_request` to
capture a new request id. Only a koto start covers every state a worker might
stop in with one rule, and it's the cheapest handover, one init and one tick.
A costly route gets bypassed, which is how rebind became the route.

#### Alternatives Considered

**Each template gains a resume route on carried keys.** No koto change, and
template authors stay in control; scope and coordinate already work this way.
It was rejected because in work-on and execute the route re-runs every passed
state's action: fresh canary and probe draws, the full suite on a new host,
scrutiny checks that can hold the chain. `skip_if` can't see context keys,
and a one-hop router would need edges to some 45 states, landing where a koto
start does but without the captures.

**The successor replays evidence up to the predecessor's state.** No koto or
template change, captures arrive afresh, and `fix-round.sh` is a precedent.
It was rejected because the successor would submit claims it never made, such
as "implementation complete", so its log would record another session's work
as its own. A replay also re-runs every action and check, and at
`spawn_and_await` materializes a second batch.

**Handovers only at handover-safe states.** A handful of testable positions
instead of every state. It was rejected as a rule because a stopped worker
can't drive on to a safe state, and the unsafe ones (implementation,
mid-review) are where workers most often run out. It stays as guidance: push
and hand over at the next boundary when that's cheap.

### Decision 3: Handover payload and resume-state keying

Most resume state is already a koto key whose value names its commits:
`impl_base`, `review_round.json` with its `reviewed_head`, the review scopes
and findings ledgers keyed by head, and `test-change.sh`'s acceptances at
blob digests. Some state is host-local or name-keyed today. The verification
result sits under `${XDG_STATE_HOME}/shirabe/verification/<session>/<head>/`,
so a successor reruns the suite even on the same host. The test-change ledger
records an absolute work tree and follows a move only when that tree is gone
(#1540). Person acceptances are tagged with a per-host key, coordinator
acceptances are checked against the local store, and a new checkout's local
branch name isn't the pushed branch (#1648).

Key assumptions:
- Continuation checkouts are full clones; a shallow clone fails the ancestry
  checks closed.
- Within one OS and architecture, a pass on the same tree is as good as a
  local rerun. CI still checks the pull request.

#### Chosen: Carried keys, each checked again against the successor's checkout

The handover script writes `handover/note.json` into the predecessor's
session before launch (`koto context add` isn't anchor-checked, so any lane
can), and the successor carries it with `--carry handover/`. The note names
the unit, branch, pushed head, predecessor session, template and COMPAT
number, state, clean-tree flag, carry list and a short reason. The session
copy is the only one. The requester doesn't copy it into its record: under
Decision 4 coordinate reads it from the predecessor's session and keeps its
pointer in its own holding row and side map. The same write snapshots the
gate figures into `handover/gate-figures.json`, and each reader adds the
snapshot to what its own log holds. The launch brief adds only a `continues`
block (predecessor session, branch, pushed head and, for a coordinated unit,
the generation) to the ordinary brief. Nothing goes into a PR or issue
comment.

The verification result's koto key becomes the authority and records OS and
architecture. `run-verification.sh --start` reuses it when its head equals
HEAD, its merge base matches, the tracked tree is clean, its status is
settled and the platform matches. Reuse is safe because the script refuses a
dirty tree, reads the verification map at the merge base and picks commands
from `merge-base..HEAD`, so those values fix the result.

The successor continues the test-change ledger. The chain becomes the
author, so no chain member can accept its own test edits. Every call compares
koto's `execution_dir` with the ledger's tree and appends a `relocate` line
with the HEAD when they differ, whether or not the old tree still exists.
Declines carry, so a handover can't reset the decline limit. A person tag or
coordinator acceptance that can't be verified from this host fails closed.
Review state and `impl_base` are carried, and their existing checks refuse
when HEAD has moved. `session/branch` is re-derived from the checkout and
compared with the note's branch; a mismatch at the same HEAD names a rename,
not a cleanup.

One rule covers everything: each piece of state is a carried key that names
its commits, trusted only after a check against the successor's checkout. The
carry happens once, at the fence, and afterwards every gate reads only its
own session.

#### Alternatives Considered

**Re-derive at the successor.** Carry only `impl_base`, then rerun the suite,
start a new ledger and redo the review rounds. Nothing stale is ever trusted,
and the carry list is tiny. It was rejected because every handover pays for a
full suite, a new ledger loses accepted edits, a reset decline count lets a
declined test edit through, and #1540's same-host case stays open.

**Chain-scoped reads, no copies.** Each session keeps what it wrote, and
readers fold across the chain, so nothing is duplicated. It was rejected
because every gate becomes chain-aware and reads several sessions each tick,
cross-host correctness then rests on the cloud backend for every read, and
the verification result would still need to move into koto.

**State on the branch, in git notes or a PR comment.** It travels with the
code under any backend, and a person can see the handover. It was rejected
because it puts GitHub writes on every handover and verification and internal
run state in public PRs, notes aren't fetched by default, and the ledger's
integrity would rest on push rights instead of koto's lock.

### Decision 4: Coordinate route for a worker that hands over

Coordinate can't route a handover today (#1527). `classify_report` knows done,
blocked and needs_fix. `report-source.sh` refuses a leg-bound worker's message
while its leg is open. `--strand` takes message-path rows only, and only pick
writes `dispatch_topic`. The Holdings row names its worker by dispatch topic,
which is also the niwa name, request label and teardown key, and teardown
needs a merged PR (#1674). Two more facts decide who acts. Only the record's
driver session may write the record: `lib_driver_check` refuses any other
writer. And supersede rings only the predecessor's own wake file, so nothing
on coordinate's side wakes when a successor fences.

Key assumptions:
- Session messages reach coordinate from another host.
- A worker on another host needs the cloud backend; under the local backend
  its session can't be read from coordinate's host, so the move refuses before
  launch and the unit takes the stranded-holding route.
- A read-only chain lookup shows `newest` without a write
  (`dc_newest_member`'s log walk serves until koto's surface lands).

#### Chosen: Coordinate launches the continuation of a coordinated unit

The design originally framed the route this way: one script that any lane
can run writes a handover note and a unit-to-live-worker pointer into the
requester's record and launches the continuation, and the coordinator loop
gains one "handed over" report kind that swaps the request. The chosen route
keeps the one script, the note, one new coordinator event and the request
swap, and departs from that framing on purpose. For a coordinated unit,
coordinate launches the continuation and writes the pointer into its own
holding row. The script launches on its own only when the unit has no outside
requester: a session a person started, or deliver's own legs.

Two things in the code force that. Only the record's driver session may
write the record, and `lib_driver_check` refuses any other writer, so a
script in a worker's lane can't put a pointer in coordinate's record. And
nothing on coordinate's side wakes when a successor fences, because supersede
rings only the predecessor's own wake file, so coordinate has to be told by
message whoever launches. Once coordinate is the one acting, launching costs
it one dispatch and buys three things. The new leg goes in the brief, so the
successor attaches before any work, and that ordering replaces a separate
wait-for-attach stop. The launch keeps `dispatch-worker.sh`'s checks: the
topic against live sessions, the grant ceiling, the brief rendered from the
record, the `--parent-from` link and the lane cap. And the row has one
writer.

The route still meets what the original framing was for. The per-handover
cost stays low: the worker runs one script, sends one message and stops. The
record has no gap: from the moment coordinate rewrites the row, the handover
reads pending until the successor is the chain's newest member and bound to
the new leg. And the unit keeps one identity: the same holding row carries it
through every generation, with a side map for the earlier ones.

`wait` gains a `handover` event, admitted from the holding's current worker
even while its leg is open, from coordinate, or from a person acting for a
crashed worker. It isn't a `classify_report` value, so done and needs_fix
can't be misused for it. Solution Architecture gives its move's steps.

#### Alternatives Considered

**The predecessor launches and coordinate adopts.** This is the route as
first framed. The unit moves on without waiting for coordinate to wake, one
script serves every caller the same way, and it works off-host under the
local backend, because the worker launches where it already is. It was
rejected because coordinate still has to write the record afterwards, since
only the driver may, and has to be told by message, since a fence doesn't
wake it. Meanwhile the successor starts outside the launch checks and the
parent link, and runs with no leg until coordinate notices, so it would need a
real wait-for-attach stop.

**Generalized strand-and-redispatch.** Treat a handover like a lost worker:
strand the holding and dispatch again. It adds no event, and one path serves
crashed and handed-over workers alike. It was rejected because every handover
would wait out a quiet timeout, the second row would need a lane-cap
carve-out, and it would loosen the refusal to strand a leg-bound row, which
keeps a live leg from being orphaned.

**Split by return path.** Coordinate launches for leg-bound units and the
worker for message-path units, each where it's best placed. It was rejected
because it puts two handover paths in coordinate, and its only gain is the
local-backend off-host case, which the chosen route refuses before launch and
sends down the strand route.

## Decision Outcome

A worker that runs out of room runs one handover script, which writes
`handover/note.json` and a gate-figure snapshot into its koto session, and
stops. The continuation runs in a fresh checkout of the pushed branch, in its
own instance, and its opener runs a supersede init that fences the
predecessor, carries the resume state and, for work-on, execute and scope,
starts at the predecessor's state. Every carried key names commits and is
checked against the successor's checkout before it's trusted.

For a coordinated unit, the worker sends coordinate one `handover` message,
and coordinate launches the continuation: it opens the new request first,
rewrites the same holding row, keeps earlier generations in a side map, and
abandons the old request once the successor is the chain's newest member and
attached. The script launches by itself only when there's no outside
requester: a session a person started, or deliver's own legs.

That split is a deliberate departure from the route the design started from,
where one script in any lane wrote the note and a pointer into the
requester's record and launched the continuation. It was chosen because only
the record's driver session may write the record, and because a successor's
fence wakes nothing on coordinate's side. It keeps that route's aims: the
worker's cost is still one script and a stop, the record never has a gap
because the handover reads pending until it settles, and the unit keeps one
identity in one holding row.

The predecessor ends up holding nothing: no checkout in use, no anchor on it,
no leg it can answer. Teardown retires its instance with a `superseded`
disposition before the unit merges.

What this closes:
- #1738 and #1748: continuations stop rebinding, each session owns its
  history, and the predecessor's instance can be torn down early.
- #1674, for continuations that go through the route: teardown reads the
  worker column and each side-map generation. A continuation started by hand
  outside the route stays unrecorded.
- #1527's two dependent pieces. The message path accepts the successor,
  because the worker column and `dispatch_topic` are rewritten, and the lane
  isn't full, because the predecessor has no row of its own. The issue's
  checkpoint-question shape stays open.
- #1540 as a whole, the same-host rebind case included, through the ledger's
  bound-directory check.

The `superseded` disposition overlaps #1469: a side-map entry whose instance
was reaped outside the run needs the same "gone, nothing waiting on it"
record. This design doesn't close #1469, whose case is a live, merged row held
at reconcile.

## Solution Architecture

### Overview

One handover script serves both sides of a succession, resume state moves
onto commit-keyed carried keys, coordinate gains one event and one dispatch
move, and koto takes a small contract. Everything else is reused.

### Components

- **`scripts/handover.sh write`** runs in the predecessor's lane, or in
  coordinate's or a person's lane for a crashed worker. It refuses unless the
  branch is pushed, HEAD is the pushed head and the template's COMPAT number
  and state are known. It writes the note and gate figures, then sends
  coordinate a `handover` message or, with no outside requester, launches the
  successor with `niwa dispatch`.
- **`scripts/handover.sh open`** runs in the successor, called by the
  work-on, execute and scope openers when the brief has a `continues` block.
  It checks out the branch, confirms HEAD, checks COMPAT, runs the supersede
  init with start-at-state and the carry list, attaches the brief's leg if
  there is one, and checks the note against the brief before the first tick.
- **Newest-member lookup**, lifted from `dc_newest_member` into a shared
  library, used by the scope, execute, execute-coordinated and deliver
  templates and by readers that find a unit's session by name.
- **Resume-state readers**: the verification scripts, `test-change.sh` and
  `lib/acceptance-rule.sh`, and the three gate-figure readers.
- **Coordinate**: the event in `wait` and `report-source.sh`,
  `dispatch-worker.sh --continue`, `render-brief.sh`, `state-schema.jq`, and
  the retire path in `teardown-pass.sh` and `state-holding.sh`.
- **deliver**: a continuation mode in `deliver-open-request.sh`.

### Key Interfaces

`handover/note.json`, written into the predecessor's session and carried:

```json
{
  "v": 1,
  "unit": "<unit id>",
  "branch": "<pushed branch>",
  "pushed_head": "<40 hex>",
  "predecessor": "<koto session name>",
  "template": "work-on",
  "compat": 3,
  "state": "<template state>",
  "clean_tree": true,
  "carry": ["handover/", "impl_base", "review_round", "..."],
  "reason": "<short free text>"
}
```

`handover/gate-figures.json`, beside the note, holds the rule-findings ladder
counts by rule, the recorded decisions the scrutiny gate grades, and the task
text. Each handover writes the snapshot plus its own log's figures, so a chain
of any length carries one snapshot.

The brief's `continues` block, validated by `render-brief.sh`, with the new
leg on the invocation line as `--koto-leg`:

```yaml
continues:
  predecessor: <koto session name>
  branch: <pushed branch>
  pushed_head: <40 hex>
  generation: <N>        # coordinated units only
```

The successor's niwa topic is `<base>-c<N>`, cut to keep the slug unique
within 40 characters, and its koto session name takes the same suffix. The
`handover` message names only the holding's topic and the predecessor's
session; coordinate reads the rest from the note.

The side map sits beside each Holdings row in `record/holdings`, one entry per
earlier generation, and takeover carries it with `record/`. The row's twelve
columns don't change.

```json
{"generation": 1, "topic": "<topic>", "session": "<koto session>",
 "instance": "<niwa instance>", "head": "<40 hex>", "teardown": "pending"}
```

`teardown` moves from `pending` to `superseded`, or to `kept` when the
inventory finds unpushed work. The old leg key moves `open`,
`handover-pending`, `handed-over`; the new request's key is written `open`
with `from` naming the old one, the shape `--releg-imported` already uses.

Elsewhere, `verification_results.json` gains `merge_base`, `os` and `arch`,
and the local cache moves to
`${XDG_STATE_HOME}/shirabe/verification/<head>-<merge-base>/`. The test-change
ledger gains an author line naming each successor and a
`relocate {from, to, head, session}` line.

### Data Flow

A coordinated handover runs in this order:

1. The worker runs `handover.sh write`. On a refusal nothing is written, and
   the worker carries on or reports blocked.
2. The script writes the note and gate figures into the predecessor's session
   and sends coordinate a `handover` message. The worker stops.
3. Coordinate admits the event and runs `dispatch-worker.sh --continue`. It
   checks the note against the row and that the predecessor's session is
   readable here, names the successor, opens the new request, marks the old
   leg key `handover-pending`, adds the predecessor to the side map, rewrites
   the row's worker, `pushed_head` and return path, and launches. The
   handover reads `pending`, with a fresh dispatch's quiet allowance.
4. The successor's opener runs `handover.sh open`: checkout, HEAD and COMPAT
   checks, the supersede init at the predecessor's state, then
   `koto request attach`. A refused attach stops it before its first tick, so
   it can't reach a terminal state unattached.
5. When the successor is the chain's newest member with the new leg bound,
   coordinate abandons the old request with a rationale naming the successor
   and marks the old leg key `handed-over`.
6. A `retire` naming a side-map topic takes the `superseded` disposition once
   the chain's newest member is the row's worker, the instance holds one
   finished job, and its session has been quiet for 600 seconds. The note
   stands in for the handoff comment. The final retire inventories the worker
   column's instance and every generation still pending.

A refusal in step 4, or a successor that outlasts its quiet allowance, fails
the handover: the new leg is marked `spent` and the holding is blocked on the
reason. The old request is abandoned only in step 5. The move is idempotent,
and running it again after a fix launches the next generation.

Other cases:
- **No outside requester.** For a session a person started, the script
  launches the successor itself after writing the note. There's no leg, row or
  pending check; the note is the record.
- **deliver's legs.** The script launches deliver's successor, which starts at
  `open_request`. In continuation mode that step opens the new request and
  captures a new `REQ` without abandoning the old one first. The leg's
  successor attaches to the new request, and deliver then abandons the old
  one. A scope leg that had already finished passes again through scope's
  `resume_route`.
- **A crashed worker.** Coordinate, from its quiet path, or a person runs
  `handover.sh write` on its behalf with origin's head and `clean_tree` false.
  The same move follows, and unpushed work is lost.
- **A worker on another host.** It sends the same message, and coordinate
  launches on its own host, where the request lives. Under the cloud backend
  the successor fences across workspace prefixes; under the local backend the
  move refuses before launch.
- **execute's batch children** stay in place under Decision 1's guard: a
  supersede successor is a root, so its `is_root` gate would misroute it.

## Implementation Approach

Resume-state work comes first because it helps even without succession. The
koto contract runs alongside, and the uncoordinated route lands before
coordinate's so the script is proven on the simplest case first.

### Phase 1: Resume state keyed to commits

shirabe only, with no koto dependency. Closes #1540, the same-host case
included.

Deliverables:
- `run-verification.sh` and `check-verification.sh`: the carried result, its
  five reuse conditions, the platform fields and the commit-keyed cache.
- `test-change.sh` and `lib/acceptance-rule.sh`: the chain author, the
  bound-directory check with `relocate`, and fail-closed host-local
  acceptances.
- The openers write `session/branch` from the checkout and refuse a branch
  mismatch at the same HEAD with a rename hint.

### Phase 2: koto contract

In koto, in parallel with Phase 1. shirabe relies only on the interface and
behaviour below; how koto provides it is koto's design. Item 1 is the most
urgent, since today a fenced predecessor could be bound to a leg it can never
answer.

1. **One bound session per leg.** `koto request attach` and
   `koto init --attach-live` refuse a superseded session with
   `session_superseded`, naming `newest`. `abandon-request` keeps working on
   a self-attached leg, a supersede successor still passes attach admission
   for an open, unbound leg, and requester-side wake rings reach the newest
   member. Acceptance: after supersede and re-leg, the successor's terminal
   tick answers the new leg, and attaching the predecessor is refused and
   writes nothing.
2. **A superseded session is closed.** It counts as stopped for liveness,
   retention and `--replace-terminal`, doesn't keep its dispatcher's hierarchy
   alive, can be reaped with no further write, and stays readable while a
   later member is kept. Acceptance: a parent's children-complete gate counts
   a fenced, non-terminal session as neither done nor failed.
3. **Children report to the newest member.** Acceptance: a batch child of a
   superseded execute session completes and unblocks the successor.
4. **Start at the predecessor's state.** Opt-in, only with `--supersede` and
   `--expect-state`, refused before the fence when the template lacks the
   state. Variables and delivered captures seed the successor's log; no
   evidence or decisions carry, and `koto rewind` refuses at the start state.
   Acceptance: a successor at work-on's `pr_creation` renders `{{BRANCH}}`
   and `{{PR_BODY_RULES}}` without `capture_unset`, and one at execute's
   `spawn_and_await` materializes no second batch.
5. **A read-only chain surface.** `koto status` or
   `koto session hierarchy --json` reports `superseded_by` and `newest`
   without a write, from the bucket under the cloud backend. Acceptance: a
   reader on another host walks the chain to `newest`.
6. **Refusals point at succession.** `execution_anchor_mismatch` and
   `execution_anchor_unresolvable` stop naming rebind as a continuation's fix.

### Phase 3: Chain-aware names, COMPAT and gate figures

Needs Phase 1, and uses `dc_newest_member`'s log walk until koto's item 5
lands. Deliverables: the shared newest-member lookup in the four templates
and the readers; COMPAT numbers and CI fingerprint jobs for work-on, execute
and scope, with each template's carry list beside its number; and the
gate-figure readers adding `handover/gate-figures.json` to their own log.

### Phase 4: Handover script and the uncoordinated route

Needs Phase 3 and koto items 2, 4 and 6.

Deliverables:
- `scripts/handover.sh` with `write` and `open`, including the crashed-worker
  form, and the work-on, execute and scope openers calling `open`.
- Worker guidance: push, hand over at a cheap boundary, never rebind.
- Acceptance: a person-started session at `pr_creation` hands over; the
  successor reuses the suite result and opens no second PR, and the
  predecessor's instance can be reaped.

### Phase 5: Coordinate's handover route

Needs Phase 4 and koto items 1 to 3. Deliverables: the `handover` event and
its admission, `dispatch-worker.sh --continue` with the pending check, the
`continues` block, the side map and leg states, and a coordinate template
COMPAT bump. Acceptance: a leg-bound worker hands over with a leg open at
every step, the lane count unchanged, and the successor's report accepted.

### Phase 6: Teardown of superseded generations

Needs Phase 5 and koto item 2. Deliverables: the `superseded` disposition and
the final retire's inventory across the side map. Acceptance: a predecessor's
instance is retired before the unit merges, and one with unpushed work is
kept.

### Phase 7: deliver's re-leg

Needs Phase 4 and koto items 1 and 3, and can run alongside Phases 5 and 6.
Deliverables: deliver's successor start at `open_request` and the
continuation mode of `deliver-open-request.sh`. Acceptance: deliver hands
over during a scope leg, the leg's successor attaches to the new request, and
the run reaches the outcome it would have reached without the handover.

## Security Considerations

Pending: written once the remaining decisions are settled.

## Consequences

### Positive

- Each assistant session owns a koto session, any session leads to the newest
  one, and takeover and continuation share one verb.
- A stopped predecessor holds nothing, so its instance can be retired before
  the unit merges.
- Any non-terminal state is a valid handover point.
- A successor on any host resumes with the suite result, test-change history,
  review rounds and gate figures, and reruns only what its checkout
  invalidates.
- A handover costs the worker one script and a stop, so bypassing it gains
  nothing.
- A coordinated unit keeps one row and one lane, with a leg open throughout.

### Negative

- koto takes six contract items, and the route can't ship for leg-bound units
  until the first two land.
- shirabe takes the larger share: the script, three openers, the lookup in
  four templates, COMPAT jobs, the gate-figure readers, coordinate's event,
  move, side map and disposition, and deliver's re-leg.
- A handover reads as an abandonment on the old request.
- Off-host continuation needs the cloud backend, and cloud-backend handovers
  inherit koto#560's carry failure until koto fixes it.
- A person acceptance doesn't verify on another host, and a coordinator
  acceptance whose session can't be found from the host stops counting.
- Retry caps that live only in directive prose aren't in the snapshot, so
  they restart with each successor.
- execute's batch children still work in place, a crashed worker's unpushed
  work is lost, and a continuation started by hand stays unrecorded.
- deliver's successor restarts at `open_request` and relies on scope's
  `resume_route` to pass a scope leg that had already finished.

### Mitigations

- The koto items carry acceptance points and are ordered by urgency; the
  shirabe phases that don't need them ship first.
- The abandonment's rationale names the successor, and the old leg key reads
  `handed-over`, so no reader mistakes a handover for a lost worker.
- Off-host under the local backend, the existing stranded-holding route is the
  fallback. The leg moves through the requester, not the carry, so koto#560
  can't strand a leg, and the opener catches a missing note before ticking.
- Host-local acceptances fail closed until someone accepts again; per-host
  signing gets its own decision.
- Worker guidance to push and hand over at a cheap boundary keeps prose retry
  counts and unpushed work small. execute's stopgap is guarded.
- Deferred work has named triggers: koto moving the leg, superseding a
  `--parent` child, and chain-scoped reads if the snapshot proves inadequate.
