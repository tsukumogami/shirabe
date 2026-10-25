---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-coordinate-successor-continues.md
decision_provenance: inline-resolved
problem: |
  A /coordinate successor can't continue the run it takes over. The opener
  finds the run by name prefix, opens a second run, copies record/ and legs/
  key by key, and cancels the first; nothing fences a predecessor that is
  still ticking, legs keep ringing the cancelled run, lineage is walked by
  name and cancel event, and imports fail on plugin path or template bytes.
  koto now records a continues relation, but nothing builds a takeover on it.
decision: |
  The successor opens its own session with --continues naming the run's
  newest member, then runs a new koto verb, koto session supersede, that in
  one serialized step fences the predecessor (an event in its own log, first
  writer wins), copies the run's named key families into the successor from
  the fenced snapshot, and rings the predecessor's wake file once. koto's
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

This is the core of the feature. The takeover has to do four things in an
order that never leaves two drivers and never leaves the run claimed by
nobody after a crash: open the successor with the relation, stop the
predecessor from driving, carry what the run holds into the successor, and
make the claim exclusive. The PRD settled that a live predecessor is
stopped rather than waited for, and that the stop must catch an in-flight
tick. This decision settles where the stop lives, how the claim is made
exclusive, and whether the run's holdings are copied or read through.

The decision was resolved inline, without a separate decision run, on the
dispatching coordinator's direction for this run's spend; it is the one
critical-tier question in the design.

#### Chosen: a koto supersede verb that fences, copies and rings in one serialized step

koto gains `koto session supersede <PRED> --by <SUCC> [--carry <prefix>]...
[--from <workspace>]`. `<SUCC>` must already hold a continues relation naming
`<PRED>` (koto refuses `no_relation` otherwise). Under `<PRED>`'s existing write
serialization (the log's exclusive `flock` on the local backend; on the cloud
backend, a pull of `<PRED>`'s state and a push conditional on that copy, as
every cloud write has done since tsukumogami/koto#480), the verb:

1. Reads `<PRED>`'s log. If it already carries a `session_superseded` event
   naming `<SUCC>`, the verb skips to step 3 (a re-run). If it names another
   session, it exits 2 with `superseded_by=<other>` and writes nothing. If
   `<PRED>` is finished or cancelled, it supersedes anyway: a crashed or
   cancelled predecessor still needs the fence so its forwarding works.
2. Appends `session_superseded {by: <SUCC>, by_session_id, at}` to `<PRED>`'s
   log. This is the claim: the append is serialized, so of two successors the
   first append wins and the second reads it at step 1.
3. Copies every context key under each `--carry` prefix from `<PRED>`'s
   fenced state into `<SUCC>` in one read of `<PRED>` and one write batch to
   `<SUCC>` (one pull and one push on the cloud backend). Keys `<SUCC>`
   already holds with the same value are skipped, so a re-run is a no-op.
4. Rings `<PRED>`'s wake file once (see Decision 3) and prints
   `superseded=<PRED>`, `carried=<n>`, `forward=<SUCC>`.

From then on koto refuses every attempt to drive `<PRED>`: `koto next`, every
context write and every log append check for a `session_superseded` event and
exit with `session_superseded`, naming the newest member reached by following
supersede events forward (`<SUCC>`, or the session that superseded it). A tick
that was in flight when the fence landed reaches that check at its final
append and is refused; a context write by a coordinate script inside that
tick is refused the same way. Reads of `<PRED>` keep working. On the cloud
backend `<SUCC>` usually lives under another workspace's prefix; the fence is
a cross-prefix write of the same kind import's marker and the continues
pointer already make, and the verb exits 3 with nothing written when the
bucket refuses it. That exit is what the opener reports as
`predecessor-unstoppable`.

`coordinate-open.sh` drives it. After its preflight (Decision 2's
compatibility check, the koto floor, scope resolution) it opens the successor
with `koto init <SUCC> --continues <PRED> [--continues-from <ws>]`, runs
`koto session supersede <PRED> --by <SUCC>` with the carry prefixes `record/`,
`legs/`, `taken_legs` and `leg_children`, and only then writes the
successor's own record changes (the coordinator row, the takeover entry, the
told reset). The carried set is the closed list R7 asks the design to
publish:

| Group | Key families | Why |
|---|---|---|
| Carried at the fence | `record/*` (sections, `record/meta`, `record/host`, `record/rotation`, `record/reasoning`, `record/entries/*`, `record/posted/*`), `legs/*`, `taken_legs`, `leg_children` | read by reconcile, the wait hub, the handover gate, deferral and cost checks; written incrementally |
| Rebuilt by the successor | `coord/*`, `reconcile/*`, `wait_target`, `report_topic`, `brief_input.json`, sealed checks in the log | written fresh on every visit to their state; seals hash the session name |
| Neither | `session/link-warning`, `koto/links/*` | the successor's own; lineage is the relation |

The takeover's steps, which R6's criterion iterates, are: (a) preflight,
writing nothing; (b) `koto init --continues`; (c) supersede; (d) the
successor's record writes; (e) printing the arm-watch step. A crash after (b)
leaves a successor session with the relation and an unfenced predecessor
still driving: one driver, and a re-run attaches to the successor and goes
on. A crash after (c) leaves the predecessor fenced and the successor holding
the run's keys but not yet ticked: no driver until the re-run, which skips
(b) and (c) and finishes (d). A rival successor that loses at (c) cancels its
own just-opened session with `koto cancel --cleanup` and prints
`reason=taken-over`; that session held no run keys and was never ticked.

#### Alternatives Considered

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
request whose fingerprint changed while `COMPAT` didn't. A change that keeps
the fingerprint but changes meaning, such as a gate script whose exit 1 now
means something else, is caught by the template's header comment asking the
author to bump `COMPAT`, and by review; that residue is a stated limitation.
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

Supersede rings the predecessor's own wake file once (Decision 1, step 4).
The predecessor's armed `koto request watch` exits with a wake; when the
predecessor's agent ticks in response, koto refuses with
`session_superseded`, and the coordinate template's directive for that
refusal tells the agent to stop and not re-arm. The successor's watch is armed
by the agent, because a harness watch has to be started by the agent that
wants its notification: `coordinate-open.sh` prints the exact `koto request
watch --session <SUCC>` command as `arm_watch=` and the skill runs it in the
same turn, before the first tick. R18 is read accordingly: "the open" is the
opener plus the arm step it prints. A predecessor watcher on another host is
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

**Chosen: 1 (supersede verb) + 2 (declared compat) + 3 (rings follow supersede) + 4 (workers resolve; pending row)**

### Summary

A takeover is one command, `coordinate-open.sh`, which now continues runs
instead of carrying them. Its preflight resolves the predecessor (the newest
member of the scope's one unfinished run, or a named session it checks is
that member), checks koto's version, and compares the predecessor's recorded
compat number with its own template's. Then it opens the successor with
`koto init --continues`, and calls `koto session supersede`, which in one
serialized step fences the predecessor, copies the run's carried key
families into the successor from the fenced state, and rings the
predecessor's wake file. The successor writes its own coordinator row, resets
the told set, records pending workers, appends one takeover entry, and the
opener prints its `key=value` result with an `arm_watch=` line the skill runs
before the first tick. A rival that loses the fence cancels its own empty
session and refuses `taken-over`; a re-run by the winner finishes whatever
step was interrupted.

koto changes in two places beyond the relation it already ships. The
supersede verb adds the fence, the carry and the ring, local and cloud, and
every write path refuses a superseded session by naming the newest member.
The request store's ring follows supersede events to the newest member, so a
leg opened by any earlier member wakes the session driving the run. Both are
filed as koto issues by the plan.

