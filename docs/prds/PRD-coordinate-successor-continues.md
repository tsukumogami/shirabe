---
schema: prd/v1
status: In Progress
problem: |
  A /coordinate run outlives the Claude sessions that drive it, and every
  handover today opens a second run, cancels the first and copies part of its
  record. The successor loses what the run held, guesses its lineage from
  session names, is refused across plugin paths and harmless template
  changes, needs a hand rebind and hand-written coordinator rows, can't hear
  legs the predecessor opened, and nothing stops two sessions driving one run.
goals: |
  A successor coordinator continues the run it takes over, through koto's
  continues relation, with one command from any instance or compatible plugin
  version: at most one session drives the run at any moment, nothing the run
  held is lost, workers and legs reach the successor without hand edits, and
  every tool that reads the run's history follows the recorded relation.
absorbed:
  - docs/briefs/BRIEF-coordinate-successor-continues.md
---

# PRD: A coordinator's successor continues its run

## Status

In Progress

Absorbed [BRIEF-coordinate-successor-continues](docs/briefs/BRIEF-coordinate-successor-continues.md); carried in Absorbed Brief.

Amended after acceptance, during design review: R24's koto floor now names
the fence that stops a predecessor as well as the relation, because the
design builds R4 and R5 on a koto change and an open on a koto without it
can't meet them. R18's "the open" is read by the design as the opener plus
the watch-arming step it hands the agent, since only the agent can start a
watch whose wake reaches it; the criterion is checked after that step.

## Absorbed Brief

