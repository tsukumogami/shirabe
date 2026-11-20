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
  First, `state-stored-set.sh` takes several workers per mode and writes
  once, and the classify collects its results and writes once per mode,
  taking one niwa listing per pass instead of one per worker. Later steps
  proceed only if a measured split after that one shows they're worth it.
  In the second, a coordinator address change keeps the `missing` rows of
  holdings that still exist, while it still clears `told` (R14). Each
  classify re-checks every kept row against its one niwa listing at
  reconcile, before the handover gate reads any row, and drops the row of
  any worker the listing finds again, so the row always says what this
  successor can see on this host, after a host change too. In the third,
  `pending` rows carry the same way, each one re-probed for liveness on
  every classify. The template's state order stays: a classify holds only
  launches that write this run's record. A holding whose worker is gone ends
  through the removed-outside-the-run retire route PR #1968 added, once a
  release carries it.
rationale: |
  The cost is in the per-worker record writes, not in niwa or the 30 second
  wait, so the fix has to remove writes. Batching leaves one write per mode
  on every classify, which by the call counts takes 20 gone workers from
  about 40 minutes to about three; carrying the rows would remove the rest
  on every succession after the first. A missing row's fact doesn't depend
  on the coordinator address, so only `told` needs clearing, and one listing
  per classify keeps the PRD's "what the successor can observe" reading for
  the cost of one local call, which also makes a host guard unnecessary.
  Moving the classify off the launch path would be a template structure
  change, which the continuation rule refuses, and would add
  compare-and-swap contention on record writes, while the changes above
  shrink the hold to about three minutes, or about a minute with the rows
  carried (both read from call counts). Retiring on a timer was rejected
  because shirabe retires on evidence.
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
workers are gone, each successor's classify ran 35 to 41 minutes, about 1.75
to 2 minutes per holding on average (individual holdings took between about
1.5 and 2.2), spread evenly across the holdings. That fits the
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
a classify, and the route that ends a holding whose worker is gone. The
reconcile report's pointer to that route stays its own issue, #2000, outside
this design's phases. Out of scope: the cost of a single record write itself
(the two whole-record reads, the visibility GETs, the history scans), the
template's state graph, and the succession command
(`DESIGN-coordinate-succession-command.md`), which calls the classify and
gains from it unchanged.

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
- The handover gate is the only reader a missing row exempts a worker from,
  and it runs after the classify at `reconcile` (Context). Nothing acts on a
  kept row before the classify has listed.
- A record moves to another host only through `--import` or a `--continues`
  takeover whose predecessor last wrote from another machine, and both are
  rare next to same-host successions.

#### Chosen: keep missing rows for existing holdings, re-check them with one listing per classify

`LIB_COORD_ROW_JQ` always keeps a `missing` row whose worker still names a
holding in the record, and always drops every `told` row and, until
Decision 2 lands, every `pending` row. It takes no flag, and no caller
decides anything about it. A missing row whose holding is gone is dropped,
so the filter keeps the clean-up the clear used to do by accident: Run rows
aren't tied to holdings, and `state-holding.sh --retire` doesn't touch them.

Each classify then takes one niwa listing at `reconcile`, before it reads
the worker set and before `state-handover.sh --check` reads any row, and
looks up every worker that has a missing row in it. A worker the listing
finds again loses its missing row (one write for all of them, in the rare
case there are any) and is classified with the rest. A worker the listing
still doesn't name keeps its row, with no write. So every missing row the
gate reads has been checked by this successor's own listing, which is what
R15's table asks for, and the check costs one local call rather than one
write per worker.

That one listing also covers a host change. After an `--import`, or a
takeover from another machine, the kept rows were written against another
host's listing, but the first classify on this host checks every one
against this host's listing before the gate reads it: a worker this host
lists loses its row, and a worker it doesn't list keeps a row that's now
true of this host too. A listing that comes back empty while kept rows
exist isn't trusted on its own ("Failing closed on the listing", below), so
a wrong workspace root on the new host can't confirm every row at once.

#### Alternatives Considered

