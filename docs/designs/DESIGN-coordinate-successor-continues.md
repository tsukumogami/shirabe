---
schema: design/v1
status: Proposed
problem: |
  A /coordinate successor can't continue the run it takes over. The opener
  finds the run by name prefix, opens a second run, copies record/ and legs/
  key by key, and cancels the first; nothing fences a predecessor that is
  still ticking, legs keep ringing the cancelled run, lineage is walked by
  name and cancel event, and imports fail on plugin path or template bytes.
  koto now records a continues relation, but nothing builds a takeover on it.
decision: |
  The successor is opened by koto init --continues --supersede, which first
  fences the run's newest member (an event in its own log, first writer
  wins, nothing written if it can't), then creates the successor with its
  relation, copies the run's named key families from the fenced snapshot,
  and rings the predecessor's wake file once. koto's
  request store forwards a ring along supersede records, so legs reach the
  newest member. Template continuation is decided by a compat number the
  template declares and CI keeps honest. Workers resolve the newest member
  themselves when they report, and a worker that can't be told is pending.
rationale: |
  The fence has to live in koto because only koto serializes every write to
  a session, including a tick that is already in flight, and only koto can
  refuse a predecessor's koto next by name. Doing the copy inside the same
  verb makes the snapshot consistent and keeps the no-driver window to one
  command, at constant cost per takeover. A declared compat number is the
  only rule that catches a gate whose meaning changed without its shape
  changing. Workers resolving their coordinator at report time is the only
  way a stopped worker learns an address without anyone resuming it.
upstream: docs/prds/PRD-coordinate-successor-continues.md
decision_provenance: inline-resolved
---

# DESIGN: A coordinator's successor continues its run

## Status

Proposed

## Context and Problem Statement

A `/coordinate` run is driven by one Claude session at a time, through one
koto session compiled from `skills/coordinate/koto-templates/coordinate.md`.
The Claude session is replaced several times a day. Today the replacement is
`skills/coordinate/scripts/coordinate-open.sh`: it finds the earlier run with
`state-read.sh --candidate`, which lists root sessions named
`coordinate-<slug>-<stamp>` holding `record/meta` and takes the newest; it
opens a new session, cancels every other live run of the slug with `koto
cancel`, and copies every `record/` and `legs/` key into the new session one
`koto context get` and one `koto context add` at a time
(`state-write-core.sh`, `core_carry`). It then links the new session to the
old one with `dispatched-by`. That link is the only lineage pointer; the
deferral check's `coord-log.sh chain-start` ignores it and walks back
through same-prefix sessions while each has a `workflow_cancelled` event,
and the on-reap cost sweep (`unit-removed.sh`) charges a removed worker to
its leg's `requested_by` if that session is live, else to the slug's one
live run.

The PRD for this feature fixes what the takeover must do instead. A
successor records, in its own session, that it continues the run's newest
member through koto's continues relation (R1), whoever launched it (R2). It
claims the run exactly once even when two successors race, and refuses with
a reason code for an ambiguous scope, a predecessor that isn't the newest
member, or a run another successor took (R3). When the predecessor is live
it stops it from driving the run and refuses only when it can't
(`predecessor-unstoppable`); from the moment the open returns at most one
session drives the run, and a predecessor tick or record write already in
flight either completes before the successor's first tick or is refused
(R4). Every later attempt by a predecessor to drive the run is refused
naming the newest member (R5), and an interrupted takeover converges when
the same command is re-run (R6). The successor starts from every record
section, entry and posted reference, every leg and which were taken, and the
run's chain start and standing go-aheads, while facts rebuilt per visit
(`coord/*`, `reconcile/*`) and log seals are its own (R7); its first
reconcile reports every holding the predecessor's last one did (R8), and its
first tick needs no rebind (R9). A successor at another plugin path, checkout
or newer version continues when the template is compatible (R10) by a
stated rule whose floor the PRD fixes: identical or directive-text-only
changes continue, and a change to a state, transition, evidence field,
variable or a gate's meaning refuses (R11), writing nothing (R12). The
coordinator address moves (R13), the told set restarts and a re-brief
records told once its message is accepted (R14), a worker that can't be told
is pending and turns told on its first report (R15), and a worker reaches the
newest member when it next starts, with nobody editing its brief (R16). A leg
any earlier member opened wakes the newest member's watch within 10 seconds
(R17); the successor ends with a watch armed and no predecessor watch running
(R18). Lineage readers follow the relation (R19), with the recycled-
coordinator `dispatched-by` link for runs carried before this feature (R20).
All of it holds after an import into a second workspace on the same host
(R21), within koto's 30-second action cap on a 65-entry run at load 25 (R22),
with a fixed `key=value` result contract (R23), a koto floor (R24), and no
authority read from the relation (R25).

