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
- [ ] The lock is `.post-lock` in the removals directory that step 1's `archive-common.sh` resolves, so the pass and the sweep agree on it. A capture that finds it held by a live process waits for it inside its own list-and-post bounds and then lists again. One whose holder is gone, or older than 60 seconds, is taken over. A removals directory that can't be used leaves the capture posting with only the list check, and one line says so.

**Check**: Run `bash skills/coordinate/scripts/unit-cost_test.sh` and see the dedupe cases pass, each listing exactly the expected number of `cost` entries for the unit.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost_test.sh`, `skills/coordinate/scripts/archive-common.sh`

### Step 3: failing heads are counted over every head, or marked as a floor

**Goal**: The capture reads each head's own runs, oldest head first, through every page of 100 the head holds, and stops after the first green head, so a pull request with many pushes gets every failing head counted; when a head's runs can't all be read, the count is `bound` over the heads read and `missing` names `failing_heads` with the reason (#1093).

**Acceptance Criteria**:

- [ ] A pull request whose 65 heads' runs the stub serves over pages of 100 per head (one head with 250 runs across three pages) gets the full failing-head count, `measured`, and every page of that head is read.
- [ ] With the read budget spent partway (the stub's reads slowed past `UNIT_COST_BUDGET_SECS`), `failing_heads` is `bound` and `missing` holds `{figure: failing_heads, reason: "time limit"}`; a page read that fails gives `read failed`; a page outside its shape gives `invalid input`.
- [ ] The reads stop at the green head: the stub records no runs read for a head after it; with no green head every head is read and the green figures are `not recoverable`.
- [ ] The capture makes no `run list --limit 300` call any more, and every existing green, merge and failing-head case in `unit-cost_test.sh` keeps its expected value.

**Check**: Run `bash skills/coordinate/scripts/unit-cost_test.sh` and see the failing-heads cases pass, the 65-head one counting every failing head.

**Dependencies**: Step 2

**Files**: `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost_test.sh`, `skills/coordinate/scripts/testdata/gh`

### Step 4: entries stay off the unit's own pull requests and issues unless the repository opts in

**Goal**: On the session store a capture keeps the cost entry in the coordinator's session (`record-append.sh --on none`). It restores today's placement on the holding's pull request, else the Unit's issue, only when #1124's reader (`scripts/pr-workflow-content.sh <dir>`, the opt-in #1114 adds) answers `include` for that item's repository, read through one accessor in `unit-cost.sh`.

**Acceptance Criteria**:

- [ ] On the session store with no reader present, and with a stub reader that answers `omit`, exits non-zero, or prints anything else, the capture runs `record-append.sh --on none`, the stub `gh` records no write to any pull request or issue, and the last line is the kept-in-the-session line.
- [ ] With a stub reader that answers `include` for the repository, the capture posts as before: on the holding's pull request, else the Unit's issue, else nowhere.
- [ ] The accessor reads the repository's `CLAUDE.md` from GitHub into a directory of its own and hands that directory to the reader. A failed read of it is omit.
- [ ] A run on a GitHub record still posts on its record issue whatever the reader says.

**Check**: Run `bash skills/coordinate/scripts/unit-cost-on_test.sh` and see the omit cases end with `--on none` and the include case post where it did before.

**Dependencies**: Step 3

**Files**: `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost-on_test.sh`, `skills/coordinate/scripts/testdata/gh`

### Step 5: the milestone survives the holding

**Goal**: A leg-bound dispatch writes its Unit onto the leg key it already keeps in the coordinator's session, and a capture that finds no Holdings row for the topic reads that key, through the unit's own koto request, for the milestone, so a unit retired or removed before its pass still names the milestone it was dispatched for.

**Acceptance Criteria**:

- [ ] A leg-bound dispatch through `dispatch-worker.sh` writes a leg key holding the brief's `unit`; a Unit outside the capture's Unit pattern is left off the key; a re-leg's new key carries the old key's `unit`.
- [ ] A capture with no Holdings row for the topic, whose archived sessions name a request the requesting coordinator's session holds a leg key for with a Unit, writes that milestone `measured`.
- [ ] With a leg key that has no Unit, or one outside the pattern, the milestone is `not recoverable`; with both a Holdings row and a leg key that differ, the row's milestone is written.

**Check**: Run `bash skills/coordinate/scripts/unit-cost_test.sh` and `bash skills/coordinate/scripts/dispatch-worker_test.sh` and see the leg-key milestone cases and the leg key's `unit` cases pass.

**Dependencies**: Step 4

**Files**: `skills/coordinate/scripts/dispatch-worker.sh`, `skills/coordinate/scripts/dispatch-worker_test.sh`, `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost_test.sh`

### Step 6: pull requests still open at capture are listed in opened

**Goal**: Credit's own read of each candidate also keeps one that reads open at capture, drafts included, and meets every credit condition but the merge, in a new entry key `opened` as `{repo, number, via: "session"}`; the holding's Pull request cell, when it reads open, is listed there as `via: "holding"`. `opened` is ordered by number, holds at most 100, follows `pulls`' public-host rule, and a read that fails leaves the candidate in neither list with `missing` naming `opened`.

**Acceptance Criteria**:

- [ ] A unit with a merged, an open, a draft and a closed-unmerged pull request, all from the holding's owner, not from a fork, on a gitBranch or linked within 120 seconds and created after dispatch, lists the merged one in `pulls`, the open one and the draft in `opened`, and the closed one in neither; an open one created before dispatch is in neither. The credit case that expects open pull request 47 to be uncredited now finds it in `opened` and still out of `pulls`.
- [ ] A holding whose Pull request cell names a pull request that reads open lists it in `opened` as `via: "holding"`, read once and never also `via: "session"`; one that reads merged or closed is not in `opened`.
- [ ] 101 open candidates give 100 `opened` entries, the lowest numbers, and `missing` holds `{figure: opened, reason: "entry size"}`; on a public host an open pull request in a repository not read as public is `{repo: "not public"}`.
- [ ] A candidate whose `pr view` fails is in neither list, and `missing` names `opened` with `read failed` (or `time limit` once the budget is spent) as it names `pulls`; a capture with no open pull request writes `opened: []` and adds nothing to `missing`.

**Check**: Run `bash skills/coordinate/scripts/unit-cost_test.sh` and see the `opened` cases pass, the draft and the open pull request listed and the closed one in neither list.

**Dependencies**: Step 5

**Files**: `skills/coordinate/scripts/unit-cost.sh`, `skills/coordinate/scripts/unit-cost_test.sh`, `skills/coordinate/scripts/testdata/gh`

### Step 7: kept removals are retried, expired and logged

A removal left pending is finished by a token-bearing sweep started at the end of the teardown pass and at each coordinator wake, under a lock per record, and one pending past 24 hours is listed stale, never dropped.

### Step 8: the reference documents capture after a removal and the workspace's on-reap line

A workspace maintainer reading `references/unit-cost.md` finds capture after a removal, `opened`, the floors, the placement switch, the last lines and the on-reap line to add.

## Implementation Sequence

The steps run in order on one branch. Steps 3, 4 and 6 touch separate parts of
`unit-cost.sh` and could be built beside one another once step 2 has landed, but
each is detailed by the plan's owner only after the step before it reaches its
terminal, so in practice they run one at a time.