The feature exists because a coordinate run outlives the sessions that drive
it, and the handover between them doesn't continue the run. The brief framed
the gap as a successor that copies part of the record into a second run and
cancels the first, loses what else the run held, guesses its lineage from
names, is refused across plugin paths and harmless template changes
(tsukumogami/shirabe#806, tsukumogami/shirabe#1144), needs a hand rebind and
hand-written coordinator rows, wakes idle workers only to tell them an address
(tsukumogami/shirabe#1245), can't hear legs its predecessor opened, and has
nothing stopping two sessions driving one run. It named koto's continues
relation (tsukumogami/koto#479) as the record the takeover should be built
on. This document's Problem Statement states all of that in full.

The outcome it asked for is an operator or coordinator who hands a run to a
fresh session with one command and sees the run carry on: one driver, nothing
lost, workers and legs reaching the successor, idle workers learning the
address on their next start, and lineage tools following the recorded
succession. That is this document's Goals. Its five journeys (a recycle while
the predecessor still runs, a worker finishing after the handover, an idle
worker pending at handover, a takeover after an import, and the cost sweep and
deferral check tracing a run's history) are the User Stories, with the
operator recovering a crashed run and the post-takeover first tick added.

Its boundary held the feature to the coordinate skill's takeover and the
request-store change it needs, and pushed out the relation itself and its
retention, koto's prune name rule, niwa's reap and destroy, other skills'
succession, the retirement of interim workarounds, and the teardown job
lookup (tsukumogami/shirabe#1243). Those are this document's Out of Scope.
It drew on the current resume-or-carry rule
(`docs/designs/current/DESIGN-coordinator-session-record.md`), the leg watch
(`docs/designs/current/DESIGN-coordinate-paused-state.md`) and the cost
sweep (`docs/designs/current/DESIGN-fleet-cost-capture.md`), which this
feature changes.

## Problem Statement

A `/coordinate` run drives a roadmap or a standing discipline for days. The
Claude session that drives it is replaced far more often: its context fills,
the host restarts, a newer shirabe is installed, or the run is moved to
another workspace. Coordinators and the operators who restart them hit the
handover several times a day.

The handover doesn't continue the run. `coordinate-open.sh` finds the earlier
run by its name prefix, opens a second run, cancels the first and copies its
`record/` and `legs/` keys into the second. What the run held beyond those two
families stays behind, including the record of which legs it already took, so
the new run reconciles more from scratch than it should. The lineage that the
deferral check and the teardown cost sweep depend on is reconstructed by
walking back through sessions with the same name prefix while each one was
cancelled, which breaks as soon as a name or a cancel differs from the
pattern.

Several steps fail or fall to people. An import onto a host whose plugin sits
at another path is refused on provenance (tsukumogami/shirabe#806), and an
import across a template change that didn't affect the run is refused as a
template mismatch (tsukumogami/shirabe#1144); both force a manual carry. The
new session's execution directory is rebound by hand before its first tick.
The coordinator address on the record and the set of workers told about it
are rewritten by hand, a re-brief doesn't count as telling, and a stopped
worker can't be told at all, so the handover gate holds the run until someone
resumes the worker just to tell it (tsukumogami/shirabe#1245). Legs the
predecessor opened still name it as their requester, so a worker finishing
after the handover never wakes the successor's `koto request watch`, and the
predecessor's watcher keeps running.

Nothing stops two sessions driving one run. If the predecessor is still alive
when its successor opens, both can tick and both can write the record.

koto is gaining a relation by which a session names the session it continues
(tsukumogami/koto#479), held by the successor, read by retention, granting no
authority. That relation is the record this feature needs; what is missing is
a takeover built on it.

## Goals

- A coordinator, or an operator acting for one, hands a run to a fresh
  session with one command, and the run continues in that session: same
  record, same legs, same lineage, no second run and no cancelled original.
- At most one session drives a run at any instant. The only moment with no
  driver is the takeover command itself.
- The handover works from another instance, another checkout, after a plugin
  upgrade and after an import into another workspace, whenever the run's
  template is one the successor can keep driving, and refuses by name when it
  isn't.
- Workers and legs follow the run: briefs, legs, watches and the told set all
  reach the successor, and no idle worker is woken only to learn an address.
- Lineage comes from the relation, never from session names.

## User Stories

1. As a coordinator whose context is filling, I want to start my successor
   from a fresh niwa instance running a newer shirabe while I'm still
   ticking, so that the run moves to the successor and I stop driving it,
   with no moment where we both do.
2. As an operator whose coordinator crashed overnight, I want to start a
   successor that continues the crashed run, so that the run picks up without
   anyone reconstructing its record.
3. As a successor coordinator, I want my first tick to work with no rebind,
   no record edit and no copy, and my first reconcile to find every holding my
   predecessor had reconciled, so that I pick the run up where it was.
4. As a coordinator with a `/work-on` worker in flight across a handover, I
   want that worker's leg result to wake my watch when it lands, so that
   work finished after the handover isn't lost in a watch nobody runs.
5. As a coordinator taking over while a worker is parked for an owner pause,
   I want that worker recorded as pending and the handover to go ahead, so
   that I don't resume it just to tell it my address, and it reaches me when
   it next starts.
6. As an operator importing a run into another workspace on the same host
   with the cloud session configuration, I want the takeover there to meet
   the same criteria as in the original workspace, and to refuse by naming
   the template when my shirabe's coordinate template can't drive the run.
7. As a coordinator settling a removed worker's cost, or checking whether a
   standing deferral still holds, I want both lookups to follow the recorded
   succession, so that a run whose session names don't fit the old pattern
   still resolves to the right chain.

## Requirements

### Terms

These words have one meaning everywhere in this document.

- **Run**: one coordinate effort for one scope (a roadmap or a discipline),
  across every session that has driven it. Its **members** are those
  sessions, linked by continues relations; its **newest member** is the one
  no other member continues.
- **Drive**: accept a `koto next` that advances the run's workflow, or a
  write to the run's record by a coordinate script.
- **Live** (a session): its koto session is not finished or cancelled, and
  either its Claude job shows a running process on this host or, when the
  job can't be observed from this host, its koto log recorded an event in
  the last 10 minutes. A session that isn't live is **not live**.
- **Holding**: a unit of work the run is responsible for, recorded as a Work
  row in the record (a dispatched worker, a parked item, a pull request
  awaiting landing or teardown). Its **classification** is the kind and
  state reconcile assigns to that row.
- **Told**: a worker is told when the coordinator's current address has been
  delivered to it: a message to its session that the send reported as
  accepted, or a re-rendered brief followed by such a message.
- **Pending**: a worker that can't be told now because its session is not
  live, recorded as such rather than as told or missing.
- **Template version**: the content hash of the compiled coordinate
  template, plus the shirabe version that shipped it.

### Functional

**Takeover and the relation**

- **R1.** Taking over a run opens a new koto session for the successor, tied
  to the successor's own Claude session, and records in it, at open, that it
  continues the run's newest member through koto's continues relation. The
  takeover opens no second run alongside a cancelled first one and copies no
  key family as a substitute for the relation. A run taken over several
  times forms a chain of members, each continuing the one before.
- **R2.** The takeover works whoever launched the successor: a coordinator's
  own recycle, an operator by hand, or a session unrelated to the
  predecessor. The predecessor is either named on the command line or found
  from the scope; nothing depends on the launcher's identity.
- **R3.** When the predecessor isn't named, it is the newest member of the
  scope's one unfinished run. A takeover refuses, with a reason code and
  without changing anything, when: the scope has more than one unfinished
  run (`ambiguous-scope`); the named predecessor isn't the newest member of
  an unfinished run of that scope (`not-newest-member`); or a different
  successor has already started or completed a takeover of the run
  (`taken-over`). Of two takeovers of one run started at the same time by
  different successors, exactly one succeeds. A start for a scope with no
  unfinished run opens a new run as today (`outcome=opened`). Re-running the
  open from the session that already took over the run is not a rival: it
  completes an interrupted takeover (`outcome=continued`) or, when the
  takeover had completed, attaches to it (`outcome=resumed`).

**Single writer**

- **R4.** When the newest member is live, the open takes over and stops it
  from driving the run; it refuses (`predecessor-unstoppable`) only when it
  can't establish that stop, and that refusal, like every refusal, leaves
  the predecessor driving the run and writes nothing. When the newest member is not live, the open
  takes over without stopping anything. In every case, from the moment the
  open returns, at most one session drives the run, and a tick or record
  write the predecessor started before the takeover either completes before
  the successor's first tick or is refused.
- **R5.** After a takeover, every attempt by a predecessor to drive the run
  is refused, and the refusal names the session that now drives it (the
  newest member, after any later takeovers). This covers the predecessor's
  `koto next` and every coordinate script that writes the record; the design
  lists those scripts.
- **R6.** The design lists the takeover's steps. A takeover interrupted after
  any step leaves the run driven by at most one session, and re-running the
  same command completes the takeover without a hand repair.

**What the successor starts from**

- **R7.** The successor starts from these facts of the run, read or carried,
  without a hand step: every record section, record entry and posted
  reference; every leg and whether it was already taken; and the run's
  lineage facts (its chain start and the standing go-aheads recorded since
  then). It does not start from facts rebuilt on every visit to a state
  (`coord/*`, `reconcile/*`) or from checks sealed into the predecessor's own
  log; the successor rebuilds those. The design publishes the closed list of
  key families in each group.
- **R8.** The successor's first reconcile reports every holding the
  predecessor's last reconcile reported, with the same classification,
  except a holding whose state changed (a leg resolved, a pull request
  merged) after the takeover began, which it reports in its new state; it
  takes no leg the predecessor had taken.
- **R9.** The successor's first tick, run from the directory and instance the
  successor was launched in, exits 0 and is accepted by the workflow, with
  no `koto session rebind`, no hand edit of the record and no carry.

**Template and plugin compatibility**

- **R10.** A successor whose plugin sits at another absolute path, in another
  checkout, or at a newer shirabe version continues the run when the
  template is compatible. The plugin path is never part of the test.
- **R11.** Compatibility is a stated, deterministic rule over the
  predecessor's template version and the successor's. At minimum: an
  identical compiled template is compatible; a change only to directive or
  details text that no gate, evidence schema or transition reads is
  compatible; a change to a state name, a transition, an evidence field, a
  variable, or what a gate's exit code means is incompatible, including a
  change that keeps a gate's command and shape but changes the meaning of
  its result.
- **R12.** A successor whose shipped template is incompatible refuses,
  naming the template and both template versions. The refusal writes
  nothing: no session, no relation, no record entry; the predecessor's run
  is unchanged.

**Coordinator address and workers**

- **R13.** On takeover the run's coordinator address becomes the successor's
  session. Every brief dispatched or re-briefed afterwards names the
  successor as its `reports_to`.
- **R14.** The told set is empty at takeover; a worker told by a predecessor
  isn't told for the successor. `dispatch-worker.sh --rebrief` records the
  worker as told once its message is accepted, and records nothing when
  delivery fails.
- **R15.** At the handover gate, each worker of a live holding is classified
  by what the successor can observe:

  | Worker condition | Status |
  |---|---|
  | Session live and the address message accepted | told |
  | Session live and the address message refused | not told: the gate holds with a `not-told` gap, as today |
  | Session not live (ended idle, stopped, or on another host with no koto event in 10 minutes) | pending |
  | Instance gone, as today's teardown check reads it | missing (today's handling) |

  The handover gate passes with pending workers and holds on not-told ones. A pending worker becomes
  told when its first report after starting again reaches the successor;
  the successor records that at its next reconcile. Nothing resumes a worker
  only to tell it.
- **R16.** A worker that starts again after one or more takeovers sends its
  first report to the run's newest member, not the coordinator its brief
  originally named, without anyone editing its brief by hand.

**Legs and watches**

- **R17.** A leg any earlier member opened, completing after a takeover, makes
  the newest member's armed `koto request watch` exit with a wake within 10
  seconds of the leg's result being recorded. This needs koto's request
  store to follow the run's continues chain from the member that requested
  the leg.
- **R18.** A successful open leaves a `koto request watch` armed on the
  successor's session and no watch running on any predecessor's session on
  this host. A predecessor watcher already gone is not an error. A watcher
  the open can't observe (on another host) doesn't block the takeover, and
  the result says so. A refused open arms nothing.

**Lineage**

- **R19.** `coord-log.sh chain-start` and the on-reap cost sweep
  (`unit-removed.sh`) find a run's members by following the continues
  relation. Their result is the same whatever the members' names are and
  whether or not any member was cancelled.
- **R20.** A run carried before this feature holds no continues relation.
  Lineage for it follows the recycled-coordinator link the carry wrote
  (`dispatched-by`, from each carried run to the run it carried). A chain
  that mixes the two (a carried run later taken over through this feature)
  follows the relation back to the first member without one, then that
  member's link. A member with neither is the chain start.

**Import**

- **R21.** After `coordinate-open.sh --import` into a second workspace on the
  same host with the cloud session configuration, a takeover in that
  workspace meets the same requirements.

### Non-functional

- **R22.** A takeover of a run with at least 65 record entries completes with
  no koto action exceeding koto's 30-second action cap, while the host's
  one-minute load average is 25 or more. The design states the largest run
  size it supports and the koto calls a takeover makes per entry.
- **R23.** The open prints its outcome as `key=value` lines, one key per
  line, with a fixed `outcome=` line whose value is one of `continued`,
  `opened`, `resumed` or `refused`; `continued` adds `predecessor=`,
  `predecessor_stopped=yes|no`, `watcher=stopped|absent|unobserved` and
  `leg_wake=supported|unsupported`, and
  `refused` adds `reason=` with one of `ambiguous-scope`,
  `not-newest-member`, `taken-over`, `predecessor-unstoppable`,
  `template-incompatible` or `koto-too-old`. A completed takeover appends
  exactly one record entry naming predecessor and successor, however many
  times the open was re-run to complete it; a refusal appends none.
- **R24.** The takeover needs a koto release with the continues relation and
  with the fence that stops a predecessor (R4, R5).
  With an older koto the open refuses (`koto-too-old`) and names the version
  it needs; it never falls back to carry-and-cancel. With those but
  without koto's request-store change behind R17, the open still takes over
  and prints `leg_wake=unsupported`; R17's criterion then fails, and the
  feature isn't accepted until it passes.
- **R25.** The relation grants nothing. The successor's merge, close and
  release posture, as the coordinate grant reader reports it, is identical
  with and without the relation.

## Acceptance Criteria

Takeover and single writer

- [ ] From a fresh niwa instance on a different shirabe version than the
      predecessor's, with the predecessor's Claude job running and ticking,
      the open prints `outcome=continued` and `predecessor_stopped=yes`; the
      predecessor's next `koto next` refuses naming the successor; no tick
      by the predecessor is accepted after the open returns. (R4, R5)
- [ ] With the predecessor's job finished and its last koto event over 10
      minutes old, the open prints `outcome=continued` and
      `predecessor_stopped=no`. (R4)
- [ ] With a predecessor tick held mid-action (a gate command blocked on a
      signal the test controls) when the open runs, then released: the
      predecessor's log has no event after the takeover's record entry, and
      the held tick either completed before the successor's first tick or
      exited refused naming the successor. Same for a record write held
      mid-script. (R4)
- [ ] When the design's stop can't be established (the design names how a
      test forces that), the open prints `outcome=refused` and
      `reason=predecessor-unstoppable`; the store holds no new session,
      relation or record entry, and the predecessor's next tick is accepted.
      (R4)
- [ ] After a takeover, each record-writing script the design lists, run
      against the predecessor, refuses naming the successor. (R5)
- [ ] For each takeover step the design lists, killing the open after that
      step and re-running the same command ends in `outcome=continued` with
      at most one session having driven the run at any point. (R6)
- [ ] The successor's session holds a continues relation naming the
      predecessor, written at open; no session of the scope was cancelled
      by the takeover and no other run was opened. (R1)
- [ ] On a chain A, B, C (B continues A, C continues B), `koto session
      hierarchy` shows each relation; a takeover naming A or B refuses, one
      naming C succeeds, and A's and B's `koto next` both refuse naming the
      new member. (R1, R3, R5)
- [ ] A takeover launched by a session that is neither the predecessor nor
      anything it dispatched succeeds and writes the same relation. (R2)
- [ ] A takeover naming the predecessor explicitly and one finding it from
      the scope produce the same relation; naming a session of another scope
      refuses. (R2, R3)
- [ ] A takeover refuses, leaving the store unchanged and printing the named
      reason, for a scope with two unfinished runs (`ambiguous-scope`), a
      named predecessor that isn't the newest member (`not-newest-member`),
      and a run another successor already took over (`taken-over`). (R3)
- [ ] Two takeovers of one run started together by different successors:
      exactly one prints `outcome=continued`, the other `reason=taken-over`.
      (R3)
- [ ] A start for a scope with no unfinished run prints `outcome=opened`;
      re-running the open from a successor whose takeover completed prints
      `outcome=resumed` and adds no record entry. (R3, R23)

What the successor starts from

- [ ] The successor's first tick, run from its launch directory in a
      different checkout from the predecessor's, exits 0 and is accepted,
      with no `koto session rebind`, record edit or carry. (R9)
- [ ] On a run holding open legs, taken legs, dispatched and parked
      holdings, standing go-aheads and at least 65 entries, taken over while
      the one-minute load recorded at start and end is 25 or more: no koto
      action exceeds 30 seconds; the successor's first reconcile reports
      every holding the predecessor's last reconcile reported with the same
      classification; it takes no already-taken leg; `chain-start` and the
      standing go-aheads read the same as before the takeover. (R7, R8, R22)
- [ ] The successor's `coord/*` and `reconcile/*` keys and log seals are its
      own, written by its own ticks, and none was copied from the
      predecessor. (R7)

Template and plugin compatibility

- [ ] A successor with an identical template, its plugin root at a different
      absolute path, continues the run. (R10)
- [ ] A successor on a newer shirabe whose template differs only in
      directive text continues the run. (R10, R11)
- [ ] A successor whose template changes a gate's exit-code meaning while
      keeping its command refuses, naming the template and both template
      versions; the store holds no new session, relation or record entry; the
      predecessor still drives the run. Same for a renamed state. (R11, R12)

Coordinator address and workers

- [ ] After takeover the coordinator row names the successor; the next
      dispatched brief and the next re-briefed brief carry the successor as
      `reports_to`. (R13)
- [ ] Immediately after takeover the told set is empty, including for
      workers the predecessor had told. (R14)
- [ ] After `--rebrief` with its message accepted, `state-handover.sh
      --check` reports no `not-told` gap for that worker; with the message
      refused, the worker is not recorded told. (R14)
- [ ] A live worker whose address message is refused is not recorded told,
      and `state-handover.sh --check` reports its `not-told` gap. (R15)
- [ ] A worker whose session ended idle, and a worker on another host with no
      koto event in 10 minutes, are recorded pending; the handover gate passes; no resume is issued to
      either. When the idle worker is resumed for its own work, its first
      report reaches the successor and the successor's next reconcile
      records it told. (R15, R16)
- [ ] A worker dispatched two takeovers ago, started again after the second,
      sends its first report to the newest member, with its brief file
      untouched by hand. (R16)

Legs and watches

- [ ] A leg the predecessor dispatched, completing after the takeover, makes
      the successor's armed watch exit with a wake within 10 seconds of the
      leg's result being recorded; the same holds two takeovers later. (R17)
- [ ] After the open returns, a watch is armed on the successor's session and
      no `koto request watch` for the predecessor's session runs on the host;
      with the predecessor's watcher already gone the open prints
      `watcher=absent`; a refused open leaves no new watch. (R18)

Lineage

- [ ] On a fixture whose member names follow the old prefix pattern but whose
      relations say otherwise, with one member cancelled and one not,
      `chain-start` and the cost sweep return the lineage the relations
      give. (R19)
- [ ] On a pre-feature carried run with a same-prefix sibling that a
      name walk would include, `chain-start` returns the chain the
      recycled-coordinator links give; a carried run later taken over through
      this feature returns the relation's members followed by the carried
      links; a run with neither relation nor link returns itself as chain
      start. (R20)

Import, output, versions and authority

- [ ] After `coordinate-open.sh --import` into a second workspace on the same
      host with the cloud session configuration, the criteria under Takeover
      and single writer, What the successor starts from, Template and plugin
      compatibility, Coordinator address and workers, Legs and watches, and
      Lineage pass in that workspace, with the imported copy as the
      predecessor. (R21)
- [ ] With a koto that has the continues relation and the fence but not the
      request-store change, the open prints `outcome=continued` and
      `leg_wake=unsupported`. (R24)
- [ ] Every outcome prints the `key=value` lines R23 lists; a takeover adds
      one record entry naming both sessions; a refusal adds none. (R23)
- [ ] With a koto older than the continues relation or the fence, the open prints
      `outcome=refused` and names the koto version it needs; no session is
      cancelled or carried. (R24)
- [ ] The coordinate grant reader reports the same merge, close and release
      posture for the successor with and without the relation. (R25)

## Out of Scope

- The continues relation itself, its retention rules and import keeping its
  source as a read-only predecessor (tsukumogami/koto#479 and its
  implementation). This feature writes and reads the relation; it doesn't
  define it.
- koto's prune name rule for `coordinate-` sessions and the other removal
  guards. They are separate koto work that also reads the relation.
- niwa keeping an instance while a session in it hasn't been continued, and
  resuming a worker whose directory was removed.
- Succession for `/execute`, `/work-on`, `/deliver` and other skills' runs.
- Ringing legs across hosts: koto's request store is host-local and isn't
  replicated by import, so a leg on one host can't wake a successor on
  another. R17 and R21 cover one host and its workspaces.
- Taking over a run whose newest member was cancelled by the old
  carry-and-cancel flow: that member is not the newest member, the carried
  run is, and R20 covers its lineage.
- Retiring the operators' interim workarounds and recording when each one
  stopped.
- The teardown pass's job lookup for a worker resumed from inside its
  instance (tsukumogami/shirabe#1243).

## Known Limitations

- Pending has no expiry here: a worker that never starts again stays pending
  until the run tears it down. The handover gate no longer protects that
  worker's address, which is the intended trade.
- Liveness from another host rests on the 10-minute event window, so a
  predecessor on another host that is alive but quiet for longer reads as not
  live, and a worker there is treated as pending.
- R17 needs a koto change in the request store. The shirabe takeover can be
  built before it, and until it ships, legs the predecessor opened are read
  by the successor's reconcile but don't wake its watch; the feature isn't
  accepted until that criterion passes.

## Decisions and Trade-offs

**Continue through the relation, not carry-and-cancel.** The successor opens
its own session and records the relation instead of copying keys into a new
run and cancelling the old one. Alternatives: keep the carry and add a link
(keeps the copy cost and the cancelled original that lineage then has to
walk); attach the successor to the predecessor's session (one koto session
tied to two Claude sessions over its life, so its log can't say which one
wrote what). The relation is what tsukumogami/koto#479 builds for exactly
this case.

**A live predecessor is stopped, not waited for.** Coordinators recycle while
they are still running, so an open that refused whenever the predecessor was
live would turn every recycle into a hand stop followed by a retry, which is
the workaround this feature retires. The PRD therefore requires the open to
take over and stop the predecessor from driving the run, and to refuse only
when it can't establish that stop. How it stops it (a fence the predecessor's
next tick reads, a message, ending its process) is the design's choice.

**Live is defined by what can be observed.** koto has no process-liveness
signal. The Claude job's running process is the best signal on one host; a
recent koto event is the only one across hosts. The 10-minute window matches
the order of koto's stale-dispatch timeout and errs toward treating a quiet
remote predecessor as not live, which R4 still handles safely because the
predecessor's next attempt to drive the run is refused either way.

**Concurrent takeovers: exactly one wins.** Two successors racing for one run
would otherwise both pass the "no successor yet" check. Requiring exactly one
to succeed makes the claim on the run atomic; the design picks where the
claim is made.

**Compatibility is a stated rule, not path or byte equality.** Path equality
is what refuses tsukumogami/shirabe#806 and byte equality is what refuses
tsukumogami/shirabe#1144. Inferring safety from a diff alone misses a change
that keeps a gate's shape but changes its meaning, so the rule must be one an
author can state. R11 fixes its floor (the safe and unsafe classes); the
design picks how the rule is expressed and checked.

**Pending instead of resuming to tell.** A stopped worker has no inbox, and
writing told before it is told would make the record false. Pending keeps the
record true and lets the gate pass. The worker reaches the newest member when
it next starts, and its first report is what turns pending into told, because
that is the first moment the successor can observe the worker has the address.

**Older runs read the existing link, never names.** Runs carried before this
feature already hold a recycled-coordinator link to the run they carried.
Reading it keeps their lineage without keeping the name rule alive.

**Cross-host leg ringing is excluded.** The request store is host-local by
koto's design. Replicating it is a koto storage change well beyond this
feature; the import clause is met within one host's workspaces.
