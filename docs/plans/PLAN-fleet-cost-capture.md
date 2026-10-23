---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-fleet-cost-capture.md
milestone: "Fleet cost capture"
step_count: 8
---

# PLAN: Fleet cost capture

## Status

Active

## Scope Summary

Build what `docs/designs/DESIGN-fleet-cost-capture.md` settles, in one pull
request against the coordinate skill: an on-reap step and a detached sweep
(`unit-removed.sh`) that capture a unit niwa removes outside the teardown pass,
the collection code the sweep shares with the pass (`archive-common.sh`), and
the capture's own changes in `unit-cost.sh`: dedupe by dispatch id under a host
lock, the dispatch id and milestone fallbacks, the `opened` key, failing heads
read per head, and the placement default, read through one accessor for the
switch #1114 adds. One field is
added to the dispatch leg key in `dispatch-worker.sh`, and
`references/unit-cost.md` documents all of it, the workspace's on-reap line
included.

## Decomposition Strategy

Walking skeleton. Step 1 crosses the whole new path on the suites' stubs: niwa's
environment reaches `unit-removed.sh record`, which writes a removal record and
detaches a sweep, which finds the coordinator through the unit's koto request,
archives what survives through the shared collection code, and runs the capture,
which writes one `cost` entry in that coordinator's session carrying the reap key
as its dispatch id. Each later step adds one behaviour on that path: counting a
unit once, failing heads over every head, the placement default, the milestone
from the leg key, open pull requests, retry and expiry, and the documentation a
workspace maintainer reads.

## Steps

### Step 1: a unit niwa removes gets its cost entry in the dispatching coordinator's session

**Goal**: The on-reap step, run with niwa's environment for a coordinator-dispatched unit whose instance is gone, records the removal and starts a detached sweep, which finds the coordinator through the unit's koto request, archives what survives with the collection code now shared with the teardown pass, and runs the capture, so one `cost` entry lands in that coordinator's session with the reap key as its dispatch id.

**Acceptance Criteria**:

- [ ] Given a stub Claude home holding the instance's transcripts, a koto `work-on` session whose execution directory was in the removed instance, and a koto request whose `requested_by` is a live stub coordinator holding the matching leg key, `unit-removed.sh record` exits 0 and, once its sweep ends, `record-append.sh --list` on that coordinator shows one `cost` entry whose `"niwa.dispatch.id"` is the reap key, with worker tokens and the session's state times `measured` and the job-state figures `not recoverable`, `no source`.
- [ ] `unit-removed.sh record` exits 0 while the sweep it started is still blocked (the suite holds the stub capture on a fifo, reads the removal record, then releases it).
- [ ] With no reap key, a reap key equal to the session id, a reap key starting with `-`, an instance path holding `..` or outside the directory `record` runs in, a removals directory that is a symbolic link or not mode 0700, or the script writable by group or others, `record` prints one line, writes no record and exits 0.
- [ ] A second removal of the same dispatch id at the same instance path keeps the first record's `removed_at`; one at a different instance path replaces the record.
- [ ] The existing `teardown-pass_test.sh` and `teardown-pass_engine_test.sh` cases pass unchanged against the pass that now sources the shared collection code.

**Check**: Run `bash skills/coordinate/scripts/unit-removed_test.sh` and see its end-to-end case print `ok` with the entry's dispatch id equal to the reap key and each refusal case print `ok`; then run `bash skills/coordinate/scripts/teardown-pass_test.sh` and see every case pass.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/unit-removed.sh`, `skills/coordinate/scripts/unit-removed_test.sh`, `skills/coordinate/scripts/archive-common.sh`, `skills/coordinate/scripts/teardown-pass.sh`, `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/check-skill.tsv`, `skills/coordinate/requires.tsv`

### Step 2: a unit is counted once whichever capture sees it first

**Goal**: A capture writes nothing when the coordinator's record already holds a `cost` entry with the same capture key or the same non-null dispatch id, the check and the post run under one host lock both captures take, and the pass's removed mode takes the dispatch id from the removal record, so the pass and a removal never leave two entries for one unit.

**Acceptance Criteria**:

- [ ] Two captures of a unit with the same non-null dispatch id and different capture keys (archives dated on different days) leave one entry, and the second capture's last line is `unit-cost: the record already holds this unit's cost entry`.
- [ ] Two captures with null dispatch ids and different capture keys both write an entry; two with the same capture key and null ids leave one.
- [ ] The pass's capture of a unit followed by a removal of it leaves one entry; a removal's capture followed by the pass's removed mode for the same unit leaves one entry.
- [ ] The pass's removed mode, with a removal record for the instance and an empty coordinator record, writes an entry whose `"niwa.dispatch.id"` is the record's and whose `missing` doesn't name it.
- [ ] A pass capture and a sweep capture with the same dispatch id and different capture keys, held at a barrier inside the lock and released together, leave one entry.

**Check**: Run `bash skills/coordinate/scripts/unit-cost_test.sh` and see the dedupe cases pass, each listing exactly the expected number of `cost` entries for the unit.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost_test.sh`, `skills/coordinate/scripts/archive-common.sh`

### Step 3: failing heads are counted over every head, or marked as a floor

A 65-head pull request gets its full failing-head count, and one whose runs couldn't all be read gets `bound` with the reason in `missing` (#1093).

### Step 4: entries stay off the unit's own pull requests and issues unless the workspace turns them on

On the session store a capture keeps the entry in the coordinator's session unless the repository opts in through #1114's switch, which restores today's placement.

### Step 5: the milestone survives the holding

A dispatch records its Unit on the leg key, and a capture with no Holdings row for the topic takes the milestone from it.

### Step 6: pull requests still open at capture are listed in opened

An open or draft pull request the unit made appears in the entry's new `opened` key, and a closed unmerged one appears in neither list.

### Step 7: kept removals are retried, expired and logged

A removal left pending is finished by a token-bearing sweep started at the end of the teardown pass and at each coordinator wake, under a lock per record, and one pending past 24 hours is listed stale, never dropped.

### Step 8: the reference documents capture after a removal and the workspace's on-reap line

A workspace maintainer reading `references/unit-cost.md` finds capture after a removal, `opened`, the floors, the placement switch, the last lines and the on-reap line to add.

## Implementation Sequence

The steps run in order on one branch. Steps 3, 4 and 6 touch separate parts of
`unit-cost.sh` and could be built beside one another once step 2 has landed, but
each is detailed by the plan's owner only after the step before it reaches its
terminal, so in practice they run one at a time.