koto's side is partly built. `koto init <name> --continues <pred>
[--continues-from <workspace>]` and `koto session link --continues` are on
koto's main branch (tsukumogami/koto#481), with retention reading the relation
as a one-way keeper; under the cloud backend that first part refuses a
relation it can't back with a bucket pointer, which the bucket walk lifts,
and import keeping its source as a read-only predecessor is a third part
(the design is tsukumogami/koto#479). Three things this feature needs are in
none of those parts. The relation never stops or fences a predecessor: koto's
only refusals that name another session are the cloud-only `session_migrated`
marker and the rebind fence for one session changing directory. koto has no
process-liveness signal: "alive" in retention means the log isn't terminal.
And koto's request store is host-local and keyed by name: a request's header
names `requested_by` and `coordinator_of_record` once, `ring_principals` and
the per-tick wake pass ring only those names' wake files under
`~/.koto/wakes/`, and `koto request watch` exits only on a wake, its deadline
or a signal.

Three shirabe facts shape the rest. The record's mutable sections are whole-key
rewrites in the run's own session, while `record/entries/NNNNNN` and
`record/posted/NNNNNN` are append-only and unbounded, so a key-by-key copy
costs two koto calls per entry, 0.3 to 1 second each on the cloud backend.
`taken_legs` is the one non-record key whose loss changes behaviour: without
it a successor takes legs again. And a worker's coordinator address is baked
into its brief file once; nothing re-reads it on resume.

## Decision Drivers

- **One driver, enforced where every write passes.** R4 and R5 need a
  refusal that a predecessor's `koto next`, its context writes and an
  in-flight tick's final append all hit. Only koto sees all three.
- **Exactly one winner.** Two successors racing must not both take the run
  (R3), and the claim must survive crashes between steps (R6).
- **Short no-driver window, constant cost.** The predecessor is fenced before
  the successor's first tick; anything slow between those two moments is time
  with no driver. R22 caps every koto action at 30 seconds on a 65-entry run
  at load 25, so per-entry work in the window is out.
- **A compatibility rule that can see meaning.** R11 requires refusing a
  change that keeps a gate's shape and changes its meaning, which no diff of
  the compiled template can see.
- **No resume to tell.** R15 and R16 forbid waking a worker to deliver an
  address, so the worker has to find the address itself.
- **Reuse koto's existing primitives.** Log appends are serialized under an
  exclusive `flock` locally and by a conditional push on the bucket since
  tsukumogami/koto#480; koto already has an exactly-one-winner claim sidecar
  (`src/engine/claim.rs`) and an epoch fence for child assignments. A new
  fence should follow those patterns rather than invent another.
- **Keep the relation authority-free.** R25 and koto's own design forbid any
  authority check reading the relation; the fence is a separate record.
- **Build what can be built before koto's relation ships.** The
  compatibility rule and the told/pending changes don't need koto; the
  takeover itself does.

## Considered Options

### Decision 1: How the takeover fences the predecessor, claims the run once and carries what it holds

Resolved inline.

This is the core of the feature. The takeover has to do four things in an
order that never leaves two drivers and never leaves the run claimed by
nobody after a crash: open the successor with the relation, stop the
predecessor from driving, carry what the run holds into the successor, and
make the claim exclusive. The PRD settled that a live predecessor is
stopped rather than waited for, and that the stop must catch an in-flight
tick. This decision settles where the stop lives, how the claim is made
exclusive, and whether the run's holdings are copied or read through.

This is the design's one critical-tier question, which a direct run would
hand to `/decision`. It was resolved inline here, weighing the alternatives
below against the drivers above, and is the first thing a reviewer of the
plan should challenge.

#### Chosen: `koto init --supersede`, which fences first and creates the successor only after the fence holds

koto's `init` gains `--supersede`, used with `--continues`: `koto init <SUCC>
--continues <PRED> --supersede [--carry <prefix>]... [--continues-from
<workspace>] [--expect-state <state>]`. The successor's session id is minted
before anything is written, and the command runs these steps in order:

1. **Check.** Read `<PRED>`'s log. If it already carries a
   `session_superseded` event naming `<SUCC>` (same name and session id), go
   to step 3: this is a re-run. If the event names another session, exit 2
   with `superseded_by=<other>` and write nothing. If `<PRED>`'s current
   workflow state isn't `--expect-state`, exit 2 `stale_state` and write
   nothing; the opener's preflight decided compatibility against that state.
   Refuse `self` and `cycle` (a successor already in `<PRED>`'s forward chain
   or holding `<PRED>` in its own relation ancestry).
2. **Fence.** Append `session_superseded {by, by_session_id, actor: {claude
   session, host, user}, at}` to `<PRED>`'s log under its existing write
   serialization: the per-append exclusive `flock` on the local backend, and
   on the cloud backend a pull of `<PRED>`'s state and a push conditional on
   that copy, as every cloud write has done since tsukumogami/koto#480. The
   lock is held for one append, never for a tick, so the fence waits
   milliseconds, not the length of a predecessor's tick. If the lock can't be
   taken within 10 seconds, or the conditional push is refused or fails, exit
   3 `fence_unavailable` with nothing written anywhere. Of two successors, the
   first append wins and the second reads it at step 1.
3. **Create.** Create `<SUCC>` with its header and its continues relation
   (the existing `--continues` path), unless it already exists from an
   earlier run of this same command.
4. **Carry.** Copy every context key under each `--carry` prefix from
   `<PRED>`'s fenced state into `<SUCC>`: one read of `<PRED>` and one write
   batch to `<SUCC>` (one pull and one push on the cloud backend), skipping
   keys `<SUCC>` already holds with the same value. Then write
   `koto/superseded-carry-complete` in `<SUCC>`. A re-run that finds the
   marker skips this step.
5. **Ring.** Ring `<PRED>`'s wake file once (Decision 3) and print
   `superseded=<PRED>`, `carried=<n>`, `forward=<SUCC>`.

Because nothing is created before the fence, every refusal writes nothing: a
rival that loses at step 1, a stale preflight, and an unavailable fence
(`fence_unavailable`, which the opener reports as `predecessor-unstoppable`)
all leave the store exactly as they found it, and the predecessor still
drives. On the local backend a test forces `fence_unavailable` by holding
`<PRED>`'s log lock past the 10-second wait.

From the fence on, koto refuses every attempt to drive `<PRED>`: `koto next`,
every context write and every log append check for a `session_superseded`
event and exit with `session_superseded`, naming the newest member reached by
following supersede events forward and echoing the fence's actor. Because the
lock is per append, a predecessor tick that started before the fence runs its
gates and actions and is refused at its final append; a context write a
coordinate script makes inside that tick is refused the same way. On the cloud
backend the tick's conditional push conflicts with the fence, koto pulls,
sees the event and refuses. An action's side effect outside koto (a worker
dispatched through niwa whose record write was then refused) leaves no record
row; the successor's first reconcile finds it through its existing host check
as an instance with no holding and reports it, which is how it already
treats an unrecorded instance. Reads of `<PRED>` keep working. On the cloud
backend `<SUCC>` usually lives under another workspace's prefix, so the fence
is a cross-prefix write of the same kind import's marker and the continues
pointer already make.

`coordinate-open.sh` drives it. Its preflight resolves the predecessor, checks
koto's version and the compatibility rule (Decision 2) against the
predecessor's current state, and then runs `koto init <SUCC> --continues
<PRED> --supersede --expect-state <state>` with the carry prefixes `record/`,
`legs/`, `taken_legs` and `leg_children`. On exit 2 `stale_state` it re-runs
the preflight once and retries; a second `stale_state` refuses
`predecessor-unstoppable`. After the fence it writes the successor's own
record changes: `record/meta.driver` (the successor's Claude session id), the
coordinator row, the told reset, pending rows, and one takeover entry whose id
is the successor's session name, written only if no entry with that id exists.
`record/meta.takeover_done` is written last. The carried set is the closed
list R7 asks the design to publish:

| Group | Key families | Why |
|---|---|---|
| Carried at the fence | `record/*` (sections, `record/meta`, `record/host`, `record/rotation`, `record/reasoning`, `record/entries/*`, `record/posted/*`), `legs/*`, `taken_legs`, `leg_children` | read by reconcile, the wait hub, the handover gate, deferral and cost checks; written incrementally |
| Rebuilt by the successor | `coord/*`, `reconcile/*`, `wait_target`, `report_topic`, `brief_input.json`, sealed checks in the log | written fresh on every visit to their state; seals hash the session name |
| Neither | `session/link-warning`, `koto/links/*` | the successor's own; lineage is the relation |

**Re-runs and the takeover's steps.** R6's criterion iterates these steps:
(a) preflight, writing nothing; (b) `koto init --supersede` steps 1 to 5;
(c) the successor's record writes, ending with `record/meta.takeover_done`;
(d) printing the result. A re-run recognises itself when the scope's newest
member is a session whose `record/meta.driver`, or whose fence actor, is the
caller's own Claude session (`CLAUDE_CODE_SESSION_ID`); with no Claude session
id to compare, a re-run can't recognise itself and refuses `taken-over`,
which is the safe side. Crashes resolve as follows:

| Interrupted | State left | Drivers | Re-run |
|---|---|---|---|
| in (a) | nothing written | predecessor | a fresh takeover |
| in (b) before the fence | nothing written | predecessor | a fresh takeover |
| in (b) after the fence, before create or carry | `<PRED>` fenced; `<SUCC>` absent or without the carry marker | none | `koto init --supersede` resumes at step 3 or 4; prints `outcome=continued` |
| in (c) | `<SUCC>` carried; some record writes missing | none | finishes (c); the takeover entry is written once; `outcome=continued` |
| in (d), or any re-run after `takeover_done` | complete | `<SUCC>` | attaches; `outcome=resumed`, no new entry |

The only no-driver window is between the fence and the end of (c), all inside
one command, or until that command is re-run after a crash. The opener prints
`session=<SUCC>`; the skill builds the arm-watch command from that validated
field and runs it before the first tick (Decision 3).

#### Alternatives Considered

**A separate `koto session supersede` verb run after `koto init
--continues`.** Keeps `init` unchanged. Rejected because the successor and its
relation then exist before the fence is known to hold, so a rival that loses,
or a fence the bucket refuses, leaves a session behind, and the PRD requires
every refusal to write nothing.

**Cancel the predecessor, with a `--continued-by` note on the cancel event.**
koto's cancel already refuses `koto next`, and a cancel is serialized like
any append. Rejected because cancel can't be undone or re-asserted, so the
crash between cancel and copy leaves a cancelled run and a successor without
its holdings and nothing to re-run against, and because cancel is the event
the old lineage walk reads, which keeps two meanings on one event.

**A shirabe-only fence: a `coord/superseded-by` key the coordinate scripts
check.** No koto change. Rejected because nothing makes `koto next` read it,
so the predecessor's ticks still advance the workflow (R5 fails), a write
from another workspace on the cloud backend is refused as cross-directory,
and two successors writing the key both succeed.

**Wait for the predecessor to stop: message it, then refuse until it isn't
live.** Rejected by the PRD's own decision: coordinators recycle while
running, and an open that refuses whenever the predecessor is live turns
every recycle into a hand stop and a retry. koto also has no liveness signal
to wait on.

**End the predecessor's Claude process.** Rejected: it works only on one host,
does nothing about a tick already committed between the kill and the open,
and leaves the koto session itself unfenced for anything else that writes it.

**Read through instead of copying: the successor reads entries and sections
from its predecessors via the relation.** No duplicated keys. Rejected
because every record reader would need chain-aware reads, a section is a
whole-key rewrite with no merge rule, and the chain grows by one member per
recycle, so a full listing costs one cloud listing per member and passes the
30-second cap after a few weeks of recycles.

**Copy key by key in shirabe, as today, but with the relation added.** No new
koto copy. Rejected for R22: 65 entries take about 130 koto calls, minutes on
a loaded host, all of it inside the no-driver window once the fence comes
first, and an unfenced copy races the predecessor's writes.

### Decision 2: The rule that decides a successor's template can keep driving the run

Resolved inline.

Today `coord-log.sh provenance` requires the session's `PLUGIN_ROOT` to equal
this plugin's path and its `template_hash` (SHA-256 of the compiled JSON) to
equal the shipped template's. The first refuses tsukumogami/shirabe#806 and
the second refuses tsukumogami/shirabe#1144. Under this design the successor
always opens its own session from its own template, so the question is no
longer whether a session can be resumed elsewhere, but whether the
predecessor's run, sitting in some state of the predecessor's template, can be
driven on by the successor's template. About a third of the last thirteen
changes to the template touched only directive text or names; the rest
changed states, transitions or what an exit code means, and one
(tsukumogami/shirabe#1139) changed a gate's meaning while keeping its command.

#### Chosen: a compat number the template declares, held honest by a CI fingerprint check

The template declares `COMPAT`, an integer, in its header, and the opener
records it with the shirabe version in `record/meta` when a run opens (so it
is carried). A successor continues the run when the predecessor's recorded
compat equals its own shipped template's, and refuses with
`reason=template-incompatible` otherwise, naming the template and both
versions (compat, compiled hash and shirabe version on each side). The plugin
path is never compared.

A CI check in shirabe computes a structural fingerprint of the compiled
template (state names, transitions and their conditions, evidence schemas,
variables, gate commands and the exit-code-to-route mapping) and fails a pull
request whose fingerprint changed while `COMPAT` didn't. The check runs the
base branch's copy of its script. For the meaning-only case
(tsukumogami/shirabe#1139: a gate script whose exit 1 now means something
else), it also hashes the scripts the template's gates invoke and fails a pull
request that changes one of them unless the same pull request either bumps
`COMPAT` or updates `COMPAT_REVIEWED`, a header field holding that hash, which
records that the author judged the change meaning-preserving. Gate scripts
change often, so requiring a bump for every edit would refuse most handovers;
requiring a recorded judgement forces the question without that cost. A
meaning change in a file no gate invokes is the residue review covers.
Directive and details text are outside the fingerprint, so a text-only
change continues without a bump.

The successor also checks, before supersede, that the predecessor's current
state name exists in its own template; a mismatch with equal compat is a
defect in the fingerprint and refuses the same way.

#### Alternatives Considered

**Structural diff at runtime, no declared number.** Continue when the two
compiled templates' fingerprints match. Rejected because it can't see a
meaning change, which R11 requires refusing, and because the successor would
need the predecessor's compiled template, which a successor on another host
may not have.

**Byte or hash equality, as today.** Rejected: it is what refuses
tsukumogami/shirabe#1144, and every handover across a text-only change would
refuse.

**Author-declared number with no CI check.** Rejected because a forgotten
bump continues a run across a real state change, which corrupts the run; the
fingerprint makes the common mistake impossible and leaves only the
meaning-only case to people.

### Decision 3: How legs the predecessor opened reach the successor, and how watches move

Resolved inline.

A leg's request names its requester once, and koto rings only the names in
the header. The successor must hear every leg any earlier member opened,
within 10 seconds of its result (R17), and the predecessor's watcher must
not outlive the takeover (R18). Requests live on one host and don't travel
with an import, so this decision is host-local by construction.

#### Chosen: rings follow supersede events, and supersede rings the predecessor once

When koto rings a principal (`ring_principals` in `src/engine/wake_signal.rs`
and the per-tick wake pass in `src/engine/wake.rs`), it first follows that
principal's `session_superseded` events forward to the newest member and
rings that member's wake file as well as the principal's. On the local
backend that is one read of the principal's log tail per superseded hop; a
principal never superseded costs one check. The stale-wake recovery that
looks up a requester's log by name follows the same chain. Nothing in the
request's header changes, so `koto request list --requested-by` still shows
the member that opened it.

Supersede rings the predecessor's own wake file once (Decision 1, step 5).
The predecessor's armed `koto request watch` exits with a wake; when the
predecessor's agent ticks in response, koto refuses with
`session_superseded`, and the coordinate template's directive for that
refusal tells the agent to stop and not re-arm. The successor's watch is armed
by the agent, because a harness watch has to be started by the agent that
wants its notification: `coordinate-open.sh` prints `session=<SUCC>`, and the
skill builds `koto request watch --session <SUCC>` from that validated field
and arms it in the same turn, before the first tick. This narrows R18's
wording: "the open" is the opener plus that arm step, because no script can
start a watch whose wake reaches the agent. R18's criterion is checked after
the arm step. A predecessor watcher on another host is
outside the ring's reach; the opener reports `watcher=unobserved` when the
predecessor's last event came from another host, `watcher=absent` when no
watch for the predecessor runs here, and `watcher=stopped` when one did and
has exited.

#### Alternatives Considered

**Re-point each open request with a `request.reassigned` event.** The header
stays the source of truth. Rejected because the takeover would have to find
and rewrite every open request of every earlier member, and a request opened
by a member two takeovers back would need the rewrite repeated at each
takeover; following the supersede chain at ring time needs nothing at
takeover beyond the fence.

**Follow the continues relation instead of the supersede event.** Rejected:
a session may have several continuers in koto's relation (the relation is
many-to-one by design), and a ring must reach exactly the session driving the
run, which only the exclusive supersede event names.

**No koto change: the successor also watches its predecessors' wake files.**
Rejected because `koto request watch` takes one session, the set of files
grows with every recycle, and the predecessor's watcher still has nothing that
ends it.

### Decision 4: The coordinator address, pending workers and reaching the newest member

Resolved inline.

The record's Run `coordinator` row is the address workers report to, and
`state-stored-set.sh --run coordinator` already clears every `told` row. The
handover gate (`state-handover.sh --check`) reports `not-told` for each
worker of a live holding with no `told` row. A re-brief re-renders the brief
but records nothing, and a stopped worker can't be messaged
(tsukumogami/shirabe#1245). A worker's brief names its address once. The
PRD's decision table classifies workers as told, not told, pending or
missing, and requires a pending worker to reach the newest member on its own
when it next starts.

#### Chosen: workers resolve the newest member when they report; pending is a Run row

Every brief already names `dispatcher_session`, the koto session of the run
member that dispatched it. A new script, `resolve-coordinator.sh
<dispatcher_session>`, follows `session_superseded` events forward from that
session to the newest member and prints that member's Run `coordinator` row,
which is a Claude session name the worker can message. The brief's Reporting
section tells the worker to run it before each report and to send the report
to what it prints; `render-result.sh` runs it too. A worker started again
after any number of takeovers therefore reports to the newest member, and its
brief file is never edited. The read is a koto read of another session, which
writes nothing.

The Run section gains a `pending <worker>` row beside `told <worker>`, written
by the handover step for each worker the PRD's table classes pending: a
worker whose Claude job has finished (`dc_job_finished`: the job's state file
reads done, stopped or failed and its pid is gone), or whose session is on
another host with no koto event in the last 10 minutes. `state-handover.sh
--check` accepts a pending worker and still reports `not-told` for a live
worker with no `told` row. When a report from a pending worker reaches the
successor, the next reconcile replaces `pending` with `told`. The re-brief
path records told through its existing evidence: the template's re-brief step
submits `sent: delivered|refused|worker_gone`, and `delivered` now runs
`state-stored-set.sh --told <worker>`, so neither `--rebrief` nor the agent
records it by hand; `refused` records nothing; `worker_gone` records pending
when the instance still exists.

#### Alternatives Considered

**Rewrite pending workers' brief files at takeover.** Rejected: nothing shows a
resumed worker re-reading its brief, so the rewrite doesn't reach the worker,
and the brief file lives in the dispatching instance's workspace, which a
successor in a fresh instance may not share.

**Inject the address into the worker's resume prompt through niwa.** Rejected
for this feature: it needs a niwa change, it only works for workers niwa
resumes, and a worker started some other way would still report to the old
address.

**Exempt stopped workers from the gate without recording them.** Rejected: the
record would no longer say who still needs the address, and the PRD's table
needs pending to be visible so it can turn told.

## Decision Outcome

**Chosen: 1 (`koto init --supersede`) + 2 (declared compat) + 3 (rings follow supersede) + 4 (workers resolve; pending row)**

### Summary

A takeover is one command, `coordinate-open.sh`, which now continues runs
instead of carrying them. Its preflight resolves the predecessor (the newest
member of the scope's one unfinished run, or a named session it checks is
that member), checks koto's version, and compares the predecessor's recorded
compat number with its own template's against the predecessor's current
state. Then it runs `koto init <SUCC> --continues <PRED> --supersede`, which
fences the predecessor before anything else is written, creates the
successor with its relation, copies the run's carried key families from the
fenced state, and rings the predecessor's wake file. The successor writes its
own driver id, coordinator row, told reset, pending rows and one takeover
entry, marks the takeover done, and the opener prints its `key=value` result,
including `session=`, from which the skill builds and arms the successor's
watch before the first tick. A rival that loses the fence, or a fence that
can't be taken, writes nothing; a re-run by the winner finishes whatever step
was interrupted and an attach after completion prints `resumed`.

koto changes in three pieces beyond the relation it already ships: the
supersede fence, refusal and carry on the local backend; the same on the
cloud backend, which needs koto's bucket walk for the relation; and ring
forwarding in the request store. The plan files each as a koto issue. The
opener's koto floor is the release with the local supersede piece; on a koto
without ring forwarding it still takes over and prints `leg_wake=unsupported`,
deciding by version, since the release that ships forwarding is known.

The lineage readers move to the relation. `coord-log.sh chain-start` walks
`koto/links/continues/*` back from the newest member, and at a member with no
relation follows its recycled-coordinator `dispatched-by` link; a member
with neither is the chain start. This needs only the relation. The cost sweep
resolves a removed worker's `requested_by` forward along supersede events to
the newest member instead of falling back to the slug's live run.
`coordinate-open.sh --import` becomes koto import followed by the same
takeover, with the imported copy as the predecessor; koto's import already
leaves the source refusing writes as `session_migrated`, so the source can't
drive the run either, and the provenance-by-path refusal of
tsukumogami/shirabe#806 goes away.

### Rationale

The fence and the carry belong together, and the fence comes first. Fencing
before creating anything is what makes every refusal write nothing; copying
from the fenced state is the only order that gives a consistent snapshot; and
doing both inside one koto command keeps the no-driver window to that command
at constant cost. The fence being an event in the predecessor's own log is
what lets koto refuse every kind of write, including an in-flight tick's last
append, without a check anywhere koto doesn't already serialize, and it is the
forward pointer Decisions 3 and 4 and the cost sweep follow. That shared
pointer is why the ring, the worker's address and the sweep need no
takeover-time rewriting. The cost is koto work beyond the relation, and a
fence that is final: a superseded session can't be revived, which is the
intended property.

## Solution Architecture

### Overview

```
successor agent
  coordinate-open.sh --scope ... [--predecessor P] [--import ...]
    (a) preflight: koto floor; scope -> P (newest unfinished member);
        P's current state s; compat(P) == compat(own) and s exists in own template
    (b) koto init S --continues P --supersede --expect-state s
          --carry record/ --carry legs/ --carry taken_legs --carry leg_children
          1 check   P's log: fenced? by whom? state still s?
          2 fence   P log += session_superseded{by:S, id, actor}  (per-append flock /
                    conditional push: first wins; nothing written on failure)
          3 create  S with header and continues relation
          4 carry   S ctx <= P ctx[carried prefixes]; koto/superseded-carry-complete
          5 ring    wakes/P once (P's watch exits)
    (c) S record: meta.driver, coordinator row, told reset, pending rows,
        takeover entry (id = S, written once), meta.takeover_done
    (d) print outcome=continued predecessor= session=S predecessor_stopped=
        watcher= leg_wake= template_drift=
  agent builds `koto request watch --session S` from session=, arms it, ticks
```

### Components

**koto `init --supersede` (new, koto).** The fence, the `session_superseded`
event with its actor, the refusal `session_superseded` naming the newest member
in every write path (`koto next`, context writes, decisions, overrides,
appends), the carry with its completion marker, the ring, `--expect-state`,
and the `self`, `cycle` and `stale_state` refusals. Local first; the cloud path
(conditional push to the predecessor's prefix) once koto's bucket walk for the
relation is in. koto validates every session name it reads from an event
before using it in a path.

**koto request store forwarding (koto).** `ring_principals`, the wake pass
and the stale-wake recovery follow `session_superseded` forward, with each
hop's session id checked and a visited set, and ring the newest member too.

**`coordinate-open.sh` (shirabe).** Replaces the carry-and-cancel path with the
takeover above; keeps plain open (`outcome=opened`) and attach to a completed
takeover (`outcome=resumed`). Result contract (R23):
`outcome=continued|opened|resumed|refused`; `continued` adds `predecessor=`,
`session=`, `predecessor_stopped=yes|no` (yes when the predecessor was live by
the PRD's definition at preflight), `watcher=stopped|absent|unobserved`,
`leg_wake=supported|unsupported` and, when the two sides differ,
`template_drift=`; `refused` adds `reason=` from `ambiguous-scope`,
`not-newest-member`, `taken-over`, `predecessor-unstoppable`,
`template-incompatible`, `koto-too-old`. It also reads the carry marker: a
re-run that finds a successor without it re-runs `koto init --supersede`
before step (c).

**Template refusal directive (shirabe).** The coordinate template gains a
directive for `session_superseded`: stop, report the newest member to whoever
launched the session, and don't re-arm the watch.

**Liveness probe (shirabe, `dispatch-common.sh`).** The PRD's definition:
not finished or cancelled in koto, and either a running Claude job on this
host (`dc_job_finished` false) or, when the job can't be seen from here, a
koto event in the last 10 minutes. Used for `predecessor_stopped` and the
pending classification.

**Compat check (shirabe).** `COMPAT` and `COMPAT_REVIEWED` in the template
header; `record/meta` gains `template_compat`, `template_hash`,
`shirabe_version` and `driver` at open; a CI script,
`check-template-compat.sh`, judged by the base branch's copy, compares the
fingerprint and the gate-script hash (scripts gates invoke and the libraries
they source) against the base branch.

**Lineage readers (shirabe).** `coord-log.sh chain-start` and
`unit-removed.sh`'s coordinator lookup, as above. Every script that writes the
record through `lib_write_guard` (`state-stored-set.sh`, `state-write-core.sh`
and its callers, `state-handover.sh --record`, `dispatch-worker.sh`'s record
writes) gets koto's `session_superseded` refusal and prints the newest member
it names; this list is the one R5's criterion iterates.

**Worker side (shirabe).** `resolve-coordinator.sh`, the brief template's
Reporting section and `render-result.sh`.

**Handover (shirabe).** `state-stored-set.sh` gains `--pending <worker>`;
`state-handover.sh --check` accepts pending; the template's re-brief evidence
`delivered` records told.

### Key Interfaces

- `koto init <SUCC> --continues <PRED> --supersede [--carry <prefix>]...
  [--continues-from <workspace>] [--expect-state <state>]` → exit 0 with
  `superseded=`, `carried=`, `forward=`; exit 2 with `superseded_by=<other>`,
  `stale_state`, `cycle` or `self`; exit 3 `fence_unavailable` (lock not taken
  in 10 seconds, or the conditional push refused or failed). Every non-zero
  exit before step 2 completes writes nothing.
- Refusal on any write to a superseded session: error kind
  `session_superseded`, naming the newest member and the fence's actor.
- `resolve-coordinator.sh <dispatcher_session>` → prints `coordinator=<claude
  session name>` and `member=<koto session>`; exit 1 when the chain can't be
  read or the member's `record/meta` names another run.
- `state-stored-set.sh --pending <worker>`; Run row `pending <worker>`.
- Template header `COMPAT: <int>`, `COMPAT_REVIEWED: <hash>`; `record/meta`
  fields `template_compat`, `template_hash`, `shirabe_version`, `driver`,
  `takeover_done`.

### Data Flow

A leg opened by member A (two takeovers back) resolves: koto promotes the
result, `ring_principals(A)` follows A's supersede event to B and B's to C,
and rings `wakes/A` and `wakes/C`. C's armed watch exits within one poll
(100 ms) of the ring, inside R17's 10 seconds. A worker dispatched by A
reports: `resolve-coordinator.sh A` follows the same events to C and prints
C's coordinator row. The cost sweep for that worker's removal resolves
`requested_by` A to C the same way.

### Seams, limits and edge cases

- A takeover of a predecessor that is itself finished or cancelled (a crash)
  supersedes it anyway; `predecessor_stopped=no`.
- A fence that can't be taken (bucket refusal, lock held) exits 3:
  `predecessor-unstoppable`, nothing written, the predecessor still drives.
- A predecessor's agent that keeps trying after the fence gets
  `session_superseded` on every call and follows the refusal directive.
- An action's side effect outside koto whose record write was refused shows
  up in the successor's first reconcile as an instance with no holding.
- Requests don't cross hosts; a successor on another host after an import
  reads legs through reconcile (`koto request get`) but isn't woken.
- Chain walks stop at 1024 hops, about six months of recycles at the current
  rate; past that a ring reaches the principal only and the worker's resolver
  falls back to its brief's address.
- Pre-feature briefs don't run `resolve-coordinator.sh`; those workers fall
  back to the brief's existing "list the sessions again if a message bounces"
  rule until they finish.

## Implementation Approach

### Phase 1: What needs no koto change (buildable now)

- The compat number, `COMPAT_REVIEWED`, `record/meta` fields and the CI
  fingerprint check.
- Told and pending: `--pending`, the gate change, re-brief evidence recording
  told (tsukumogami/shirabe#1245), the liveness probe.

### Phase 2: Readers of the relation (needs only koto's relation release)

- `chain-start` over the relation, with the legacy `dispatched-by` fallback.

### Phase 3: koto's supersede and ring forwarding

- `koto init --supersede` on the local backend: fence, refusal, carry, marker,
  ring, refusals.
- The same on the cloud backend, after koto's bucket walk for the relation.
- Ring forwarding in the request store.

### Phase 4: The takeover in shirabe

- `coordinate-open.sh` takeover, result contract, rival and re-run handling,
  driver id, coordinator row and told reset, refusal directive.
- The cost sweep's forward resolution.
- Worker side: `resolve-coordinator.sh`, brief template, `render-result.sh`.

### Phase 5: Import

- `coordinate-open.sh --import` as import plus takeover, once koto's import
  keeps its source as a read-only predecessor.

## Security Considerations

The takeover runs inside koto's existing trust boundary. Whoever can write a
session's log (a process of the same user on the local backend, a holder of
the bucket credential on the cloud backend) can already cancel or alter any
session in it. On a host or bucket where every writer holds every prefix, the
fence doesn't widen that boundary, but it makes an irreversible action one
command long, so the design treats mistakes and confused agents as the main
threat and attributes every fence. Where a bucket grants writes per prefix, a
holder of one prefix that can write another's state can now redirect that
run's workers, legs and cost sweep, which a cancel never did; that deployment
shape is unsupported, and the fence refuses rather than half-writes when the
bucket denies it.

**Who may fence.** `koto init --supersede` fences a predecessor the successor
names in its own continues relation. The successor writes that relation
itself and the relation grants no authority, so this proves intent, not
permission: any session that can name another can fence it, and a wrong
fence stops the right coordinator and redirects its workers and legs. This is
accepted residual risk, escalated in the plan's report. Three things reduce
the chance of a wrong fence. The opener passes the predecessor's workflow
state its preflight observed (`--expect-state`), and koto refuses a fence
decided on stale facts; a state, unlike a log sequence number, doesn't move
on every tick, so a live predecessor doesn't make the check flap. The opener
re-checks the scope and run identity from `record/meta` before fencing. And
the `session_superseded` event records the actor (Claude session, host, user,
time), which the predecessor's refusal echoes. A fenced session can't be
revived; recovery is another takeover of the newest member. That is why the
carry is all-or-nothing: koto writes the `koto/superseded-carry-complete`
marker into the successor after the batch, and the opener, which reads it on
every re-run, re-runs the carry before the successor's first tick when it is
missing.

**Cloud backend.** The fence is a write into the predecessor's prefix with the
successor host's credential, so that host can write both prefixes. The
conditional push is the only cross-prefix write; if the bucket refuses it the
verb exits 3 with nothing written and the opener reports
`predecessor-unstoppable`. The verb refuses on a backend that can't do a
conditional write rather than falling back to an unconditional one. Carrying a
run into another prefix copies its full record there; nothing checks that the
destination is as private as the source, so an operator taking a run into
another workspace owns that choice. Retention releases the whole lineage
together. After an import, the source refuses writes as `session_migrated`
(koto's import keeps it as a read-only predecessor), so the original can't
keep driving while the copy is taken over; carried values from the import are
validated like any other carried key.

**Chains.** Every walker that follows `session_superseded` (ring forwarding,
the stale-wake lookup, `resolve-coordinator.sh`, the cost sweep, the refusal
message) checks that each hop's session id matches the event's
`by_session_id`, keeps a visited set and stops after 1024 hops (about six
months of recycles; koto validates each name before building a path from it). koto refuses a
supersede whose successor is the predecessor, is already in the predecessor's
forward chain, or has the predecessor in its own relation ancestry, so a cycle
built with `koto session link --continues` can't make a ring loop. On a broken
chain a ring reaches the principal and the last good member, and the worker's
resolver exits 1, which the brief treats as "report to the address in this
brief". A worker also checks that the resolved member's `record/meta` names
the same run before trusting its coordinator row.

**Inputs.** Session names, worker names, the event's `by` field and carried
keys are data. Session and worker names must match koto's name pattern before
use; printed `key=value` values carry no control characters; the skill builds
the arm-watch command from the validated `session=` field rather than running
a printed string; `--from` and `--continues-from` come only from the
invoker, never from a carried key; carried key names are validated as
`koto context add` validates them.

**Template compatibility.** A matching `COMPAT` lets a successor at another
plugin path, checkout or version drive a run. The plugin's scripts already
run with the user's privileges, so this adds no privilege, but it removes the
old path-equality guard, so the opener records hash, compat and shirabe
version on both sides, prints `template_drift=` when they differ, and refuses
a predecessor with no recorded compat. The CI fingerprint check runs the base
branch's copy of the script against both templates on `pull_request`, without
secrets, so a pull request can't change the judge that evaluates it.

**Output.** Result lines and refusals print session names and reason codes,
not workspace paths or bucket keys. Session names can embed private slugs, so
takeover output stays out of public pull requests, commits and comments, and
test fixtures use synthetic names.

## Consequences

### Positive

- One command hands a run over, from any instance, checkout or compatible
  version, with no hand rebind, row edit or watcher kill.
- At most one driver is enforced by koto at the only point every write
  passes, including a tick already in flight.
- Legs, workers and the cost sweep reach the newest member through one
  forward pointer, with nothing rewritten at takeover.
- Template changes that only touch text stop forcing a carry.

### Negative

- New koto work beyond the relation koto already ships: the takeover can't
  land until a koto release carries `init --supersede` on the local backend,
  can't run on the cloud backend until the cloud fence ships, and doesn't
  wake on old legs until ring forwarding ships.
- The carry duplicates the run's keys into every member, so storage grows
  with the number of takeovers until retention releases the lineage.
- A meaning-only change in a file no gate invokes still relies on review.
- Anyone who can name a session can fence it; the fence is attributed, not
  authorized.
- A superseded session can't be revived; a takeover started by mistake is
  undone only by another takeover.

### Mitigations

- Phases 1 and 2 land before koto's supersede work, and the opener prints
  `leg_wake=unsupported` on a koto without ring forwarding rather than
  failing.
- Retention releases a whole lineage together once its newest member's
  retention passes, so duplicate keys go with it.
- The template header comment and the review checklist name the meaning-only
  case, and the refusal names both versions so an operator can see why.
