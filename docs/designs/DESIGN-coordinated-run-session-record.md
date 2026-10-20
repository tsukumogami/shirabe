---
schema: design/v1
status: Planned
problem: |
  `/execute`'s coordinated loop keeps the node-to-pull-request map, each node's pushed head
  and the only sign the cascade ran as lines in the coordination pull request's body, which
  `coord-common.sh`, `coord-merge.sh` and `node-push.sh` parse on every pass. Moving that
  state into the run's `execute-<topic>` session needs a key layout with one writer per
  fact, one reader every script goes through, a way for the record to survive a pause that
  ends at a koto terminal, a renderer the body is rebuilt from at every transition, a
  recovery path for a host with no session, and a defined fate for `/deliver`'s inner leg
  after an import.
decision: |
  The record is keys under `run/` in the execute session, one per node and per follow-up
  plus `run/setup` and `run/cascade`, written only through `run-record.sh`, whose verbs each
  own fixed keys, and read only through a sourced reader. Pauses stay terminal; the opener
  carries the `run/` keys across the replacement as it already carries `run_id`. A shared
  codec in `scripts/lib/` renders the body from the record, the live Part 1 and live states
  after every transition and parses the rendering for recovery, which setup runs when the
  record is absent. Imports use two new sets of the shared import step, the existing attach
  binds an imported session to a new leg, merges pass Part 1 through a shared
  `squash-message.sh`, and follow-ups enter at setup.
rationale: |
  Per-node keys and a verb-to-key table make one writer per fact mechanical without the
  coordinate skill's multi-writer core. Keeping pauses terminal keeps the leg promotion that
  `/deliver` and coordinators read results from, and the carry reuses the opener's existing
  `run_id` path. One renderer reached from every transition removes the stale index at its
  root, and putting merge observation there gives merged heads an owner without making the
  read-only loop write. A koto spike showed the existing attach already re-legs an imported
  session on one host, so no new leg mechanism is built.
upstream: docs/prds/PRD-coordinated-run-session-record.md
decision_provenance: inline-resolved
---

# DESIGN: The coordinated run's session is its record

## Status

Planned

## Context and Problem Statement

A coordinated PLAN runs through `skills/execute/koto-templates/execute-coordinated.md`, a
thin envelope around a stateless loop: `coordinated-next.sh` computes the one next action
from the PLAN and live GitHub, the agent performs it with `node-cut.sh`, `/work-on`,
`node-push.sh` and `coord-merge.sh`, and repeats until the loop prints `done:<outcome>`,
`pause` or an error. The verdict state `coord_verdict` then ends the session at one of five
terminals; `paused_awaiting_merges` and `ready_awaiting_merge` are terminals too, and a
later `/execute` replaces the finished session with a fresh one through `koto init
--replace-terminal`, carrying only `run_id` (`execute-open.sh`).