The lineage readers move to the relation. `coord-log.sh chain-start` walks
`koto/links/continues/*` back from the newest member, and at a member with no
relation follows its recycled-coordinator `dispatched-by` link; a member
with neither is the chain start. The cost sweep resolves a removed worker's
`requested_by` forward along supersede events to the newest member instead
of falling back to the slug's live run. `coordinate-open.sh --import` becomes
koto import followed by the same takeover, with the imported copy as the
predecessor, which also retires the provenance-by-path refusal of
tsukumogami/shirabe#806.

### Rationale

The fence and the carry belong together. Fencing first and copying from the
fenced state is the only order that gives a consistent snapshot, and doing
both inside one koto verb is what keeps the no-driver window to one
command at constant cost. The fence being an event in the predecessor's own
log is what lets koto refuse every kind of write, including an in-flight
tick, without adding a check anywhere koto doesn't already serialize, and it
is also the forward pointer that Decisions 3 and 4 and the cost sweep follow.
That shared pointer is why the ring, the worker's address and the sweep need
no takeover-time rewriting. The cost is a second koto dependency beyond the
relation, and a fence that is final: a superseded session can't be revived,
which is the intended property.

## Solution Architecture

### Overview

```
successor agent
  coordinate-open.sh --scope ... [--predecessor P] [--import ...]
    preflight: koto floor, scope -> P (newest unfinished member), compat(P) == compat(own)
    koto init S --continues P [--continues-from ws]           (relation, F12)
    koto session supersede P --by S --carry record/ --carry legs/ --carry taken_legs --carry leg_children
      P log += session_superseded{by:S}   (flock / conditional push: first wins)
      S ctx  <= P ctx[carried prefixes]   (one read, one write batch)
      ring wakes/P                        (P's watch exits)
    S record: coordinator row = S's Claude session, told reset, pending rows, takeover entry
    print outcome=continued ... arm_watch=koto request watch --session S ...
  agent runs arm_watch, then first tick
```

### Components

**koto `session supersede` (new, koto).** Verb, event type
`session_superseded`, the refusal `session_superseded` naming the newest
member in every write path (`koto next`, context writes, decisions,
overrides, appends), and the carry. Local: under the log's `flock`. Cloud:
pull, append, conditional push to the predecessor's prefix, then one push
for the successor; exit 3 with nothing written if either fails before the
fence lands, and an idempotent re-run if it fails after.

**koto request store forwarding (koto).** `ring_principals`, the wake pass
and the stale-wake recovery follow `session_superseded` forward and ring the
newest member too.

