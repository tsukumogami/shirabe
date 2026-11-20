---
schema: design/v1
status: Proposed
problem: |
  A `/coordinate` successor runs `handover-classify.sh` at `reconcile`, and no
  launch can happen until it's done, because `pick_facts` is reachable only
  after the handover gate passes. Over a record that carries holdings whose
  workers are gone, the classify is slow: it makes one full read-modify-write
  of the record per gone worker, one after another, and every succession
  repeats all of them, because a new coordinator address clears the
  `missing` rows along with the `told` ones. On a coordinator scope whose
  record carries 20 such holdings, each successor's classify ran 35 to 41
  minutes, and the run launched nothing in that time.
decision: |
  A coordinator address change keeps the `missing` rows of holdings that
  still exist, while it still clears `told` (R14). Each classify re-checks
  every kept row against one niwa listing, and drops the row of any worker
  the listing finds again, so the row always says what this successor can
  see. Rows are kept only while the record stays on the host that wrote
  them. `state-stored-set.sh` takes several workers per mode and writes once,
  and the classify collects its results and writes once per mode, taking
  one niwa listing per pass instead of one per worker. `pending` rows carry
  too, in a second step, each one re-probed for liveness on every classify.
  The template's state order stays: a classify holds only launches that
  write this run's record. A holding whose worker is gone ends through the
  removed-outside-the-run retire route PR #1968 added, once a release
  carries it.
rationale: |
  The cost is in the per-worker record writes, not in niwa or the 30 second
  wait, so the fix has to remove writes: carrying the rows removes them on
  every succession after the first, and batching removes them on the
  classify that writes the rows. A missing row's fact doesn't depend on the
  coordinator address, so only `told` needs clearing; one listing per
  classify keeps the PRD's "what the successor can observe" reading for the
  cost of one local call. Moving the classify off the launch path would be a
  template structure change, which the continuation rule refuses, and would
  add compare-and-swap contention on record writes, while the two changes
  above shrink the hold from about 40 minutes to about a minute on a
  succession whose carried workers are all gone. Retiring on a timer was
  rejected because shirabe retires on evidence.
upstream: docs/prds/PRD-coordinate-successor-continues.md
decision_provenance: inline-resolved
---

# DESIGN: A successor's handover classify, and the launches it holds

## Status

Proposed

## Context and Problem Statement

A `/coordinate` successor takes over a run whose record already holds
holdings. At `reconcile` it runs `handover-classify.sh`, which sorts every
live holding's worker by what the successor can observe (PRD R15): live
workers get a line naming the new address and turn `told`; a worker whose
session is gone while its instance stays is recorded `pending`; a worker
niwa's listing names no instance for, twice, 30 seconds apart, is recorded
`missing`. The handover gate, `state-handover.sh --check`, then passes on
pending and missing workers and holds on any live worker with no `told` row
(`state-handover.sh:335`). The design this one follows,
`DESIGN-coordinate-successor-continues.md` (Decision 4), added the pending
row; PR #1819 added the missing row on the same model.

Two things make the classify slow on a successor, and a third makes the wait
visible.

**Every succession re-classifies the same gone workers.** Setting the
coordinator address applies one jq filter, `LIB_COORD_ROW_JQ`
(`skills/coordinate/scripts/state-common.sh:177-182`), which drops every
`told`, `pending` and `missing` row. Three paths apply it: `state-stored-set.sh
--run coordinator` (`state-stored-set.sh:1053-1055`), which the opener's
`finish_takeover` writes on every `--continues` takeover
(`coordinate-open.sh:871-884`), and the carry's in-copy row through
`lib_carrier_row` (`state-common.sh:208-215`, called from
`state-open.sh:294` and `state-write-core.sh:579`). Each successor has a new
session name, so each one clears. PRD R14 asks only that the told set be
empty at takeover. `pending` was cleared because the upstream design wanted
the successor to observe pending workers itself; `missing` copied pending's
clear when PR #1819 added it, with no reason of its own. A missing row says
"niwa on this host listed no instance for W" (`state-stored-set.sh:1115`),
which doesn't depend on which address is current. Issue #1865 reports the
dropped missing rows, and #1696 reports the same for pending rows.