**Keep clearing missing rows, and rely on batching (Decision 3) alone.**
Every succession would still pay the listing, the 30 second wait and one
batched write for all its gone workers: about three minutes, read from the
call counts, against the 35 to 41 observed. That's a real improvement, and
it's this design's first phase. Rejected as the whole answer, if the
measured split after that phase shows the remaining write still matters,
because it keeps a write per succession for a fact nothing changed, and the
record still gains an entry per succession restating it.

**Carry the rows and trust them, with no re-check.** This is what #1865
proposes, and it's the cheapest. Rejected because a worker wrongly read
missing (the listing missed a live worker twice under load) would stay
exempt from the gate across every later succession, never looked at again,
and because a carried row is the predecessor's observation, not the
successor's, which R15 reads against. One listing per classify fixes both
for one local call.

**Keep the rows only while the record stays on the host that wrote them.**
A host guard: a `--keep-missing` flag on `--run coordinator`, set by an
opener helper only on positive evidence that the predecessor's last writer
was this machine (`version.json`'s machine id, or a predecessor session
koto reports as local), with the decision stored after the fence so a
re-run after a crash reuses it, and every failed read meaning drop.
Rejected: the classify's one listing per run, at `reconcile` before
`state-handover.sh --check`, already re-checks every kept row, and it
covers a host change the same way, since the new host's listing decides
each row before the gate reads it. The guard would add a flag, an opener
helper, a stored field in the record and a re-run rule to protect rows that
nothing reads before the listing has checked them, and it would make some
same-host successions pay the full classify whenever one of its reads
failed.

**Tag each missing row with the host that wrote it.** The row would carry a
machine id, and a classify on another host would ignore rows that aren't its
own. Rejected: it adds a host fact to the Run section's row shape, which the
schema (`state-schema.jq`) and every reader would have to learn, for a case
the re-check already settles: this host's listing decides every kept row
before the gate reads it.

**Skip only the 30 second re-read when the predecessor already had the
worker missing.** The predecessor's rows are gone after the clear, so the
classify would have to read old entries to know, and the saving is the wait
and 20 listings: under a minute of 35 to 41, by the call counts. Rejected
because the writes, which are the cost, stay.

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

#### Chosen: carry pending rows under the same filter, re-probe each one on every classify, as a later change

The filter keeps a `pending` row on the same condition as a missing one: its
worker still names a holding. Each classify re-probes every carried pending
worker with the probe that first classified it, using the pass's shared
listing. A worker still not live, with its instance listed, keeps its row
and costs no write. A worker that's live now is printed `live W <address>`
like any other, and the agent's `--told` replaces the pending row
(`state-stored-set.sh:1094-1096`). A worker whose instance the listing no
longer names goes into the batched missing write, which means `--missing`
must accept a worker recorded pending and replace that row, where today it
refuses one. A worker the probe can't settle (its koto log can't be read,
the `unknown` line) loses its carried row, so the gate holds on it as R15
asks for a worker the successor couldn't observe.