Everything the loop knows about what it has done comes back from the coordination pull
request's body. `node-push.sh` writes one PR Index line per node, `- <node> |
<repo>:docs/plans/PLAN-<slug>.md#<n> | open | head=<sha>`, and a `coordination` line after
the cascade pushes; nothing ever rewrites `open` to `merged`. `coord_compute` in
`coord-common.sh` parses those lines on every pass: the map, each node's `head=` as the
merge's expected head, the coordination line's missing `head=` as "the cascade hasn't run",
and, once the cascade has deleted the PLAN, the node list itself. `coord-merge.sh` parses
the same line for the PR and head it merges. The coordination pull request carries no run
marker; node pull requests carry `<!-- shirabe-run: <id> -->`, which `owned-pr.sh` checks,
so a fresh session with a new id finds its own merged nodes foreign and stops at
`error:execute:pr-adopt` (shirabe#733, shirabe#901). `merge-exec.sh` takes an optional
message file, but `coord-merge.sh` and the single-pr `merge_attempt` pass none, so the
whole body lands in the squash commit. The index lists the coordination pull request
itself, which `scripts/coordination-gate-refs.sh` drops by repository and number
(shirabe#748); a follow-up pull request has no way in (shirabe#785).

`DESIGN-scope-then-execute.md` chose this in its sixth decision: per-node koto children
can't wait for a merge, and "the coordination PR, not a machine-local session, is the
durable resume record". The first reason still holds and this design keeps the loop
script-driven. The second no longer does: koto imports a session into another workspace or
host, and the coordinate skill now keeps its own record in its session, through a sourced
reader (`record-source.sh`), a store sealed per run with GitHub the default, and an opener
that resumes, carries and imports.

The requirements this design answers, from `docs/prds/PRD-coordinated-run-session-record.md`:

- the run's facts are session keys on either store: per node its repository, pull request,
  pushed head, whether that head was verified, and its merged head; per follow-up the same
  plus its node; the coordination pull request's number and pushed head; the cascade
  verdict (`not-run`, `pushed` with a head, `failed` with a step); the node list from setup;
  `run_id`; the store; a recovery marker (R1);
- each fact has one owning step, any other write exits 65 `not-owner`, and keys are written
  before the body is rendered from them (R2);
- no script under `skills/execute/` reads a PR Index entry or `head=` from a body, enforced
  by a structure test naming the forbidden symbols and any `head=` pattern (R3);
- merges pass the recorded head to `--match-head-commit`, and a moved live head stops the
  merge with `awaiting:head-moved` (R4); pull request state, checks, review and
  mergeability are never stored, and a failed live read renders `unknown` (R5);
- the store is `github` unless `--store session`, sealed at setup, a different later value
  refused as `store-mismatch`; on `session` a start with no session stops with
  `session-absent` and writes nothing to GitHub (R6, R7);
- with no record, a start recovers from the rendering: ownership lookup, map from the
  rendered index (ignoring a self row), identity from a carried `run_id`, then the rendered
  run line, then unanimous run markers, else `recovery-unproven`; heads re-read live and
  unverified; cascade from the PLAN's presence; a `recovered=<url>` report line; a `failed`
  cascade re-runs next time (R8, R9); an unverified head passes the loop's readiness check
  before a merge (R10); `--adopt-run <id>` re-stamps disagreeing markers and records the
  login and time (R11);
- `execute` and `deliver` import sets, the imported session attached in place, the source
  refusing with `session_migrated` (R12); a pause keeps the record, only merge attempts
  reset (R13); the inner leg ends with the result or `execute-leg-lost:<code>` (R14);
- a render after each listed transition and every terminal, byte-stable, posted only when
  changed, a failed post reported as `body=stale` and retried (R15); `--follow-up
  <node>=<url> [--remove]` with five refusals and the gate held until it merges (R16); the
  rendered body's exact shape, Part 1 kept byte for byte or composed from a fixed sentence,
  no self row, refusal of a private node in a public body, 60,000-byte cap (R17); a `/scope`
  republish re-rendered at the next transition (R18);
- `/deliver` passes `/scope`'s pull request as `--coordination-pr`, verified at setup (R19),
  and reads `/scope`'s intent from its leg (R20); every squash merge passes title and Part 1
  through the land step's builder, refusing with `merge-refused:squash-message` (R21);
- pre-feature runs recover once and stay `github` (R22); the CI gate and its workflow are
  unchanged (R23); one writer at a time (R24).

## Decision Drivers

- **One writer per fact, one way in** (R2, R3). Ownership has to be enforceable by a test,
  not by convention, and the grep-shaped acceptance must hold without moving parsing
  somewhere it can hide.
- **Results still promote** (R14). `/deliver` and coordinators read `/execute`'s result
  from a koto request leg, which koto fills only at a terminal.
- **The page stays CI's** (R23). The reusable merge-last gate reads the body; its marker,
  reference form and self-row rule can't change, and every rendered body has to pass
  `shirabe validate --coordination-body`.
- **No head from the page** (R4, R9). On recovery a head is
  re-read live and re-verified, never taken from the body.
- **Reuse before invention.** `merge-exec.sh`'s message file, the opener's `run_id` carry,
  `run-id.sh restamp`, `merge-verdict.sh`'s readiness check, the land step's message
  builder and the shared import step all exist; the design should extend them.
- **Old runs keep running** (R22). Workers run the installed plugin, so a release with this
  feature meets sessions and bodies an earlier release wrote.
- **Cost per pass.** `coord_compute` runs every loop iteration under koto's 30-second
  action limit; the reader must not add a GitHub read, and koto key reads are local.

## Considered Options

### Decision 1: The record's layout, writers, reader and store seal

Resolved inline.

The loop has one writer at a time, but several steps write different facts: the push, the
cascade, the merge observer, setup, recovery and the follow-up step. The layout decides
whether ownership can be checked and how much each write touches.

Key assumptions:

- the loop has one writer at a time (R24);
- koto keys survive a `--no-cleanup` terminal and can be read until the replacement opens.

#### Chosen: per-node keys under `run/`, one recorder, one reader, the store in `run/setup`

Keys in `execute-<topic>`:

| Key | Holds | Owner (verb of `run-record.sh`) |
|---|---|---|
| `run/setup` | `store`, `coordination_pr`, the node list from the PLAN (`name`, `kind`, `repo`, `waits_on`), `/scope`'s run lines | `setup` (record-coord-setup.sh) |
| `run/node/<node>` | `repo`, `pr`, `head`, `verified`, `merged_head` | `push` (node-push.sh node), `observe` (coord-render.sh), `verified` (record-coordination-verdict.sh), `recover` |
| `run/follow-up/<node>/<n>` (`<n>` the pull request number) | `repo`, `pr`, `head`, `verified`, `merged_head`, `removed` | `follow-up` (setup), `observe`, `verified`, `recover` |
| `run/cascade` | `verdict`, `head`, `verified`, `step` | `cascade` (node-push.sh coordination and the cascade's failure path), `verified`, `recover` |
| `run/recovered` | the pull request recovered from, the identity source | `recover` |
| `run/adopted` | the id, the login, the time | `adopt` |

Within a shared key each verb owns named fields: `push` writes `repo`, `pr`, `head` and
sets `verified: true`; `observe` writes only `merged_head`; `verified` flips only
`verified`. `run-record.sh` holds that verb-to-field table and refuses anything outside it
with exit 65 `not-owner`, changing nothing; a structure test asserts each verb is called
only from its owning script and that no script under `skills/execute/` runs `koto context
add` or `koto context remove` on a `run/` key except `run-record.sh`. The keys rely on
`koto context list --prefix` and on `/` in key names, both present since koto 0.16.0 and
used by the coordinate skill's record; shirabe's koto floor (0.20.0) doesn't move. The reader is a sourced library,
`run-record-lib.sh`, with `rr_setup`, `rr_nodes`, `rr_node <node>`, `rr_follow_ups
<node>`, `rr_cascade`, all local koto reads. The store is sealed in `run/setup` at the
run's first setup and compared on every later one; the invocation's `--store` reaches
setup through a rebind variable, `STORE`, so the comparison happens in the run rather than
as a koto attach refusal.

#### Alternatives Considered

- **One JSON key for the whole record.** Simple to read in one call, but every write
  rewrites every fact, so a push could clobber a merged head recorded a moment earlier, and
  R2's one-writer-per-fact can't be checked per key.
- **The coordinate skill's write core.** It already guarantees provenance, a byte budget
  and a written-time compare, but it's built for many writers over one record and
  validates by rendering a GitHub record body this run doesn't have; a serial loop pays its
  cost for guarantees it doesn't need.
- **Each script writing its keys directly with `koto context add`.** No new script, but
  there is then no single place to refuse a wrong writer, and the structure test could only
  forbid, not route.
- **The store as a fixed koto variable.** koto would refuse a mismatch at attach for free,
  but a fixed variable lives in the session and is gone when a finished session is
  replaced, which every pause does.

### Decision 2: Surviving a pause that ends at a terminal

Resolved inline.

Every pause today ends the session at a terminal, and the next `/execute` replaces it with
an empty one.

Key assumptions:

- a finished session's keys are readable until the replacement opens, as the `run_id`
  carry already relies on;
- an imported finished session is replaced on the importing host the same way.

#### Chosen: pauses stay terminal; the opener carries `run/` across the replacement

`execute-open.sh` already reads `run_id` from the finished session before `koto init
--replace-terminal` and seeds it into the new one. It widens that read to every key under
`run/` (`koto context list --prefix run/`, then `get` each into a private directory) and,
after `opened=new`, restores them through `run-record.sh carry`, the one verb allowed to
write keys it doesn't own, and only into a session holding no `run/` key yet, under a
`mkdir` lock named for the session. The carry validates every field again and clears every
`verified` flag, so each carried head passes the loop's readiness check once more before a
merge. The snapshot directory is kept until the carry succeeds and its path is printed; an
opener that finds a snapshot for a session with no `run/` keys carries from it before
anything else, so a crash between the replacement and the carry loses nothing. With no
snapshot left either, setup's recovery applies (on the `github` store) or the start stops
with `session-absent` (on `session`). `merge_attempts`
isn't under `run/` and isn't carried, so it starts empty on each invocation (R13). A live
session attached in place keeps its keys and needs no carry.

#### Alternatives Considered

- **A non-terminal wait state.** The session would stay live across the pause and the next
  invocation would attach. But koto promotes a result to a request leg only at a terminal,
  so `/deliver`'s execute leg would sit open through every pause, and koto has no wake on a
  GitHub merge to move the state on.
- **A child session per node.** Rejected by the sixth decision of
  `DESIGN-scope-then-execute.md` for a reason that still holds: koto releases `waits_on` on
  a child's terminal success, never on a merge, and deletes a child's context at its
  terminal.
- **Resuming the finished session in place.** koto doesn't tick a terminal session; this
  would need a koto change for a case the carry already covers.

### Decision 3: Where the body is rendered, by what, from what

Resolved inline.

Today only `node-push.sh` writes the body, line by line with `awk`, so merges, the cascade
and terminals never reach it.

Key assumptions:

- comparing the rendered bytes with the live body avoids posting an unchanged one;
- `/scope`'s run lines don't change after publish except on a republish (R18).

#### Chosen: a shared codec, called after every transition, which also observes merges

`scripts/lib/coordination-body.sh` is a sourced library with two halves: `cb_render`
builds a body from a JSON document (the record, live states keyed by pull request, the live
Part 1 or none, the topic and node count for the composed Part 1), and `cb_parse` reads a
rendered or old-format body back into a map for recovery only, refusing a body over 60,000
bytes rather than reading part of it. `skills/execute/scripts/coord-render.sh`
is the one caller that posts: it reads the coordination pull request (`gh pr view --json
body,state,headRefOid`), reads each indexed pull request's state and, for one newly seen
`MERGED`, its merge head, records that through `run-record.sh observe`, renders, refuses a
body over 60,000 bytes (`body=full`), compares bytes, re-reads the body just before
posting and skips the post (`body=stale`) when its Part 1 changed since the render, and
posts with `gh pr edit --body-file` only on a difference. A failed read or post prints `body=stale` and exits 0, so it never changes a
node's loop decision. The coordination pull request is the exception, because CI's
merge-last gate reads the posted body: `evaluate-coordination` and `merge-coordination`
run the renderer first and proceed only on `body=posted` or `body=unchanged`, otherwise
reporting `merge-refused:body-stale`, so the gate never reads an index older than the
record. The recorded `merged_head` is what the index shows for a merged pull request; the
renderer is its reader. A coordination pull request already merged gets no further post:
its body is final at the merge.

It's called by `node-push.sh` after a node's pull request opens or is pushed (replacing
its `awk` surgery), by `node-push.sh coordination` after the cascade pushes and by the
cascade's failure path, by the follow-up step at setup, and by the `coord_verdict` default
action before every terminal; a loop pass that observes a merge calls it from
`record-coordination-verdict.sh` too. The rendered body:

~~~
<Part 1: the live one, byte for byte, or the composed sentence>

---

> This is a **coordination PR** for a coordinated effort. It is docs-only and
> merges **last**, once every indexed PR has merged and finalization is complete.
> See `references/coordination-strategy.md`.

topic=<slug>
exit=<...>
outcome=<...>
intent=<...>
mode=coordinated
store=<github|session>
run=<32 hex>

## PR Index

- <node> | <repo>:docs/plans/PLAN-<slug>.md#<n> | <open|merged|closed|unknown> | head=<sha>
- <node>/follow-up-<n> | <repo>:docs/plans/PLAN-<slug>.md#<n> | <state> | head=<sha>

## Merge Order

```merge-order
...
```
~~~

The composed Part 1 is exactly `Coordination pull request for <topic>. It carries the
planning documents for <n> node pull requests and merges after all of them.` The merge-order
block keeps today's renderer, and a `shirabe-run` marker found anywhere in the live body is
kept at the end, as `node-push.sh` keeps it today. A record holding a node in a private
repository under a public home is refused (`execute:visibility`) without naming the
repository, matching `coord_node_visibility`.

#### Alternatives Considered

- **Keep rendering in `node-push.sh`.** The smallest change, but it can't see a merge, the
  cascade or a terminal, which is how the index goes stale today (shirabe#785).
- **Render in CI.** CI runs on every body edit and already parses the index, but it has no
  session to render from and would be a second writer.
- **Render Part 1 from a template every time.** Uniform, but it overwrites a person's
  edits to the description the squash commit carries.

### Decision 4: Recovery

Resolved inline.

A `github`-store start with no record has to rebuild one without trusting a head on the
page.

Key assumptions:

- `coordinated-next.sh` can route an unverified head through its existing evaluate step;
- `run-id.sh restamp` works on a merged pull request's body.

#### Chosen: setup recovers when `run/setup` is absent; unverified heads re-verify in the loop

`record-coord-setup.sh` already checks the write set, the branch and the home. When
`run/setup` is absent it decides: a `session` store stops with `session-absent` before any
GitHub call; otherwise it runs recovery:

1. the coordination pull request through `coord_find_pr` (ownership lookup and the
   declaration marker), `coordination-pr-missing` for none, `coordination-pr-ambiguous` for
   several, or, with `--coordination-pr`, that pull request after the same check
   (`coordination-pr-mismatch` when they differ);
2. `cb_parse` over its body: the map and follow-ups, any line naming the coordination pull
   request itself dropped; a body with no index line and no PLAN stops with
   `coordination-pr-missing`;
3. the node list from the PLAN when the branch has it, otherwise from the map;
4. identity: the session's `run_id` when it holds one, else the rendered `run=` line, else
   the run marker every node pull request in the map agrees on, else (no index line at all
   and nothing marked) a minted one. Every pull request in the map must be in a repository
   the PLAN or the map's own node names, pass the ownership lookup on its node's branch
   (`impl/<slug>-<node>`), and carry a run marker equal to that identity; one with another
   marker, or none, stops the start with `recovery-unproven`, naming each;
5. each pull request's head from `gh pr view --json headRefOid` (a merged one's merge head
   for `merged_head`), all written with `verified: false` through `run-record.sh recover`;
6. the cascade: `not-run` with the PLAN on the branch, otherwise `pushed` at the
   coordination pull request's live head, unverified;
7. `run/recovered`, and `recovered=<url>` on the invocation's report.

In the loop, `coord_compute` treats an unverified head as needing evaluation: the next
action for that pull request is `evaluate:<node>` (or `evaluate-coordination`), which runs
`merge-verdict.sh` at the recorded head and, when it passes, `run-record.sh verified`.
`merge:<node>` is never printed for an unverified head. A `failed` cascade prints `cascade`
again. `--adopt-run <id>`, a rebind variable, is honoured only when the last result was
`recovery-unproven`: setup re-stamps each disagreeing marker with `run-id.sh restamp`,
seeds `<id>`, and writes `run/adopted` with `gh api user --jq .login` and the time. It re-stamps
only pull requests the recovery step named, in the PLAN's repositories, on their node's
branch and authored by the invoking login, the same set the ownership lookup admits.

#### Alternatives Considered

- **A separate recovery state before setup.** Clearer in the state graph, but it would
  re-run the write-set and branch checks setup already owns, and every new state is a new
  terminal mapping in the result maps.
- **Majority identity.** Recovers more runs unattended, but lets a run adopt a node another
  run opened; the adopt step makes that a recorded act instead.
- **Heads from the rendered index.** Saves one read per pull request, but puts the editable
  page back in the merge decision, which this design rules out.

### Decision 5: Moves, the inner leg and the handover from `/scope`

Resolved inline.

koto's request store is host-local, and `/deliver` opens a fresh request on every run. A
spike on koto 0.20.1, over a fake S3 bucket with two workspaces sharing one home, measured:
the source copy answers `session_migrated` after the import; the old request's leg stays
bound to the session by name; a new request's `koto init --attach-live --koto-leg
<new>:execute` binds the imported live session (`outcome: attached`); its terminal result
is promoted to the new leg, and the old request, abandoned, ends `abandoned`.

Key assumptions:

- on another host, an imported session attaches the same way, the import having rewritten
  its origin.

#### Chosen: the existing attach re-legs; a missing request is a named loss; the handover rides the leg

`scripts/skill-session.sh import` gains `execute` (`execute-<topic>`) and `deliver`
(`deliver-<topic>`), compiling `execute.md`, `execute-coordinated.md` and `deliver.md` from
the plugin root on the importing host before `koto session import`. A `/deliver` started
after the import opens its request as today and `/execute`'s opener attaches the imported
session to the new leg. A `/deliver` session resumed in place whose request the host's
store doesn't hold reaches its `exec_leg` gate with `disposition: missing`, which now maps
to `done_error` with `reason: execute-leg-lost:request_not_found`; a refused attach
(`source: refused`) maps to `execute-leg-lost:<koto code>`. Both reports name the execute
session's state from `koto status`.

The handover: the `execute_run` directive passes `--coordination-pr
${gates.scope_leg.payload.pr}`, already copied into `/deliver`'s context at
`scoped_check`, and `--store` when `/deliver` was given one. `deliver-probe.sh scoped`
takes the leg's `intent` and `pr` as arguments instead of calling `publish-scoping-pr.sh
--verify`, which read `intent=` off the body; it still verifies the pull request through
`owned-pr.sh`.

#### Alternatives Considered

- **An execute-side re-leg command**, like the coordinate skill's `dispatch-worker.sh
  --releg-imported`. Explicit, but it duplicates what the opener's attach already does, as
  the spike showed.
- **A resumed `/deliver` opening a second request.** It would cover the missing-request
  case without a fresh run, but it rewrites a request id captured at `open_request`
  mid-run, for a case a fresh `/deliver` already handles.
- **Keep the body `intent=` read.** No `/deliver` change, but it keeps the page copy as a
  source, which the feature removes.

### Decision 6: The squash message

Resolved inline.

#### Chosen: one builder in `scripts/lib/`, passed as `merge-exec.sh`'s message file

`skills/coordinate/scripts/squash-message.sh` moves to `scripts/lib/squash-message.sh`
with its test, unchanged, and `land-merge.sh` calls it there. `coord-merge.sh` and the
single-pr `merge_attempt` read the pull request's title and body, run it, and pass its
output as `merge-exec.sh`'s fourth argument; a non-zero exit from the builder (empty Part 1,
a multi-line title, AI attribution) skips the merge with `merge-refused:squash-message`.
`merge-exec.sh` already passes no message for `rebase` and the same one for `merge`.

#### Alternatives Considered

- **Call the coordinate skill's copy from `/execute`.** No move, but a dependency from
  `/execute` onto a script the coordinate skill may change for its own reasons.
- **A second builder in `/execute`.** Two copies of the stripping and attribution rules to
  drift apart.
- **Title only.** Simplest, but the default branch then loses the description a reader
  should find there.

### Decision 7: Follow-ups

Resolved inline.

#### Chosen: `--follow-up <node>=<url> [--remove]`, recorded at setup, merged after its node

`execute-open.sh` maps the flag to a rebind variable, `FOLLOW_UP`. Setup, after the record
is loaded or recovered, checks it (the node in `run/setup`, the pull request in the node's
repository, based on its default branch, not from a fork, authored by the invoking GitHub
login, not closed unmerged) and records it through
`run-record.sh follow-up` with its live head and `verified: false`, so the loop's evaluate
step checks it before any merge, as it does a recovered head; `--remove` sets `removed`. `coord_compute` adds each live
follow-up as a pull request after its node, named `<node>/follow-up-<n>` by its number so two
on one node stay distinct: `merge:<node>/follow-up-<n>` only after the node is merged, and the coordination pull request's merge-last gate counts its index line through
`coordination-gate-refs.sh` unchanged. A follow-up closed unmerged is reported
`follow-up-closed:<url>` and blocks `evaluate-coordination`.

#### Alternatives Considered

- **Discover follow-ups on GitHub** by branch or title. No flag, but any pull request that
  matched could hold the gate.
- **A separate `/execute` subcommand** that records and exits. Smaller, but a second entry
  point with its own copy of the opener's checks.
- **Record follow-ups in the coordinator's record.** Puts a run fact in a coordinator's
  store, which a direct `/execute` doesn't have.

## Decision Outcome

The run's facts move into `execute-<topic>` under `run/`, one key per node, per follow-up,
for setup and for the cascade, each field owned by one verb of `run-record.sh` and read
through `run-record-lib.sh`. Pauses stay terminal so results keep reaching legs, and the
opener carries `run/` across each replacement the way it carries `run_id`. The body becomes
the output of one renderer, `coord-render.sh` over the shared `coordination-body.sh`, run
after every transition and before every terminal; the renderer is also where a merge is
first seen and its head recorded. A start with no record recovers in setup from the
rendering and live reads, never trusting a head on the page, and an unverified head
re-verifies through the loop's existing evaluate step. Imports use two new sets of the
shared import step, `/deliver`'s inner leg re-binds through the existing attach or ends in a
named loss, `/deliver` hands `/scope`'s pull request and intent over from the leg, merges
pass Part 1 through one shared builder, and follow-ups enter through setup.

Together these remove every body parse from `skills/execute/`: the index-entry grammar and
its functions move into the codec's recovery half, which only setup calls, and only when
the record is absent.

## Solution Architecture

### Overview

```
execute-open.sh  --carry run/*-->  execute-<topic> session (run/ keys)
      |                                ^            |
      v                                |            v
record-coord-setup.sh --setup/recover/follow-up--> run-record.sh  <-- node-push.sh (push, cascade)
      |                                ^                         <-- coord-render.sh (observe)
      v                                |                         <-- record-coordination-verdict.sh (verified)
coordinated-next.sh / coord_compute --rr_*--> run-record-lib.sh
      |
      v
coord-merge.sh --rr_*--> merge-exec.sh <message from scripts/lib/squash-message.sh>
      |
coord-render.sh --cb_render--> scripts/lib/coordination-body.sh --> gh pr edit (coordination PR)
                                                       ^
                       CI lifecycle.yml + coordination-gate-refs.sh read the posted body (unchanged)
```

### Components

- **`skills/execute/scripts/run-record.sh`** (new): verbs `setup`, `push`, `observe`,
  `verified`, `cascade`, `follow-up`, `recover`, `adopt`, `carry`; each validates its input
  (node ids `^[a-z][a-z0-9-]*$`, 40-hex heads, `owner/repo`, positive numbers) and the
  verb-to-field table, writes with `koto context add`, and exits 65 `not-owner` for a field
  outside its row. `carry` writes only into a session with no `run/` key.
- **`skills/execute/scripts/run-record-lib.sh`** (new): sourced reader, `rr_*` functions
  printing JSON; no GitHub call.
- **`scripts/lib/coordination-body.sh`** (new): `cb_render`, `cb_parse`, and the index-entry
  grammar moved from `coord-common.sh`.
- **`skills/execute/scripts/coord-render.sh`** (new): the observer and poster; prints
  `body=posted`, `body=unchanged`, `body=stale` or `body=full`.
- **`scripts/lib/squash-message.sh`** (moved from `skills/coordinate/scripts/`).
- **Changed**: `execute-open.sh` (the carry; `--store`, `--coordination-pr`, `--follow-up`,
  `--remove`, `--adopt-run` mapped to rebind variables), `execute-coordinated.md` (the five
  variables; `coord_verdict`'s action renders before routing, amending the template's
  statement that the verdict step writes nothing to GitHub; result maps gain `body` and
  `recovered`, and each new stop token reaches a terminal's `reason`: setup's stops through
  `done_error`, the loop's through `done_blocked`), `record-coord-setup.sh` (record, store seal, recovery, follow-ups, the
  handed pull request), `coord-common.sh` (`coord_compute` reads `rr_*`; unverified heads
  and follow-ups; no body parse), `node-push.sh` (writes through `run-record.sh` and calls
  `coord-render.sh` instead of editing the body), `coord-merge.sh` (the recorded head and the
  message file), `execute.md`'s `merge_attempt` (the message file),
  `record-coordination-verdict.sh` (records `verified`, calls the renderer),
  `skills/execute/SKILL.md` (the closed write-target set), `scripts/skill-session.sh` (two
  import sets), `skills/deliver/koto-templates/deliver.md` (the handover arguments, the
  `execute-leg-lost` routes), `skills/deliver/scripts/deliver-probe.sh` (intent and pull
  request from the leg), `skills/coordinate/scripts/land-merge.sh` (the builder's new path),
  `references/coordination-strategy.md` and `docs/designs/current/DESIGN-scope-then-execute.md`
  (dated amendments).

### Key Interfaces

```
run-record.sh <verb> --session <S> [--node <n>] [--json <file>]   # exit 0 | 64 usage | 65 not-owner | 66 invalid
run-record-lib.sh: rr_setup S | rr_nodes S | rr_node S <n> | rr_follow_ups S <n> | rr_cascade S
coord-render.sh --session <S> --slug <slug> --home-repo <r> --coord-branch <b>
cb_render <doc.json>  -> body on stdout          cb_parse <body-file> -> {nodes, follow_ups, run}
execute-open.sh ... [--store github|session] [--coordination-pr <url>]
                    [--follow-up <node>=<url> [--remove]] [--adopt-run <32 hex>]
skill-session.sh import execute|deliver <topic> --from <workspace>
```

New report tokens and stops: `store-mismatch`, `session-absent`, `coordination-pr-missing`,
`coordination-pr-ambiguous`, `coordination-pr-mismatch`, `coordination-pr-closed`,
`recovery-unproven`, `recovered=<url>`, `body=stale`, `body=full`,
`merge-refused:squash-message`, `follow-up-node`, `follow-up-repo`, `follow-up-base`,
`follow-up-closed`, and `/deliver`'s `execute-leg-lost:<code>`.

### Data Flow

1. `/deliver` reads `/scope`'s leg (`pr`, `intent`), runs `deliver-probe.sh scoped` on
   them, then `/execute --coordinated ... --coordination-pr <pr> [--store ...]`.
2. `execute-open.sh` snapshots `run/` from a finished session, opens or attaches, carries.
3. Setup: with `run/setup`, compare the store and the handed pull request; without it,
   seal a new record or recover; then record any follow-up and render.
4. Loop: `coord_compute` reads the record and live states; `dispatch` → `node-push.sh` →
   `run-record.sh push` → render; `evaluate` → readiness → `run-record.sh verified`;
   `merge` → `coord-merge.sh` with the recorded head and Part 1; `cascade` →
   `run-record.sh cascade` → render.
5. `coord_verdict`: observe merges, render, route to a terminal; the result reaches the leg.

## Implementation Approach

Phases 1 to 3 change what a running loop reads, so they ship in one release: a release
holding Phase 1 without Phase 3 would meet pre-feature runs with no record and no recovery.
No release is cut between their merges.

### Phase 1: The record and its seam

`run-record.sh`, `run-record-lib.sh`, a shared test helper that seeds a record, the
opener's carry and the five variables, setup's store seal, node list and handed pull
request, `node-push.sh` writing heads through the recorder, `coord_compute` and
`coord-merge.sh` reading the record, and merges pinned to the recorded head. The body is
still written by `node-push.sh` as today during this phase, and the index-entry grammar is
still defined in `coord-common.sh` for it.

Deliverables: the two new scripts, the test helper and their tests; `execute-open.sh`,
`record-coord-setup.sh`, `coord-common.sh`, `node-push.sh`, `coord-merge.sh`, the template;
`skills/execute/SKILL.md`'s write-target set.

### Phase 2: The rendering and the squash message

The shared codec and `coord-render.sh` at every transition and terminal, merge observation,
Part 1 handling, no self row, the size cap, `node-push.sh`'s body surgery removed, the
builder moved to `scripts/lib/` and passed on every merge.

Deliverables: `scripts/lib/coordination-body.sh`, `coord-render.sh`,
`scripts/lib/squash-message.sh`, `land-merge.sh`, `coord-merge.sh`, `execute.md`, renderer
and merge tests, the eval fixtures' bodies.

### Phase 3: Recovery and adoption

Recovery in setup, `session-absent`, unverified heads through evaluate, `--adopt-run`, and
pre-feature runs.

Deliverables: `record-coord-setup.sh`, `coord-common.sh`, `run-id.sh` use, recovery tests
over old-format and rendered bodies, and the structure test (R3), which can pass only once
the grammar has left `skills/execute/` for the codec.

### Phase 4: Follow-ups

`--follow-up` and `--remove`, the setup checks, follow-ups in `coord_compute`, the merge
after the node, and the gate held.

Deliverables: `execute-open.sh`, `record-coord-setup.sh`, `coord-common.sh`, tests.

### Phase 5: Moves and the handover

The two import sets, `/deliver`'s handover arguments and intent from the leg, the
`execute-leg-lost` routes, and the end-to-end engine test the PRD's first acceptance
criteria describe.

Deliverables: `scripts/skill-session.sh`, `deliver.md`, `deliver-probe.sh`, an engine test
under `skills/execute/scripts/` over `skills/coordinate/scripts/testdata/cloud-hosts.sh`.

The dated amendments land with the phase whose behavior they describe: Phase 1 rewrites
`skills/execute/SKILL.md`'s statement of where the run's state lives and its closed
write-target set; Phase 2 amends `references/coordination-strategy.md` (the state lives in
the run's session and the body is its rendering, replacing "no session file is the source of
truth") and adds a dated amendment to the sixth decision of
`docs/designs/current/DESIGN-scope-then-execute.md`, keeping its logic and recording that
the machine-local objection no longer holds.

## Security Considerations

The record holds what the body held before (pull request numbers, repositories, heads, the
run id) plus the store and the adopt record's GitHub login. It stays in the session store;
the renderer posts only what the index already showed, and never on a `session`-store start
that found no session.

**Untrusted input.** The coordination body and the run markers are editable by anyone with
write access, and after this change only recovery reads the body. `cb_parse` keeps today's
grammar (node ids `^[a-z][a-z0-9-]*$`, `owner/repo`, plan paths with `..` and `//`
refused, 40-hex heads ignored) and reads at most the renderer's 60,000-byte cap. Recovered
values reach `run-record.sh` as JSON data, never as shell text. A recovered pull request is
adopted only when it's in a repository the PLAN or its node names, passes the ownership
lookup on its node's branch (which requires the invoking login as its author, the
default base and no fork), and carries a run marker equal to the run's identity; anything
else stops the start with `recovery-unproven`. A body over the cap is refused, not read in
part. No head is read from the body.

**Carried and imported keys.** `carry` treats keys as data: names are matched against the
fixed `run/` layout before use, every field is validated again by `run-record.sh`, and
`carry` writes only into a session holding no `run/` key. An imported session supplies keys
only; templates and scripts always come from the importing host's plugin root, compiled
there by the import step. A follow-up's head is recorded unverified and checked like a recovered
one, and a follow-up must be authored by the invoking login, outside a fork, on the node's
repository and base. Every carried head comes back unverified too, and setup checks every
carried repository against the PLAN's write set before any GitHub call, so a key edited in
the session store can't skip the readiness check or point the run at another repository.
The session store itself is part of the trusted base: koto's import checks that the session
is a root compiled from a template it holds, not what its keys say, and a person who can
write the store already runs as the user.

**Merges.** A merge is pinned to a head this run pushed and verified, or one re-read live
and re-verified by the same readiness check. The editable page can no longer pin one.

**Adoption.** `--adopt-run` is the one operation that edits another run's markers. It's
honoured only on an invocation after a `recovery-unproven` stop, re-stamps only the pull
requests that stop named, in the PLAN's repositories, on their node's branch and authored by
the invoking login, and records the login and time in `run/adopted`.

**Posting.** The renderer re-reads the body just before posting and skips the post when
Part 1 changed since it rendered, so a person's concurrent edit to the description isn't
overwritten; the next transition renders again. That narrows the window rather than closing
it. A stale or oversize body never reaches the merge-last gate unnoticed: the coordination
pull request is evaluated and merged only after a render that posted or found nothing to
change, so CI's gate reads an index at least as new as the record.

**Public text.** The squash message is Part 1 through the shared builder, which strips HTML
comments and refuses AI attribution and `Co-authored-by` trailers. Closing keywords and
mentions in Part 1 are left as written: a description that closes an issue on merge is what
its author meant, and the builder doesn't second-guess it. A public coordination pull request never names a
private node: the visibility check fails closed, and its refusal names the node, never the
private repository; the renderer's tests cover node and follow-up lines and the run lines.
Rendered bodies and report lines carry pull request URLs, heads and koto
codes, never workspace paths, session-store locations or tokens, and the renderer's tests
check that.

**Residual risk.** A person with write access can still edit the body to make a recovery
stop (`recovery-unproven`). Run markers can be copied, but a copied one can't steer
recovery toward another author's pull request, because the ownership lookup admits only the
invoking login's. They can edit the rendered region, which the next transition overwrites, and the
coordination merge waits for a fresh render. The CI merge-last gate is unchanged and
recomputes every state live; its input is now the renderer's output, which the
coordination merge keeps current. Two `/execute` invocations at once on one topic remain
unsupported (R24); koto refuses a second workspace's attach and the carry's lock covers the
one window where two openers could both write. The adopt record's login stays in the
session store and is never rendered.

## Consequences

### Positive

- A moved or restarted run keeps its identity and adopts its own merged nodes, closing
  shirabe#733 and shirabe#901 without a hand-set id.
- The index is current after every transition, lists follow-ups and drops the self row,
  closing shirabe#785 and shirabe#748.
- The default branch's squash commits carry Part 1 only, on both merge paths.
- `/execute` no longer parses the body, and an edit to it can't pin a merge.

### Negative

- Every transition costs one extra coordination pull request read and, when something
  changed, one edit; each pass of the verdict action adds a state read per indexed pull
  request.
- Two more places hold the run's state for a reader to understand: the session keys and the
  rendering, where there was one.
- A pre-feature run's first start under this release runs recovery, one extra pass of reads.
- The coordinate skill's land step now depends on a script under `scripts/lib/`.

### Mitigations

- The renderer posts only on a byte difference, and the state reads are the ones
  `coord_compute` already makes; `body=stale` keeps a failed post from costing a decision.
- `skills/execute/SKILL.md` names the record as the store and the body as its rendering, and
  the amended coordination contract says the same, so a reader has one statement to trust.
- Recovery is once per run; after it the record is in the session.
- The move of `squash-message.sh` keeps its tests and contents byte for byte.
