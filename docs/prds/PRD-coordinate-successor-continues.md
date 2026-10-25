---
schema: prd/v1
status: Draft
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
  version: exactly one session drives the run at any moment, nothing the run
  held is lost, workers and legs reach the successor without hand edits, and
  every tool that reads the run's history follows the recorded relation.
upstream: docs/briefs/BRIEF-coordinate-successor-continues.md
---

# PRD: A coordinator's successor continues its run

## Status

Draft

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
- Exactly one session drives a run at any moment, including while the
  predecessor is still running when the successor opens.
- The handover works from another instance, another checkout, after a plugin
  upgrade and after an import, whenever the run's template is one the
  successor can keep driving, and refuses by name when it isn't.
- Workers and legs follow the run: briefs, legs, watches and the told set all
  reach the successor, and no idle worker is woken only to learn an address.
- Lineage comes from the relation, never from session names.

## User Stories

1. As a coordinator whose context is filling, I want to start my successor
   from a fresh niwa instance running a newer shirabe while I'm still
   ticking, so that the run moves to the successor without a window where we
   both drive it or neither does.
2. As a successor coordinator, I want my first tick to work with no rebind,
   no record edit and no copy, and my first reconcile to find every holding my
   predecessor had reconciled, so that I pick the run up where it was.
3. As a coordinator with a `/work-on` worker in flight across a handover, I
   want that worker's leg result to wake my watch when it lands, so that
   work finished after the handover isn't lost in a watch nobody runs.
4. As a coordinator taking over while a worker is parked for an owner pause,
   I want that worker recorded as pending and the handover to go ahead, so
   that I don't resume it just to tell it my address, and it learns the
   address when it next starts.
5. As an operator importing a run into another workspace with the cloud
   session configuration, I want the takeover there to behave exactly as on
   the original host, and to refuse by naming the template when my shirabe's
   coordinate template can't drive the run.
6. As a coordinator settling a removed worker's cost, or checking whether a
   standing deferral still holds, I want both lookups to follow the recorded
   succession, so that a run whose session names don't fit the old pattern
   still resolves to the right chain.

## Requirements

### Functional

**Takeover and the relation**

- **R1.** Taking over a run opens a new koto session for the successor, tied
  to the successor's own Claude session, and records in it, at open, that it
  continues the predecessor through koto's continues relation. The takeover
  creates no second run alongside a cancelled first one and copies no key
  family as a substitute for the relation.
- **R2.** The takeover works whoever launched the successor: a coordinator's
  own recycle, an operator by hand, or another session picking up a stalled
  run. It names the predecessor explicitly or finds it from the scope; it
  never depends on the launcher's identity.
- **R3.** A takeover finds the predecessor by scope (roadmap or discipline)
  and refuses with a named reason when the scope has no run to continue, more
  than one live run, or a run whose newest member already has a successor.
  A plain start with no prior run behaves as today.

**Single writer**

- **R4.** At no point after the successor's open returns do two sessions both
  accept ticks or record writes for one run. When the predecessor is live,
  the open either stops it before the successor takes over or refuses,
  naming the live predecessor and the reason.
- **R5.** After a takeover, the predecessor's `koto next` and every
  coordinate script that writes the record refuse, and the refusal names the
  successor session.
- **R6.** A takeover interrupted part-way leaves the run driven by exactly one
  of the two sessions, and re-running the same command converges on a
  completed takeover without a hand repair.

**What the successor starts from**

- **R7.** The successor starts from everything the run holds that a later
  reconcile or wait reads: the record (sections, entries, posted
  references), the legs and which of them were already taken, and the
  run's lineage facts (chain start, standing go-aheads). It does not start
  from facts that are rebuilt every visit or sealed to the predecessor's own
  session, and the design states which those are.
- **R8.** The successor's first reconcile finds every holding the
  predecessor had reconciled, with the same classification, and re-processes
  no leg the predecessor had already taken.
- **R9.** The successor's first tick succeeds from its own instance and
  directory with no `koto session rebind`, no edit of the record's state by
  hand and no carry.

**Template and plugin compatibility**

- **R10.** A successor whose plugin sits at another absolute path, or in
  another checkout, continues the run when the template is compatible. The
  plugin path is never part of the compatibility test.