**Each row the classify writes is a full record write.** The classify writes
through `set_row` (`handover-classify.sh:82-94`), one `state-stored-set.sh`
call per worker, after it has looked each worker up with its own
`niwa list --json` (`dc_find_session`, `dispatch-common.sh:440-458`), in two
passes around one 30 second wait (`handover-classify.sh:139-157`).

**Launches wait for it by state order.** No pick or dispatch step reads the
`told`, `pending` or `missing` rows. `pick-facts.sh` covers a unit by any
holding that names it, `deferral-check.sh` reads holdings, pauses, deferrals
and owed decisions, and `dispatch-worker.sh` reads only the Run
`coordinator` row (`dispatch-worker.sh:368`) for the brief's `reports_to`.
The only reader of the classified rows is `state-handover.sh --check`, the
`reconcile_handover` gate (`koto-templates/coordinate.md:380-383`). Launches
wait because `reconcile`'s only way to `pick_facts` needs that gate to exit 0
(`coordinate.md:396-401`). The hold is the template's state order, not a
data dependency.

### Where a classify's time goes

The figures below are marked by where they come from. "Read from code"
counts calls by reading the scripts on main; nothing was run to get them.
"Observed" comes from runs.

Read from code, one `state-stored-set.sh --missing W` write, roadmap scope,
nothing absent:

- about 41 koto reads, most of them in two whole-record reads: one at
  `state-stored-set.sh:656` (a write reads the whole record it writes back,
  `:648-649`) and one in the write core's compare at
  `state-write-core.sh:129`. Each whole-record read is 11 koto calls, nine
  of them in parallel. The rest are `coord-log.sh` subcommands (ten of them
  per write, each a `koto session dir` and some jq over the run's log) and
  three looks at `record/meta`.
- 4 koto writes: `record/meta` pending, `record/run`, `record/meta` final
  and the entry.
- 2 GitHub REST GETs, both the host's visibility: one in the write core
  (`state-write-core.sh:791`) and one in `state-entry.sh`. On a public host,
  one more per distinct repository the record names (`state-write-core.sh:819`).
- roughly 150 to 180 jq processes, most of them over the full record.

Some parts grow with history: `coord-log.sh live-session` reads one koto
status per earlier run of the scope on the host, the entry write lists every
`record/entries/` key (`state-entry.sh:484`), and the driver check scans the
host's Claude job directory. On koto's cloud backend each koto call is a
bucket round trip of 0.3 to 1 second (`state-read.sh:71-73`), so koto calls
are the unit that costs.

Read from code, a whole classify on a successor whose record carries 20
holdings whose workers are gone:

| Step | koto reads | koto writes | GitHub GETs | niwa listings | Other |
|---|---|---|---|---|---|
| `--list` (`handover-classify.sh:96`) | about 7 | 0 | 0 | 0 | |
| told pass (`:103-112`) | 0 | 0 | 0 | 0 | no rows survive the clear |
| `state-handover.sh` (`:114`) | about 16, plus one per leg holding | 0 | 0 | 0 | |
| first pass (`:140-147`) | 0 | 0 | 0 | 20 | |
| wait (`:149`) | | | | | 30 seconds, once |
| second pass (`:150-156`) | 0 | 0 | 0 | 20 | |
| 20 `--missing` writes | about 820 | 80 | 40 | 0 | about 3,000 jq |

The writes are about 95 percent of the koto calls and all of the GitHub
calls. A `niwa list --json` call reads local files only (no network, no
subprocess), so 40 of them are small next to the writes, and so is the
single wait. The told pass does nothing on a successor, because the clear
left no rows for it to read.

Observed: on a coordinator scope whose record carries 20 holdings whose
workers are gone, each successor's classify ran 35 to 41 minutes, about 1.5
to 2.2 minutes per holding, spread evenly across the holdings. That fits the
model's per-write cost. Issue #1696 measured the same shape on another
record: 30 writes at 4 to 5 minutes each on a cloud-synced session, about
two hours.

> **Observed per-phase split: not yet measured.** A sampled split of one
> classify's wall time by step (listing, wait, each write) can go here. Until
> it does, the per-step figures above are read from code, and only the
> totals are observed.

### Scope

In scope: the coordinator-row filter and its three callers, the classify's
write and listing pattern, `state-stored-set.sh`'s write modes for told,
pending and missing, the guidance an operator follows about launches during
a classify, and the route that ends a holding whose worker is gone. Out of
scope: the cost of a single record write itself (the two whole-record reads,
the visibility GETs, the history scans), the template's state graph, and the
succession command (`DESIGN-coordinate-succession-command.md`), which calls
the classify and gains from it unchanged.

## Decision Drivers

1. **R14 holds.** The told set is empty at takeover. No change may carry a
   `told` row across an address change.
2. **R15 holds under its strict reading.** Each live holding's worker is
   classified "by what the successor can observe". A row the successor
   keeps must be one this successor has checked, not only one a predecessor
   wrote.
3. **No carried worker silently loses its coordinator address.** Every one
   is told, recorded pending or missing, or holds the gate. A pending or
   missing worker that comes back finds the newest member itself through
   `resolve-coordinator.sh` (R16), and its first report turns it told
   (`handover-classify.sh:101-112`).
4. **The template's structure stays.** A change to a state, a transition, an
   evidence field or what a gate's exit means is incompatible under R11, and
   a successor on the new template couldn't continue a predecessor on the
   old one. Script and details-text changes are compatible.
5. **Cost must actually move.** The writes are the cost; a change that leaves
   one record write per worker per succession doesn't fix the problem.
6. **Shirabe retires on evidence.** A holding ends because something
   confirmed its worker is gone (the teardown check), not because time
   passed.
7. **Don't widen the existing launch constraint.** Operators already work to
   "a classify doesn't hold a launch that doesn't read the classified rows".
   Any rule this design states may narrow that or keep it, never widen it.

## Considered Options

### Decision 1: What a coordinator address change does to `missing` rows

Resolved inline.

The address change exists to reset who has heard the address. A missing row
records something else: that niwa on this host had no instance for the
worker. Clearing it forces every successor to pay one record write per gone
worker to learn the same fact again. The question is whether to keep the
row, and if so, how the successor stays honest about it.

Key assumptions:

- An instance niwa no longer lists stays gone. A worker that does run again
  does so in a new instance or under another topic, and reaches the newest
  member through R16.
- A record moves to another host only through `--import` or a `--continues`
  takeover whose predecessor last wrote from another machine, and both are
  rare next to same-host successions.

#### Chosen: keep missing rows for existing holdings, re-check them with one listing per classify, on the same host only

`LIB_COORD_ROW_JQ` keeps a `missing` row when its worker still names a
holding in the record and the caller says the record is staying on the host
that wrote it. It still drops every `told` row and, until Decision 2 lands,
every `pending` row. A missing row whose holding is gone is dropped, so the
filter keeps the clean-up the clear used to do by accident: Run rows aren't
tied to holdings, and `state-holding.sh --retire` doesn't touch them.

Each classify then takes one niwa listing before it reads the worker set and
looks up every worker that has a missing row in it. A worker the listing
finds again loses its missing row (one write for all of them, in the rare
case there are any) and is classified with the rest. A worker the listing
still doesn't name keeps its row, with no write. So every missing row the
gate reads has been checked by this successor's own listing, which is what
R15's table asks for, and the check costs one local call rather than one
write per worker.

The host guard keeps the row's "on this host" claim true. A same-host carry
and a `--continues` takeover whose predecessor's last writer is this machine
(the opener already reads this as `ELSEWHERE`, `coordinate-open.sh:792-798`)
keep the rows; an `--import`, or a takeover from another machine, drops them
and pays the full classify once on the new host. The re-check alone would
mostly cover a host change, since the new host's listing decides, but a row
whose text names another host's listing would sit in the record until then.

#### Alternatives Considered

**Keep clearing missing rows, and rely on batching (Decision 3) alone.**
Every succession would still pay the listing, the 30 second wait and one
batched write for all its gone workers: about three minutes instead of 35
to 41. That's a real improvement, and Decision 3 is chosen for the first
classify anyway. Rejected as the whole answer because it keeps a write per
succession for a fact nothing changed, and the record still gains an entry
per succession restating it.

**Carry the rows and trust them, with no re-check.** This is what #1865
proposes, and it's the cheapest. Rejected because a worker wrongly read
missing (the listing missed a live worker twice under load) would stay
exempt from the gate across every later succession, never looked at again,
and because a carried row is the predecessor's observation, not the
successor's, which R15 reads against. One listing per classify fixes both
for one local call.

**Tag each missing row with the host that wrote it.** The row would carry a
machine id, and a classify on another host would ignore rows that aren't its
own. Rejected: it adds a host fact to the Run section's row shape, which the
schema (`state-schema.jq`) and every reader would have to learn, for a case
the caller can decide once at takeover with a fact the opener already reads.

**Skip only the 30 second re-read when the predecessor already had the
worker missing.** The predecessor's rows are gone after the clear, so the
classify would have to read old entries to know, and the saving is the wait
and 20 listings: under a minute of 35 to 41. Rejected because the writes,
which are the cost, stay.

### Decision 2: Whether `pending` rows carry too (#1696)

Resolved inline.

A pending row says the worker's session isn't live while its instance is
still there. Like missing, that doesn't depend on the address, and #1696
measured the same repeat cost for it. Unlike missing, it changes without the
listing noticing: a stopped worker can be started again in the same
instance between two successions, and a listing can't tell a live session
from a stopped one.

Key assumptions:

- The liveness probe the classify already uses (`dc_session_live`, with
  `koto session list --execution-dir` and the Claude job file) is local
  reads only, so running it per carried pending worker costs reads, not
  writes.
- A pending worker that started again reports to the newest member through
  R16 whether or not the successor messaged it.

#### Chosen: carry pending rows under the same filter and host guard, re-probe each one on every classify, as a second change

The filter keeps a `pending` row on the same conditions as a missing one.
Each classify re-probes every carried pending worker with the probe that
first classified it, using the pass's shared listing. A worker still not
live, with its instance listed, keeps its row and costs no write. A worker
that's live now is printed `live W <address>` like any other, and the
agent's `--told` replaces the pending row (`state-stored-set.sh:1094-1096`).
A worker whose instance the listing no longer names goes into the batched
missing write, which means `--missing` must accept a worker recorded pending
and replace that row, where today it refuses one.

This lands after Decision 1, as its own change, because it needs a per-worker
probe instead of one listing and changes a refusal in `--missing`. R15 holds:
every carried pending row is re-observed by the successor. R16 covers the
case the probe misses, a worker started between the probe and its first
report.

#### Alternatives Considered

**Keep clearing pending rows.** The upstream design's own choice: the
successor observes each pending worker afresh. Rejected because the
observation can be made with reads alone; the clear forces a write per
worker to record a result that usually hasn't changed, which is the two-hour
pass #1696 measured.

**Carry pending rows under the one-listing check used for missing.** The
listing would confirm the instance is still there. Rejected because the
listing can't see whether the session came back, so a worker resumed between
successions would keep a pending row while live, and the successor would
never send it the address. R16 means its reports would still arrive, but the
record would say something the successor never checked.

### Decision 3: How the classify writes its rows and reads niwa

Resolved inline.

A first classify, or one after a host change, still has to write a row per
gone worker. Today each row is its own record write, with its own two
whole-record reads, compare-and-swap, visibility GETs and entry. Each worker
also gets its own `niwa list --json`, twice.

Key assumptions:

- A write that records several workers at once can be checked worker by
  worker before anything is written, the way one write is checked today
  (`state-stored-set.sh:1108-1115`).
- The classify already knows, before it writes, that each worker it passes
  has no told, pending or missing row: it took them from
  `state-handover.sh`'s list of workers with none
  (`handover-classify.sh:115`).

#### Chosen: several workers per mode in one write, one entry naming them all, one listing per pass

`state-stored-set.sh` accepts the told, pending and missing modes repeated
(`--missing W1 --missing W2 ...`, the shape `--host` already uses), checks
every worker against the current rules, refuses the whole call if any one
fails, and otherwise writes the Run section once and posts one entry naming
every worker. A retry on exit 11 or 12 repeats the whole call, as `set_row`
does today. `handover-classify.sh` collects the workers it finds pending and
missing and calls the writer once per mode, so a classify makes at most one
write per mode plus the rare re-check write from Decision 1.

`dispatch-common.sh` gains a list-once form: one `niwa list --json` per pass
into a file, and a lookup of a topic in that file. The classify takes one
listing for the re-check and the first pass, and one more after the wait.
`dc_find_session` keeps its signature for its other callers
(`dispatch-worker.sh:632`, `rebrief-record.sh:91`, `state-holding.sh:210`,
`teardown-inventory.sh:187`).

For 20 gone workers, the first classify drops from 20 writes to one (about
41 koto reads, 4 writes and 2 GETs in place of about 820, 80 and 40), and
from 40 listings to 2. It also shrinks the window in which a dispatch write
and a classify write can collide on the compare-and-swap.

#### Alternatives Considered

**Keep one write per worker.** Rejected by driver 5: the writes are the
cost.

**One write for every mode at once.** A single call carrying told, pending
and missing workers together. Rejected because the writer's modes each have
their own refusals and entry text, and a mixed call would need a new
combined mode with its own rules, for at most two saved writes per classify.

**One write, but one entry per worker after it.** Keeps the per-worker
history line. Rejected: each entry still costs about seven koto reads, one
write and one GET (`state-entry.sh`), which gives back a good part of the
saving, and one entry that names every worker says the same thing.

### Decision 4: Which launches a classify holds

Resolved inline.

Launches wait for the classify only because the template's `reconcile`
state leads to `pick_facts` through the handover gate. An operator who
wants launches sooner could move the classify, or launch around it.

Key assumptions:

- With Decisions 1 and 3, a classify on a succession whose carried workers
  are all gone takes about a minute, and a first classify that writes 20
  rows takes about three.
- Every launch through the template writes the record: `dispatch-worker.sh`
  writes the holding `dispatching`, then `dispatched`, through the same
  whole-record compare-and-swap.

#### Chosen: keep the state order; a classify holds only launches that write this run's record

The template doesn't change. For operators, the rule is: a classify holds
only launches that write this run's record. A launch that doesn't touch the
record, such as a dispatch for work outside this run, isn't held.

This narrows the constraint operators already use, never widens it. Every
record write reads the whole record and writes it back
(`state-stored-set.sh:648-649`, `state-write-core.sh:129`), so a launch that
writes the record reads the classified rows and races the classify's write
on the compare-and-swap; a launch that doesn't write it is outside the hold
under both statements. What the hold protects in a record-writing launch is
the record, not the address: the launch's own brief already carries the new
coordinator row (`dispatch-worker.sh:368-379`), and its pick would otherwise
run before `pick_facts` rebuilds `coord/pick.json`.

#### Alternatives Considered

**Move the classify off the launch path**, for example run it after
`pick_facts` or in the background while the run picks and dispatches.
Rejected: it changes the template's states and transitions, which R11 treats
as incompatible, so a successor on the new template couldn't continue a
predecessor on the old one. It also puts the classify's writes and the
dispatch's writes on the compare-and-swap at the same time; each side gives
up after three tries (`handover-classify.sh:84-93`, and the dispatch's
`dc_record_write`), and a dispatch that loses after launching leaves a
worker running with a `dispatching` row. On a discipline scope the same gate
also carries `carry-unacknowledged`, which must hold dispatch. And it saves
nothing in total calls, only wall time on launches, which Decisions 1 and 3
already save.

**Let every launch through during a classify.** Rejected: a record-writing
launch races the classify's write and can run on pick facts not yet rebuilt,
and the rows it would skip waiting for are about a minute away once the
other decisions land.

### Decision 5: How a holding whose worker is gone ends

Resolved inline.

Carrying rows makes a gone worker cheap to keep, but its holding still
covers its unit and counts against the cap (`pick-facts.sh`), and the
reconcile report keeps saying "read again, then decide". Before PR #1968, no
route ended a `dispatched`, unmerged holding whose worker was gone (#1833,
#732).

Key assumptions:

- PR #1968 (merged, not yet in a release) lets `state-holding.sh --retire`
  remove a holding, merged or not, once the teardown check confirms a
  removed teardown whose reason starts with "removed outside the run".

#### Chosen: retire through #1968's removed-outside-the-run teardown route, on evidence

Once a release carries #1968, a holding whose worker the classify records
missing ends through the hub's retire, `teardown: removed` (with no handoff
when nobody can write one, `coordinate.md`, the `teardown` details) and
destroy, and the record entry says the teardown wasn't the run's own. The
reconcile report's next step for a holding whose worker is recorded missing
names that route instead of "read again, then decide". Nothing retires a
holding because it has been missing for a while.

Two gaps stay open and aren't closed here: #1833 asks that a leg-bound
holding's open leg be released when it ends this way, and #732 covers a
holding whose worker vanished with its host, which a teardown check on the
new host can't confirm.

#### Alternatives Considered

**Retire a holding after it has been missing at N classifies, or for T
hours.** N can be counted from the carried `missing` entries. Rejected by
driver 6: elapsed time isn't evidence the worker is gone. A worker misread
missing would lose its holding, and a later report from its topic would
match no holding and be refused. Retiring also frees the unit for pick,
which could re-dispatch work nobody still wants.

**Have reconcile mark such holdings stranded**, as #732 suggests. Rejected
for this design: `--strand` takes only a message return path and
re-dispatches the unit, which is a different outcome from ending it, and
#732 stays open for the host-move case it was filed for.

## Decision Outcome

The five decisions work as one change to the successor's opening minutes.
The address change keeps the missing rows of holdings that still exist on
the same host, and clears `told` as R14 requires. The classify checks every
kept row against one listing, writes nothing for workers still gone, and
classifies any it finds again. When it does have rows to write, it writes
each mode once. Pending rows follow in a second change, re-probed for
liveness each time. The template keeps its order, and operators hold only
launches that write the record.

On a succession whose carried workers are all gone, the classify does a
`--list`, one told-pass log read per carried row, `state-handover.sh` and one
listing: roughly 45 to 65 koto reads, no writes and no wait, about a minute
on the cloud backend (estimated from the call counts above; not yet
observed). A first classify that writes 20 rows makes one batched write, two
listings and the 30 second wait: about three minutes. The launch hold
shrinks by the same amount, from about 40 minutes to about a minute.

The guarantee the classify gives stays: no carried worker silently loses its
coordinator address. A told row still has to be earned from this successor.
A missing row stands only while this successor's listing agrees. A carried
missing or pending worker that comes back finds the newest member through
`resolve-coordinator.sh`, and its first report turns it told at the next
reconcile (`handover-classify.sh:101-112`). The holdings that cause the cost
end through #1968's route once a release carries it, on the teardown
check's evidence.

## Solution Architecture

### Overview

The change sits in four scripts and two documents of
`skills/coordinate/`, and touches no template state:

- `scripts/state-common.sh`: the coordinator-row filter and `lib_carrier_row`.
- `scripts/state-stored-set.sh`: repeated worker modes, the batched entry,
  a mode that drops a missing row the listing finds again, and the keep flag
  on `--run coordinator`.
- `scripts/handover-classify.sh`: the re-check, list-once lookups and
  collected writes.
- `scripts/dispatch-common.sh`: a list-once lookup beside `dc_find_session`.
- `scripts/coordinate-open.sh`: passes the keep flag when the takeover stays
  on this host.
- `koto-templates/coordinate.md` details text (`:3602`), `references/state-keys.md`
  (`:330`) and the `state-stored-set.sh` header (`:41-53`): say what a new
  address now clears.

### Components

**The coordinator-row filter.** `LIB_COORD_ROW_JQ` takes two more inputs: a
`$keep` boolean and the set of workers the record's holdings name. With
`$keep` false it behaves as today. With `$keep` true it drops `told` rows,
keeps `missing` rows whose worker is in the holdings set, and drops the rest.
The second step (Decision 2) extends the kept set to `pending` rows on the
same terms. `lib_carrier_row` today hands the filter only the Run array
(`{run: .}`, `state-common.sh:214`); it gains the holdings as an argument so
the carry paths can apply the same filter.

**The keep flag.** `state-stored-set.sh --run coordinator VALUE --by WHO`
gains `--keep-missing`. The entry text gains a clause naming how many missing
rows were kept. `coordinate-open.sh`'s `finish_takeover` passes the flag when
the takeover isn't an import and `read_watch` left `ELSEWHERE` at 0. The
same-host carry in `state-open.sh` passes `$keep` true to `lib_carrier_row`;
the carry in `state-write-core.sh` passes true only when the copy stays on
this host. Each caller's choice is checked in implementation against how it
is reached.

**Repeated worker modes.** `--told`, `--pending` and `--missing` each accept
the flag more than once. The writer checks each worker with today's rules
(`state-stored-set.sh:1094-1115`) against the state as it builds the next
one, refuses the whole call with the first failing worker's reason, and
otherwise appends every row in one `next.json`, makes one `core_write`, and
posts one entry whose text names every worker. One worker gives exactly
today's entry text.

**Dropping a row the listing finds again.** A new mode,
`--relisted W [--relisted W]... --by WHO`, removes the missing row of each W
and posts one entry saying niwa on this host lists an instance for W again.
It refuses a worker with no missing row. Only the classify writes it.

**The classify.** `handover-classify.sh` runs in this order:

1. `--list`, as today, and the told pass over pending and missing rows, as
   today, collecting the workers to record told and writing them once.
2. One listing (L0) into a file. For every missing row, look the worker up
   in L0. Workers found go into one `--relisted` write.
3. `state-handover.sh`, as today. Its worker set now includes the relisted
   workers, since they have no row.
4. First pass over that set against L0, then (Decision 2) the re-probe of
   carried pending workers against L0.
5. If any worker was missed, wait once and take one more listing (L1), and
   look the missed workers up in it.
6. One `--pending` write for every worker found pending, one `--missing`
   write for every worker missed twice, each through `set_row`'s retry.

The printed lines keep their shapes and order; `relisted <worker>` is added
for the step 2 case, so the agent and the tests can see it.

**The list-once lookup.** `dc_list_sessions <root> <file>` runs `niwa list
--json` once from the root and checks it's an array; `dc_find_in_list
<file> <topic>` does what `dc_find_session` does today against that file.
`dc_find_session` becomes the two in sequence and keeps its exit codes.

### Key Interfaces

```
state-stored-set.sh --session S --run coordinator VALUE --by WHO [--keep-missing]
state-stored-set.sh --session S --told WHO [--told WHO]... --by WHO
state-stored-set.sh --session S --pending WHO [--pending WHO]... --by WHO
state-stored-set.sh --session S --missing WHO [--missing WHO]... --by WHO
state-stored-set.sh --session S --relisted WHO [--relisted WHO]... --by WHO
```

Exit codes stay as they are; a refusal names the worker it refused.
`handover-classify.sh --session S` keeps its usage and exit codes and gains
one output line kind, `relisted <worker>`.

### Data Flow

At takeover, the opener fences the predecessor and writes the coordinator
row with `--keep-missing` on a same-host takeover. The Run section then
holds the new coordinator row, no `told` rows, and the missing rows of
holdings that still exist. At `reconcile`, the classify reads those rows,
checks them against L0, writes a `--relisted` entry only when it found
someone, classifies the remaining workers with no row, and writes each mode
once. `state-handover.sh --check` reads the result as it does today. The gate
passes, and the template goes on to `pick_facts`.

## Implementation Approach

### Phase 1: Batch the classify's writes and listings

Repeated worker modes and the batched entry in `state-stored-set.sh`; the
list-once lookup in `dispatch-common.sh`; the classify collecting its
results and taking one listing per pass. This comes first because it needs
no change to what the record means, and it helps every first classify on
its own.

Deliverables:
- `skills/coordinate/scripts/state-stored-set.sh` (repeated modes)
- `skills/coordinate/scripts/dispatch-common.sh` (list-once lookup)
- `skills/coordinate/scripts/handover-classify.sh` (collected writes, two listings)
- tests beside each script

### Phase 2: Carry missing rows with the one-listing re-check

The filter's keep input and holdings set, the keep flag and its callers, the
`--relisted` mode, the classify's re-check, and the three text updates. This
is #1865.

Deliverables:
- `skills/coordinate/scripts/state-common.sh`
- `skills/coordinate/scripts/state-stored-set.sh` (`--keep-missing`, `--relisted`)
- `skills/coordinate/scripts/coordinate-open.sh`, `state-open.sh`, `state-write-core.sh` (callers)
- `skills/coordinate/scripts/handover-classify.sh` (re-check)
- `skills/coordinate/koto-templates/coordinate.md` details text, `references/state-keys.md`
- tests: the stored-set, handover and classify suites

### Phase 3: Carry pending rows with a per-worker re-probe

The filter keeps pending rows, the classify re-probes them, and `--missing`
replaces a pending row. This is #1696.

Deliverables:
- `skills/coordinate/scripts/state-common.sh`, `state-stored-set.sh`, `handover-classify.sh`
- the same text and test updates for pending

### Phase 4: Point gone workers' holdings at the retire route

Once a release carries #1968, the reconcile report's next step for a
holding whose worker is recorded missing names the retire route.

Deliverables:
- `skills/coordinate/scripts/reconcile-report.sh` and its test

## Security Considerations

To be written in Phase 5.

## Consequences

### Positive

- A succession whose carried workers are all gone holds launches for about
  a minute instead of 35 to 41.
- A first classify that writes many rows makes one write per mode.
- The record stops gaining one entry per gone worker per succession.
- Fewer simultaneous record writes means fewer compare-and-swap retries.

### Negative

- A missing row can now outlive the coordinator that wrote it, so the record
  holds observations older than the current address.
- A batched write refuses as a whole, so one bad worker stops the rows of
  the others in that call.
- The classify reads every missing row against the listing on each run,
  which changes the template's stated rule that a worker recorded missing
  stays missing even when niwa lists it again (`coordinate.md:3601`, said of
  the re-brief path).
- Three documented statements of "a new address clears all three" change.

### Mitigations

- Every kept row is re-checked against this successor's own listing, rows of
  gone holdings are dropped, and rows don't cross hosts.
- The classify only passes workers it took from the list of workers with no
  row, so a batch refusal means the record changed under it, which `set_row`
  already retries.
- The re-brief path's rule stays as it is; only the classify re-checks, and
  the details text says so.
- The text updates land in the same change as the behaviour.