**`coordinate-open.sh` (shirabe).** Replaces the carry-and-cancel path with
the takeover above; keeps plain open (`outcome=opened`) and resume of the
session this Claude session already drives (`outcome=resumed`). Result
contract (R23): `outcome=continued|opened|resumed|refused`; `continued` adds
`predecessor=`, `predecessor_stopped=yes|no` (yes when the predecessor was
live by the PRD's definition at preflight), `watcher=stopped|absent|unobserved`,
`leg_wake=supported|unsupported` and `arm_watch=`; `refused` adds `reason=`
from `ambiguous-scope`, `not-newest-member`, `taken-over`,
`predecessor-unstoppable`, `template-incompatible`, `koto-too-old`.

**Liveness probe (shirabe, `dispatch-common.sh`).** The PRD's definition:
not finished or cancelled in koto, and either a running Claude job on this
host (`dc_job_finished` false) or, when the job can't be seen from here, a
koto event in the last 10 minutes. Used for `predecessor_stopped` and the
pending classification.

**Compat check (shirabe).** `COMPAT` in the template header; `record/meta`
gains `template_compat`, `template_hash` and `shirabe_version` at open; a CI
script, `check-template-compat.sh`, compares the fingerprint against the base
branch.

**Lineage readers (shirabe).** `coord-log.sh chain-start` and
`unit-removed.sh`'s coordinator lookup, as above. The record-writing scripts
that refuse a superseded predecessor are every script that calls
`lib_write_guard` (`state-stored-set.sh`, `state-write-core.sh` and its
callers, `state-handover.sh --record`, `dispatch-worker.sh`'s record writes);
they get koto's `session_superseded` refusal and print the newest member it
names.

**Worker side (shirabe).** `resolve-coordinator.sh`, the brief template's
Reporting section and `render-result.sh`.

**Handover (shirabe).** `state-stored-set.sh` gains `--pending <worker>`;
`state-handover.sh --check` accepts pending; the template's re-brief evidence
`delivered` records told.

### Key Interfaces

- `koto session supersede <PRED> --by <SUCC> [--carry <prefix>]...
  [--from <workspace>]` → exit 0 with `superseded=`, `carried=`, `forward=`;
  exit 2 `superseded_by=<other>` or `no_relation`; exit 3 bucket failure,
  nothing written before the fence.
- Refusal on any write to a superseded session: exit code and error kind
  `session_superseded`, message naming the newest member.
- `resolve-coordinator.sh <dispatcher_session>` → prints `coordinator=<claude
  session name>` and `member=<koto session>`; exit 1 when the chain can't be
  read.
- `state-stored-set.sh --pending <worker>`; Run row `pending <worker>`.
- Template header `COMPAT: <int>`; `record/meta` fields `template_compat`,
  `template_hash`, `shirabe_version`.

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
- Cloud fence from a successor without write access to the predecessor's
  prefix exits 3: `predecessor-unstoppable`, nothing written, the
  predecessor still drives.
- A predecessor's agent that keeps trying after the fence gets
  `session_superseded` on every call; the template's refusal directive says
  to stop, report the newest member to whoever launched it, and not re-arm.
- Requests don't cross hosts; a successor on another host after an
  import reads legs through reconcile (`koto request get`) but isn't woken.
- Pre-feature briefs don't run `resolve-coordinator.sh`; those workers fall
  back to the brief's existing "list the sessions again if a message bounces"
  rule until they finish.

## Implementation Approach

### Phase 1: What needs no koto change (buildable now)

- The compat number, `record/meta` fields and the CI fingerprint check.
- Told and pending: `--pending`, the gate change, re-brief evidence recording
  told (tsukumogami/shirabe#1245), the liveness probe.

### Phase 2: koto's supersede verb and ring forwarding

- `koto session supersede` with the fence, refusal, carry and ring, local
  backend first, then the cloud path once koto's bucket walk for the relation
  is in.
- Ring forwarding in the request store.

### Phase 3: The takeover in shirabe

- `coordinate-open.sh` takeover, result contract, rival and re-run handling,
  coordinator row and told reset, arm-watch step, refusal directive in the
  template.
- Lineage readers: `chain-start`, the cost sweep, legacy `dispatched-by`.
- Worker side: `resolve-coordinator.sh`, brief template, `render-result.sh`.

### Phase 4: Import

- `coordinate-open.sh --import` as import plus takeover, once koto's import
  keeps its source as a read-only predecessor.

## Security Considerations

To be completed in the security phase.

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

- Two new koto capabilities (the supersede verb and ring forwarding) beyond
  the relation koto already ships, so the takeover can't land until a koto
  release carries both.
- The carry duplicates the run's keys into every member, so storage grows
  with the number of takeovers until retention releases the lineage.
- A meaning-only gate change still relies on the author bumping `COMPAT`.
- A superseded session can't be revived; a takeover started by mistake is
  undone only by another takeover.

### Mitigations

- Phase 1 lands before koto's work, and the opener prints
  `leg_wake=unsupported` on a koto without ring forwarding rather than
  failing.
- Retention releases a whole lineage together once its newest member's
  retention passes, so duplicate keys go with it.
- The template header comment and the review checklist name the meaning-only
  case, and the refusal names both versions so an operator can see why.