This lands after Decision 1, as its own change (#1696), and only if the
measured split after the first phase shows the pending writes are worth
removing, because it needs a per-worker probe instead of one listing and
changes a refusal in `--missing`. R15 holds: every carried pending row is
re-observed by the successor. R16 covers the case the probe misses, a
worker started between the probe and its first report.

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

Every classify today, and a first classify once rows carry, has to write a
row per gone worker. Each row is its own record write, with its own two
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

`state-stored-set.sh` accepts the pending and missing modes repeated
(`--missing W1 --missing W2 ...`, the shape `--host` already uses), and the
told mode the same way once rows carry, checks every worker against the
current rules, refuses the whole call if any one fails, and otherwise writes
the Run section once and posts one entry naming every worker. This is
#1999. `handover-classify.sh` collects the workers it finds pending and
missing and calls the writer once per mode through `set_row`, so a classify
makes at most one write per mode plus the rare re-check write from
Decision 1.

Before every attempt, the first included, `set_row` re-reads the stored set
and drops from the batch any worker that now has a row; a batch left empty
is done. `set_row`'s retry stays as it is: it repeats the call only on exits
11 and 12, a record that changed under it (`handover-classify.sh:87-90`).
Any other exit, a refusal (65, `state-stored-set.sh:783`) among them, ends
the classify with exit 2, so the gate holds and nobody is exempted.

`dispatch-common.sh` gains a list-once form: one `niwa list --json` per pass
into a file, and a lookup of a topic in that file. The classify takes one
listing for the first pass (and, once rows carry, the re-check), and one
more after the wait. `dc_find_session` keeps its signature for its other
callers (`dispatch-worker.sh:632`, `rebrief-record.sh:91`,
`state-holding.sh:210`, `teardown-inventory.sh:187`).

For 20 gone workers, a classify drops from 20 writes to one (about 41 koto
reads, 4 writes and 2 GETs in place of about 820, 80 and 40), and from 40
listings to 2: about three minutes in place of 35 to 41, read from the call
counts and not yet observed. It also shrinks the window in which a dispatch
write and a classify write can collide on the compare-and-swap.

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

- With batching, a classify that writes 20 rows takes about three minutes,
  and with the rows carried, a classify on a succession whose carried
  workers are all gone takes about a minute; both are read from call counts
  and not yet observed.
- Every launch through the template writes the record: `dispatch-worker.sh`
  writes the holding `dispatching`, then `dispatched`, through the same
  whole-record compare-and-swap.

#### Chosen: keep the state order; a classify holds only launches that write this run's record

The template doesn't change. For operators, the rule is: a classify holds
only launches that write this run's record. A launch that doesn't touch the
record, such as a dispatch for work outside this run, isn't held. The rule
is written where an operator meets the classify: the coordinate skill's
reconcile guidance in `SKILL.md` and the template's `reconcile` details.

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
and the rows it would skip waiting for are about three minutes away once
batching lands, by the call counts.

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
destroy, and the record entry says the teardown wasn't the run's own.
Nothing retires a holding because it has been missing for a while. Pointing
the reconcile report's next step for such a holding at that route, instead
of "read again, then decide", stays its own issue, #2000, and isn't one of
this design's phases.

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

The five decisions work as one change to the successor's opening minutes,
landed in steps. The first batches the classify: each mode is one write and
each pass one listing, which by the call counts takes a classify over 20
gone workers from about 40 minutes to about three. If a measured split after
it shows the rest is worth it, the address change then keeps the missing
rows of holdings that still exist and clears `told` as R14 requires; the
classify checks every kept row against one listing, on whichever host it
runs, writes nothing for workers still gone, and classifies any it finds
again. Pending rows follow on the same condition, re-probed for liveness
each time. The template keeps its order, and operators hold only launches
that write the record.

With the rows carried, on a succession whose carried workers are all gone,
the classify does a `--list`, one told-pass log read per carried row,
`state-handover.sh` and one listing: roughly 45 to 65 koto reads, no writes
and no wait, about a minute on the cloud backend (estimated from the call
counts above; not yet observed). A classify that writes 20 rows makes one
batched write, two listings and the 30 second wait: about three minutes,
estimated the same way. The launch hold shrinks by the same amount, from
about 40 minutes to about three with batching alone and about a minute with
the rows carried.

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

The change sits in six scripts and four pieces of text in
`skills/coordinate/`, and touches no template state:

- `scripts/state-common.sh`: the coordinator-row filter and `lib_carrier_row`.
- `scripts/state-stored-set.sh`: repeated worker modes, the batched entry,
  a mode that drops a missing row the listing finds again, and the
  holdings set it hands the filter on `--run coordinator`.
- `scripts/handover-classify.sh`: the re-check, list-once lookups, collected
  writes and a private directory for the listing files.
- `scripts/dispatch-common.sh`: a list-once lookup beside `dc_find_session`.
- `scripts/state-open.sh` and `scripts/state-write-core.sh`: the two carry
  paths, which pass the holdings to `lib_carrier_row`.
- `SKILL.md`'s reconcile guidance and the template's `reconcile` details:
  the operator rule from Decision 4.
- `koto-templates/coordinate.md` details text (`:3601-3602`),
  `references/state-keys.md` (`:330`) and the `state-stored-set.sh` header
  (`:41-53`): say what a new address now clears, and that the classify,
  unlike the re-brief path, re-checks a missing row against the listing.

The template changes are details text, which R11 counts compatible; a
release records the new compiled template's fingerprint in
`coordinate.compat.json` as it does for any text change. The opener
(`coordinate-open.sh`) doesn't change: its takeover write and its carry of
an earlier run reach the filter through `state-stored-set.sh` and
`core_carry`, which read the holdings themselves. The reconcile report's
pointer to the retire route (Decision 5) is #2000 and isn't part of this
change.

### Components

**The coordinator-row filter.** `LIB_COORD_ROW_JQ` takes one more input, the
set of workers the record's holdings name. It drops `told` rows, keeps
`missing` rows whose worker is in that set, and drops the rest; there's no
flag, and every caller gets the same behaviour. The later step (Decision 2)
extends the kept set to `pending` rows on the same terms. `lib_carrier_row`
today hands the filter only the Run array (`{run: .}`,
`state-common.sh:214`); it gains a holdings file. Each caller has the
holdings to hand: `state-stored-set.sh --run coordinator` reads the whole
record before it writes (`:648-656`), so the filter runs over a state that
holds `.holdings`; `state-open.sh`'s carry builds `next.json` with
`.holdings` before it calls `lib_carrier_row` (`:280-294`); and `core_carry`
(`state-write-core.sh:535` onwards) lists and reads every `record/` key of
the source, `record/holdings` among them, so it reads that key before it
rewrites `record/run`. The address entry says how many missing rows the
change kept.

**Repeated worker modes.** `--pending` and `--missing`, and `--told` once
rows carry, each accept the flag more than once. The writer checks each
worker with today's rules (`state-stored-set.sh:1094-1115`) against the
state as it builds the next one, refuses the whole call with the first
failing worker's reason, and otherwise appends every row in one
`next.json`, makes one `core_write`, and posts one entry whose text names
every worker. One worker gives exactly today's entry text. A call that
names one worker twice is refused. Every call goes through the same write
guard as today (`lib_write_guard`, `state-common.sh:143` onwards), so a
write from a session that's no longer the record's driver is refused, which
covers a classify whose run was taken over while it waited. A batch's entry
names each worker once and sits far under the entry budget
(`state-entry.sh:622`); the writer checks the text against that budget
before the state write and refuses a call whose entry would pass it.

**Failing closed on the listing.** A listing that can't be read or isn't a
JSON array ends the classify with exit 2, as `dc_find_session`'s return 2
does today; it's never read as "no instances". A listing that is a valid
empty array, while the record holds missing rows, isn't trusted on its own:
the classify takes the second listing after the wait before it keeps those
rows, so a kept row needs two misses 30 seconds apart in that case. With a
non-empty first listing, and no other worker missed, there's no second
listing, and a kept row's worker is missed once, not twice. A live worker
the listing misreads under load then stays exempt until the next classify
lists it, and R16 is the backstop: a running worker finds the newest member
itself through `resolve-coordinator.sh`, and its first report turns it
told. The listing files live in a directory made with `mktemp -d` under
`umask 077`, removed by an EXIT, INT and TERM trap, which
`handover-classify.sh` doesn't have today.

**Dropping a row the listing finds again.** A new mode,
`--relisted W [--relisted W]... --by WHO`, removes the missing row of each W
and posts one entry saying niwa on this host lists an instance for W again.
It refuses a worker with no missing row, and it goes through the same write
guard and driver check as every other mode. Only the classify writes it.

**The classify.** `handover-classify.sh` runs in this order:

1. `--list`, as today, and the told pass over pending and missing rows, as
   today, collecting the workers to record told and writing them once.
2. One listing (L0) into a file. For every missing row, look the worker up
   in L0. Workers found go into one `--relisted` write.
3. `state-handover.sh`, as today. Its worker set now includes the relisted
   workers, since they have no row.
4. First pass over that set against L0, then (Decision 2) the re-probe of
   carried pending workers against L0. A carried pending worker L0 doesn't
   name joins the missed workers, so it too needs two misses before it's
   recorded missing.
5. If any worker was missed, or L0 was empty while missing rows exist, wait
   once and take one more listing (L1). Look up in it every missed worker
   and every worker that still has a missing row. A missing-row worker L1
   finds goes into one `--relisted` write, which drops its missing row, and
   is then classified like any worker a listing found: printed `live`,
   recorded pending, or printed `unknown`. A missing-row worker L1 doesn't
   name keeps its row.
6. The step 5 `--relisted` write, when there is one, then one `--pending`
   write for every worker found pending and one `--missing` write for every
   worker missed twice, each through `set_row`. The relisted write goes
   first because `--pending` refuses a worker that still has a missing row
   (`state-stored-set.sh:1103`). Before every attempt, the first included,
   `set_row` drops from the batch any worker that now has a row; it retries
   only exits 11 and 12, and any refusal ends the classify with exit 2.

The printed lines keep their shapes and order; `relisted <worker>` is added
for the step 2 and step 5 cases, so the agent and the tests can see it.

**The list-once lookup.** `dc_list_sessions <root> <file>` runs `niwa list
--json` once from the root and checks it's an array; `dc_find_in_list
<file> <topic>` does what `dc_find_session` does today against that file.
`dc_find_session` becomes the two in sequence and keeps its exit codes.

### Key Interfaces

```
state-stored-set.sh --session S --run coordinator VALUE --by WHO
state-stored-set.sh --session S --told W [--told W]... --by WHO
state-stored-set.sh --session S --pending W [--pending W]... --by WHO
state-stored-set.sh --session S --missing W [--missing W]... --by WHO
state-stored-set.sh --session S --relisted W [--relisted W]... --by WHO
```

W is a worker's topic; WHO is the writer named in the row's `set_by`. The
`--run coordinator` usage doesn't change; which rows it keeps is the
filter's doing. Exit codes stay as they are; a refusal names the worker it
refused. `handover-classify.sh --session S` keeps its usage and exit codes
and gains one output line kind, `relisted <worker>`.

### Data Flow

At takeover, the opener fences the predecessor and writes the coordinator
row as it does today. The Run section then holds the new coordinator row,
no `told` rows, and the missing rows of holdings that still exist, whichever
host wrote them. At `reconcile`, the classify reads those rows, checks them
against L0 (and L1 when it takes one), writes a `--relisted` entry only when
it found someone, classifies the remaining workers with no row, and writes
each mode once. `state-handover.sh --check` reads the result as it does
today. The gate passes, and the template goes on to `pick_facts`.

## Implementation Approach

### Phase 1: Batch the classify's writes and listings (#1999)

The smallest change that removes the cost: repeated `--pending` and
`--missing` modes with one batched entry in `state-stored-set.sh`, the
list-once lookup in `dispatch-common.sh`, and the classify collecting its
results, taking one listing per pass and writing each mode once through
`set_row`'s pre-attempt re-read. It changes nothing about what the record
means; the filter and the carry paths stay as they are. By the call counts
it takes a classify over 20 gone workers from about 40 minutes to about
three. The phase also writes down the operator rule from Decision 4, which
is text only.

Phases 2 and 3 proceed only if a measured per-step split of a classify,
taken after Phase 1 lands, shows they're worth it, and any part of them the
split doesn't call for is dropped. Repeated `--told` waits for Phase 2: on
a successor today the told pass has no rows to read, so it writes nothing
until rows carry.

Deliverables:
- `skills/coordinate/scripts/state-stored-set.sh` (repeated `--pending` and `--missing`, the batched entry)
- `skills/coordinate/scripts/dispatch-common.sh` (list-once lookup)
- `skills/coordinate/scripts/handover-classify.sh` (collected writes, two listings, the private listing directory and its trap)
- `skills/coordinate/SKILL.md` (the reconcile guidance under "Running the Workflow") and `skills/coordinate/koto-templates/coordinate.md` (the `reconcile` details): a classify holds only launches that write this run's record
- tests beside each script

### Phase 2: Carry missing rows with the one-listing re-check (#1865)

Only if the split after Phase 1 calls for it. The filter's holdings input
and its three callers, repeated `--told`, the `--relisted` mode, the
classify's re-check against L0 and L1 with its empty-listing rule, and the
three text updates.

Deliverables:
- `skills/coordinate/scripts/state-common.sh`
- `skills/coordinate/scripts/state-stored-set.sh` (`--relisted`, repeated `--told`, the holdings set on `--run coordinator`, the header text)
- `skills/coordinate/scripts/state-open.sh`, `state-write-core.sh` (carry callers)
- `skills/coordinate/scripts/handover-classify.sh` (re-check)
- `skills/coordinate/koto-templates/coordinate.md` details text (`:3601-3602`), `references/state-keys.md`
- tests: the stored-set, handover, carry and classify suites

### Phase 3: Carry pending rows with a per-worker re-probe (#1696)

On the same condition as Phase 2: only if the measured split shows the
pending writes are worth removing. The filter keeps pending rows, the
classify re-probes them, and `--missing` replaces a pending row.

Deliverables:
- `skills/coordinate/scripts/state-common.sh`, `state-stored-set.sh`, `handover-classify.sh`
- the same text and test updates for pending

Pointing the reconcile report at the retire route for holdings whose worker
is recorded missing (Decision 5) isn't a phase of this design: it stays its
own issue, #2000, and waits on a release that carries #1968.

## Security Considerations

This design changes shell scripts under `skills/coordinate/` that already
run with the caller's own rights. It adds no dependency, no network endpoint
and no credential, and it makes fewer GitHub calls than the code it changes:
the visibility GETs of one record write per mode instead of one per worker.
Its security questions are about what the handover gate trusts. The rule
that shapes every answer below is that a kept row can only exempt a worker
from the gate, and a re-check can only take rows away, so every failure is
meant to land on the side of dropping a row and holding the gate.

**Inputs.** The classify reads niwa's listing, worker topic names and the
record's rows. The pass's listing files sit in a private `mktemp -d`
directory under `umask 077`, removed by an EXIT, INT and TERM trap, and are
parsed with the array check and tab-safe jq reads `dc_find_session` uses
today. A listing that can't be read or isn't an array ends the classify with
exit 2; it's never treated as an empty list. A listing that is a valid empty
array while the record holds missing rows (a wrong or empty workspace root
would give one) isn't trusted alone: the classify waits and lists again
before it keeps those rows. Worker names pass the schema's worker check
(`check_worker` in `state-schema.jq`) before any row, entry or printed line
carries them, in every repeated mode and in `--relisted`, and a call that
names one worker twice is refused. The `unknown <worker> <why>` line stays
scrubbed as it is today. Rows in the record are unsigned data, as they are
now; anyone who can write the record can already write a row.

**New write paths.** `--relisted` and the repeated modes are new ways to
change the Run section. Each one goes through the write guard and driver
check every mode uses (`lib_write_guard`, `state-common.sh:143` onwards), so
only the record's driver can make them. The address entry records how many
missing rows the change kept. The driver check also closes the stale-write
window: a classify reads the coordinator address at its start and writes
after its wait, and if a succession lands in between, the old classify's
write comes from a session that's no longer the driver and is refused.

**The gate.** A kept missing row exempts its worker from the handover gate,
so it's kept only while it can be checked. It stands only while this
successor's own listing still doesn't name the worker. A worker the listing
names loses its row and is classified again, so a stale or forged missing
row for a live worker goes at the next classify, sooner than at the next
succession as before. With a non-empty first listing a kept row stands on
one miss rather than two, so a live worker misread under load stays exempt
until the next classify; R16 still delivers its reports to the newest
member, and its first report turns it told. Rows of workers with no holding
are dropped, and `told` rows are always dropped (R14). A carried pending
row (Phase 3) is re-probed on every classify, and one the probe can't settle
loses its row. A row is an observation and never the reason a holding ends:
a holding retires only on the teardown check's evidence, so a misread row
can't remove a live worker's holding.

**Hosts.** A missing row says niwa on the host that wrote it listed no
instance. After an `--import` or a takeover from another machine, a kept
row was written against another host's listing, and nothing reads it as an
exemption until this host's classify has checked it: the handover gate runs
after the classify, and the classify's listing is this workspace root's on
this host. A worker this listing names loses its row; one it doesn't name
keeps a row that's now true here too. An empty listing while rows exist is
listed again after the wait before any row is kept. Two workspace roots on
one machine are covered the same way, since each classify lists from its
own root.

**Writes.** A batched call checks every worker against the record's current
state, writes the Run section once, and refuses as a whole when any worker
fails, which leaves those workers without a row and so held by the gate,
never exempt. Before every attempt, the first included, the classify drops
any worker that now has a row, so one worker recorded by another writer
doesn't refuse the batch, and an attempt that landed before a retry leaves
nothing to write again. `set_row` retries only a record that changed under
it (exits 11 and 12); a refusal ends the classify with exit 2, and a re-run
picks up only the workers with no row. If the state lands and its entry
doesn't post (exit 14), that lost entry covers every worker of the call; the
rows themselves are intact. A call whose entry would pass the entry budget
is refused before the state write.

**Availability and timing.** A classify that keeps failing holds the gate,
and so every launch, as it does today; the design's failures are all of that
kind, never a silent pass. Between the classify's listing and its write
there's a window in which a worker's state can change: a dispatch into that
window under a matching topic could get a row while live. The window is
seconds now that there's one listing per pass, the told pass or the next
classify settles it, and a launch that writes the record is held for the
classify anyway (Decision 4).

**Data.** Rows and entries name workers by topic and nothing else from
niwa's listing; instance paths aren't recorded. One entry names every worker
of a batch, and it goes through the same size and public-host visibility
checks as any other entry (`state-write-core.sh:791`, `:819`). Nothing from
the record is sent to GitHub beyond the visibility lookups the write path
already makes.

## Consequences

### Positive

- A classify that writes many rows makes one write per mode: about three
  minutes for 20 gone workers instead of 35 to 41, read from the call
  counts, with batching alone.
- With the rows carried, a succession whose carried workers are all gone
  holds launches for about a minute, estimated the same way.
- With the rows carried, the record stops gaining one entry per gone worker
  per succession.
- Fewer simultaneous record writes means fewer compare-and-swap retries.

### Negative

- A missing row can now outlive the coordinator that wrote it, so the record
  holds observations older than the current address, and after a host move,
  observations of another host until this host's first classify lists.
- A batched write refuses as a whole, so one bad worker stops the rows of
  the others in that call.
- With a non-empty first listing, a kept row stands on one miss, so a live
  worker misread under load stays exempt until the next classify.
- The classify reads every missing row against the listing on each run,
  which changes the template's stated rule that a worker recorded missing
  stays missing even when niwa lists it again (`coordinate.md:3601`, said of
  the re-brief path).
- Three documented statements of "a new address clears all three" change.

### Mitigations

- Every kept row is re-checked against this successor's own listing before
  the gate reads it, on whichever host, rows of gone holdings are dropped,
  and an empty listing is never trusted alone.
- The classify only passes workers it took from the list of workers with no
  row, and `set_row` drops any worker that has one before every attempt, the
  first included. A refusal that still comes back isn't retried: `set_row`
  retries only exits 11 and 12 (`handover-classify.sh:87-90`), and a refusal
  (exit 65, `state-stored-set.sh:783`) ends the classify with exit 2, which
  holds the gate rather than exempting anyone.
- A live worker misread missing finds the newest member itself through
  `resolve-coordinator.sh` (R16), and the next classify's listing drops its
  row.
- The re-brief path's rule stays as it is; only the classify re-checks, and
  the details text says so.
- The text updates land in the same change as the behaviour.
- Phases 2 and 3 land only on a measured split, so if batching is enough,
  nothing about what the record means changes.