- **R11.** Compatibility is decided by a stated, deterministic rule over the
  predecessor's template and the successor's shipped template. An identical
  template is compatible. A template that changed only in ways the rule
  declares safe is compatible. Any other change is incompatible.
- **R12.** A successor whose shipped coordinate template is incompatible
  refuses to continue the run, names the template and both versions, and
  leaves the predecessor and its run unchanged.

**Coordinator address and workers**

- **R13.** On takeover the run's coordinator address becomes the successor's
  session. Every brief dispatched or re-briefed afterwards names the
  successor as its `reports_to`.
- **R14.** The told set restarts at takeover. A worker counts as told when
  the successor has delivered the address to it, including by
  `dispatch-worker.sh --rebrief`, which records told itself once delivery
  worked.
- **R15.** A worker that can't be told now because its session ended idle is
  recorded as pending, not told and not missing. The handover gate passes
  with pending workers. A pending worker becomes told when it next starts and
  has the successor's address, and nothing resumes a worker only to tell it.
- **R16.** A worker that starts again after one or more takeovers reaches the
  run's current coordinator, not the one its brief originally named, without
  anyone editing its brief by hand.

**Legs and watches**

- **R17.** A leg the predecessor opened, completing after the takeover, wakes
  the successor's `koto request watch` within one wait. This needs koto's
  request store to follow the run's succession from the session that
  requested the leg.
- **R18.** The successor's open arms the successor's leg watch, and any watch
  the predecessor had armed exits rather than outliving the takeover.

**Lineage**

- **R19.** `coord-log.sh chain-start` and the on-reap cost sweep
  (`unit-removed.sh`) find a run's lineage by following the continues
  relation. Neither reads a session-name prefix or a cancel event to decide
  lineage.
- **R20.** For runs carried before this feature, which hold no continues
  relation, lineage reads the recycled-coordinator link the carry already
  writes; it never falls back to the name prefix.

**Import**

- **R21.** After `coordinate-open.sh --import` into a second workspace with
  the cloud session configuration, every requirement above holds for a
  takeover in that workspace.

### Non-functional

- **R22.** A takeover of a run with at least 65 record entries completes
  within koto's action limits (no single koto action over its 30-second cap)
  while the host's one-minute load average is 25 or more.
- **R23.** The takeover prints one result line per outcome (taken over,
  refused with a reason, stopped predecessor) that a calling coordinator can
  parse, and records the takeover as an entry in the run's record.
- **R24.** The takeover requires a koto release that ships the continues
  relation; with an older koto the opener refuses and names the koto version
  it needs rather than falling back to carry-and-cancel.
- **R25.** The relation grants nothing: no authority check reads it, and the
  successor's merge, close and release posture comes from its own grant as
  today.

## Acceptance Criteria

- [ ] From a fresh niwa instance running a different shirabe version than the
      predecessor's, while the predecessor's Claude session is still ticking,
      the successor's open either stops the predecessor and takes over or
      refuses naming the live predecessor; in neither case do two sessions
      accept a tick for the run afterwards. (R4)
- [ ] After a takeover, the predecessor's `koto next` refuses and the refusal
      names the successor; a predecessor-side `state-stored-set.sh` write
      refuses the same way. (R5)
- [ ] Killing the takeover at each of its steps and re-running the same
      command ends with exactly one session driving the run and a completed
      takeover. (R6)
- [ ] The successor's session holds a continues relation naming the
      predecessor, written at open; no `coordinate-` session of the scope was
      cancelled by the takeover and no run besides the successor's was
      opened. (R1)
- [ ] A takeover started by a session that is neither the predecessor nor
      anything it dispatched succeeds and writes the same relation. (R2)
- [ ] A takeover refuses with a named reason for a scope with no run, a scope
      with two live runs, and a predecessor that already has a successor. (R3)
- [ ] The successor's first tick succeeds with no `koto session rebind`, no
      hand edit of record state and no carry. (R9)
- [ ] On a run holding open legs, taken legs, dispatched and parked
      holdings, the successor's first reconcile reports every holding the
      predecessor had reconciled, with the same classification, and takes no
      leg the predecessor had taken. (R7, R8)
- [ ] A run with at least 65 record entries is taken over with no koto action
      exceeding 30 seconds while the one-minute load, recorded at the start
      and end of the takeover, is 25 or more. (R22)
- [ ] A successor whose plugin root is at a different absolute path, with an
      identical template, continues the run. (R10)
- [ ] A successor whose template differs from the predecessor's only in a
      change the compatibility rule declares safe continues the run; one
      whose template changed in any other way refuses, naming the template
      and both versions, and the predecessor still drives the run. (R11, R12)
- [ ] After takeover the run's coordinator row names the successor, and the
      next brief dispatched carries the successor as `reports_to`. (R13)
- [ ] After `dispatch-worker.sh --rebrief` delivers a brief to a worker,
      `state-handover.sh --check` reports no `not-told` gap for that worker
      with no manual `--told` step. (R14)
- [ ] A worker whose session ended idle is recorded pending; the handover
      gate passes; when the worker next starts it reports to the successor
      and is then recorded told; no resume was made only to tell it. (R15)
- [ ] A worker dispatched two takeovers ago, started again after the second,
      reaches the current successor with its brief file untouched by hand.
      (R16)
- [ ] A leg the predecessor dispatched, completing after the takeover, wakes
      the successor's `koto request watch` within one wait. (R17)
- [ ] A `koto request watch` the predecessor had armed has exited by the time
      the successor's open returns, and the successor has a watch armed on
      its own session. (R18)
- [ ] On a fixture where the session-name prefix and the continues relation
      disagree, `chain-start` and the cost sweep both return the lineage the
      relation gives. (R19)
- [ ] On a run carried before this feature, `chain-start` returns the chain
      the recycled-coordinator link gives, and no name-prefix walk runs.
      (R20)
- [ ] Each criterion above that concerns a takeover passes again after
      `coordinate-open.sh --import` into a second workspace with the cloud
      session configuration. (R21)
- [ ] Every takeover outcome prints its result line and appends a record
      entry naming predecessor and successor. (R23)
- [ ] With a koto that lacks the continues relation, the takeover refuses and
      names the koto version it needs; no carry or cancel runs. (R24)
- [ ] An authority check for the successor reads the same with and without
      the relation. (R25)

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
  another. R17 and R21 cover the same host and a second workspace on it.
- Retiring the operators' interim workarounds and recording when each one
  stopped.
- The teardown pass's job lookup for a worker resumed from inside its
  instance (tsukumogami/shirabe#1243).

## Known Limitations

- Pending has no expiry here: a worker that never starts again stays pending
  until the run tears it down. The handover gate no longer protects that
  worker's address, which is the intended trade.
- A worker's liveness can only be observed on the host it runs on. A
  successor that can't observe a worker treats it as pending rather than
  told, so a live worker on another host may be told late.
- R17 needs a koto change in the request store. Until that ships, the shirabe
  takeover can land, and legs the predecessor opened are read by the
  successor's reconcile but don't wake its watch.

## Decisions and Trade-offs

**Continue through the relation, not carry-and-cancel.** The successor opens
its own session and records the relation instead of copying keys into a new
run and cancelling the old one. Alternatives: keep the carry and add a link
(keeps the copy cost and the cancelled original that lineage then has to
walk); attach the successor to the predecessor's session (one koto session tied to
two Claude sessions over its life, so its log can't say which one wrote what,
and R1 requires each coordinator session to keep its own). The relation is what koto#479 builds for exactly this case.

**The single-writer guarantee is fixed; the handshake is the design's.** The
PRD requires that two sessions never drive one run and that the predecessor's
refusal names the successor. Whether the open stops a live predecessor or
refuses until it stops is a mechanism choice the design makes. koto has no
process-liveness signal, so either way the design states what it treats as
live.

**Compatibility is a stated rule, not path or byte equality.** Path equality
is what refuses tsukumogami/shirabe#806 and byte equality is what refuses
tsukumogami/shirabe#1144. Inferring safety from a diff alone misses a change
that keeps a gate's shape but changes its meaning, so the rule must be one an
author can state; the design picks it.

**Pending instead of resuming to tell.** A stopped worker has no inbox, and
writing told before it is told would make the record false. Pending keeps the
record true and lets the gate pass; the worker resolves the current
coordinator when it next starts.

**Older runs read the existing link, never names.** Runs carried before this
feature already hold a recycled-coordinator link to the run they carried.
Reading it keeps their lineage without keeping the name rule alive.

**Cross-host leg ringing is excluded.** The request store is host-local by
koto's design. Replicating it is a koto storage change well beyond this
feature; the import clause is met within one host's workspaces.
