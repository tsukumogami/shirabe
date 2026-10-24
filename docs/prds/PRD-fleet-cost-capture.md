---
schema: prd/v1
status: In Progress
problem: |
  A coordinator-dispatched unit gets a `unit-cost/1` entry only when the
  coordinator's own teardown pass removes it. Units removed by hand or by a
  reap get none, an entry for a unit already removed carries no dispatch id,
  the milestone is lost with the Holdings row, the session store posts the
  entry on the unit's pull request, and failing heads stop at 300 runs, so the
  fleet's cost per merged pull request by plan shape covers a minority of it.
goals: |
  Every coordinator-dispatched unit gets exactly one entry however niwa removed
  it, with no step run by hand, naming its dispatch id, milestone, plan shape and
  each pull request it opened that merged or is still open; its failing-head
  count is whole or marked as a floor; and by default nothing of it is written
  into the repository it changed.
source_issue: 1093
absorbed:
  - docs/briefs/BRIEF-fleet-cost-capture.md
---

# PRD: Fleet cost capture

## Status

In Progress

Absorbed [BRIEF-fleet-cost-capture](docs/briefs/BRIEF-fleet-cost-capture.md); carried in Absorbed Brief.

Amended after acceptance: the switch that puts cost entries back on a unit's
items is no longer a variable of this feature's own. It is the one switch
#1114 adds for every kind of workflow-tool content in pull requests, read
through one accessor (R11), so a repository turns all of it on or off in one
place.

Amended again after acceptance: a sweep started by niwa's on-reap command has no
GitHub token (niwa refuses credential-shaped names in that command's
environment), and a GitHub call without one would fall back to a stored login.
So a sweep without a token makes no GitHub call at all: it archives and
computes the local figures and leaves the removal pending, and a sweep that
holds the coordinator's own token finishes it (R12a). Records are never dropped
for age; one pending past 24 hours is listed as stale (R12).

## Absorbed Brief

The feature exists because a dispatched unit's cost is captured only when the
coordinator's own teardown pass removes it, and in practice most units leave
another way: a coordinator removes a worker by hand when the pass refuses it,
a person deletes finished sessions and a reap reclaims their instances,
another coordinator reaps its own workers. Those units leave no entry, and
the entries that are written can lose the dispatch id, the milestone and part
of the failing-head count. This document's Problem Statement states that in
full.

The outcome is for the person reading the fleet's cost series across every
coordinator on the host: one entry per dispatched unit however it was removed,
each naming the dispatch id the series joins on, the milestone (or `none`),
the plan shape and every pull request the unit opened, with nobody running a
step for it, and a failing-head count that is whole or says it is a floor. A
reviewer of the repository the unit changed sees none of it by default. The
Goals and User Stories carry that outcome and its journeys: a coordinator's
hand removal after a refused pass, a day's sessions deleted and reaped, the
series read over a week of pull requests, a maintainer reviewing a worker's
pull request, and a 65-push branch whose 17 failing heads must not read as 5.

The boundary holds the capture itself, its placement and its documentation,
and pushes out the series and its join, any koto or niwa change, the other
tool content shirabe writes into pull requests, units no coordinator
dispatched, back-filling, and the land half of a holding with several pull
requests; Requirements and Out of Scope carry each.

## Problem Statement

The coordinate skill writes a unit's `unit-cost/1` entry in one place: its
teardown pass, between the archive and `niwa destroy`
(`skills/coordinate/scripts/teardown-pass.sh`, step 4a). A unit removed any
other way never reaches that step. Coordinators remove workers by hand when the
pass refuses them (a pull request that will never merge) or when they're told
to remove finished sessions in the same pass as the merge; a person deletes
finished sessions in the Agent View and `niwa reap` reclaims their instances;
another coordinator reaps its workers with its own steps. In each case the unit
has no entry, and its pull requests have no record of the milestone or plan
shape they belonged to.

The entries that are written lose what the fleet's series joins on. The
`niwa.dispatch.id` field is read from `niwa list` at teardown, so the pass's
removed mode (for a unit already gone) writes it as null. The milestone is cut
from the Holdings row's Unit, and that row is removed when the unit is retired.
The capture key, `<UTC date>-<topic>-<job id>`, changes with the day and with
the job id, so two captures of one unit aren't recognised as the same. On the
session store the entry is posted as a comment on the unit's pull request, and
a repository's reviewers, who may not use these tools, get coordinator
bookkeeping on their review thread.

The failing-head count reads one `gh run list --limit 300` per pull request. On
a branch with many pushes that covers only the latest heads: a 65-head branch
recorded 5 failing heads where reading every run gives 17, and the entry called
the 5 measured (#1093).

The person computing cost per merged pull request split by plan shape, across
every coordinator on the host, can therefore compute it over only the units the
pass happened to remove, with no way to tell which pull requests are missing.

## Goals

- The fleet series reader finds one entry for every coordinator-dispatched unit,
  whichever niwa step removed it, carrying the dispatch id it joins on, the
  milestone (or `none`), the plan shape and each pull request the unit opened
  that merged or is still open.
- Nobody runs a step for the capture, whether the unit leaves through the
  teardown pass, `niwa destroy` or a reap.
- A failing-head count is either taken over every head or marked as a floor.
- By default no pull request, and no issue the unit opened or worked on,
  carries any of it; a workspace that wants the old placement turns it on.

## User Stories

- As the person computing the fleet's cost series, I want one entry per
  dispatched unit with its dispatch id, milestone, plan shape and pull
  requests, so that I can list every merged pull request of a week under its
  plan shape and see which entries are incomplete instead of guessing.
- As a coordinator whose teardown pass refused a unit, I want the unit's cost
  captured when I remove its instance and session by hand, so that I don't
  run a capture step and the entry still names the milestone the unit was
  dispatched for.
- As the owner deleting finished sessions in the Agent View, I want each unit a
  reap reclaims to get its entry on the record of the coordinator that
  dispatched it, including units no longer in that coordinator's Holdings, so
  that clearing the Agent View doesn't lose cost data.
- As a coordinator whose pass removes a unit it already saw removed, I want the
  second capture to post nothing, so that the series counts the unit once.
- As the series reader comparing rework across units, I want a failing-head
  count over every head of a long branch, or one marked as a floor, so that a
  short count never sits in a sum as a measurement.
- As a maintainer of a repository that adopted shirabe, I want a worker's pull
  request to carry no cost entry, so that the review thread holds the review
  and nothing about tools I don't use.
- As the person who maintains a workspace's configuration, I want one documented
  line to turn removal capture on and one variable to put entries back on pull
  requests, so that I can choose the placement without reading the scripts.

## Terms

- **Unit**: one worker a coordinator dispatched with `niwa dispatch`, identified
  by niwa's dispatch id. A re-dispatch is a new unit.
- **Coordinator-dispatched**: the unit's koto sessions name a koto request (in a
  session's `request-leg.toml`) whose `requested_by` is a session named
  `coordinate-<scope slug>-<UTC stamp>`, the shape every coordinator run's
  session has. A unit with no such request is not coordinator-dispatched.
- **Scope slug**: the `<scope slug>` part of that name; two coordinator runs
  with the same slug drive the same roadmap or discipline.
- **Live run**: a coordinator session koto lists whose current state koto
  reports as not terminal (`koto status`).
- **Head, green, failing**: a pull request's heads are its commits, oldest
  first, as GitHub lists them. A head is green when every workflow run on it,
  each at its final attempt, concluded `success` or `skipped`; failing when any
  attempt of any run on it concluded `failure` or `timed_out`
  (`references/unit-cost.md` as of this change, Green and Failing heads).
- **Dispatch time**: the earliest of the unit's koto request `created_at`, the
  job's `createdAt` and each main transcript's first event, as
  `references/unit-cost.md` defines Dispatch; after a removal the job's is gone
  and the other two remain.
- **Removal**: niwa removing the unit's session and running the workspace's
  on-reap command for it, with `NIWA_REAP_KEY` (the dispatch id),
  `NIWA_SESSION_ID` and `NIWA_INSTANCE_PATH` in its environment.
- **Removal record**: a file the on-reap step writes per removal, named by the
  dispatch id, under `${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals/`,
  holding the dispatch id, session id, instance path and `removed_at`.
- **Record**: the coordinator's own record: its koto session on the session
  store, and on a GitHub record the issue the coordinator created to hold it.
  Neither is a pull request or issue the unit opened or worked on.
- **Credit's conditions**: a pull request counts as the unit's when (1) its base
  repository's owner is the holding repository's owner, (2) its head repository
  has the same owner (not a fork), (3) it was created at or after dispatch, and
  (4) its head branch is a `gitBranch` some line of the unit's transcripts
  carries, or a `pr-link` record for it is within 120 seconds of its creation
  (`skills/coordinate/references/unit-cost.md`, Credit).
- **Floor**: a figure in state `bound`, a lower bound and never the figure.

## Requirements

### Functional

- **R1. Capture on removal.** The on-reap step, run for a coordinator-dispatched
  unit, leads to that unit's `unit-cost/1` entry with no further command run by
  anyone. niwa runs the step at `niwa destroy`, `niwa reap` and the reaps
  `niwa dispatch`, `niwa create` and `niwa watch` run first; this feature relies
  on that and tests the step under niwa's documented environment.
- **R2. Same figures as the pass.** A capture after a removal computes every
  figure by the definitions in `skills/coordinate/references/unit-cost.md`, from
  the Claude Code project directories of the instance path, the koto sessions
  whose execution directory was at or under it, and the unit's koto request. A
  figure whose source is gone (the job's `state.json` always; a pruned
  transcript or koto session) is `not recoverable` with reason `no source`, and
  the capture still writes the entry.
- **R3. The dispatching coordinator's record.** The entry goes to the record of
  the run named by `requested_by` while that run is live. When it has ended, it
  goes to the one live run with the same scope slug. When the unit's sessions
  name several coordinator requests, the earliest by `created_at` is the
  dispatch's, as Dispatch time reads it. With none, or with
  several, nothing is written and the removal record is kept with reason `no
  coordinator` or `several coordinators`.
- **R4. Dispatch id on every entry.** The pass's normal mode reads
  `"niwa.dispatch.id"` from `niwa list`, as today, and also reads the removal
  record for the instance path when one exists; when both exist and differ,
  `niwa list`'s wins and the capture prints one line naming both before its
  last line. The pass's removed mode and a capture after a removal never read
  `niwa list`: they take the removal record's dispatch id. With neither it stays
  null with `missing` naming it, `no source`.
- **R5. One entry per unit.** A capture writes nothing when the record already
  holds a `cost` entry with the same capture key, or with the same non-null
  `"niwa.dispatch.id"`; a null id never matches, and two entries with the same
  key match whatever their ids. This holds in both orders: the pass's capture
  then a removal's, and a removal's then the pass's removed mode. The check and
  the write run under one host lock that the pass's capture and the sweep both
  take, so two captures of one unit that overlap leave one entry.
- **R6. Milestone.** Read from the Holdings row whose Worker is the topic; when
  no row names it, from the Unit the coordinator recorded for the dispatch when
  it dispatched it (R6a). The row wins when both exist. With neither, `not
  recoverable`, `no source`.
- **R6a. The Unit recorded at dispatch.** When the coordinator opens a request
  leg for a dispatch, the leg key it already writes in its own session
  (`legs/<request>/<leg>`, from `dispatch-common.sh`'s `dc_leg_put`) also holds
  the dispatch's Unit, as the Holdings row would carry it, matched to the
  capture's Unit pattern. A capture finds the key through the unit's koto
  request id. A message-path dispatch opens no leg and records no Unit.
- **R7. Every pull request the unit opened.** `pulls` keeps its meaning: merged
  pull requests meeting credit's conditions, `via` `holding` or `session`. A new
  key, `opened`, lists each pull request meeting conditions 1 to 4 that is open
  at capture, drafts included, as `{repo, number, via}`. A pull request read as
  merged goes in `pulls` only; one closed without merging goes in neither.
  `opened` holds at most 100 objects (beyond that `missing` names `opened`,
  `entry size`) and follows `pulls`' public-host rule (`{repo: "not public"}`).
  A candidate whose state can't be read is in neither list, and `missing` names
  `opened` with the read's reason, as `pulls` does today.
- **R8. Plan shape.** Same definition and source (the unit's koto sessions) for
  a capture after a removal; with no session left, `not recoverable`, `no
  source`.
- **R9. Failing heads over every head.** Each of the unit's pull requests'
  heads is read, oldest first, until its first green head, however many runs the
  branch holds; with no green head, every head is read. Failing heads count the
  failing heads read up to and including the green head. When a head's runs
  aren't read whole, the count is `bound` over the heads read and `missing`
  names `failing_heads` with the reason: `time limit` when the capture's
  90-second read budget ran out, `read failed` when a read failed or was cut at
  its own 8-second bound (`UNIT_COST_FETCH_SECS`), `invalid input` when a read's
  output was outside its shape.
- **R10. Off the unit's items by default.** With the switch at omit, a
  session-store capture writes the entry to the coordinator's session only
  (`record-append.sh --on none`); a GitHub-record capture posts it on the
  coordinator's record issue, as today. With the switch at include, a
  session-store capture posts as today: the holding's pull request, else the
  Unit's issue, else nowhere.
- **R11. The switch.** The capture reads the switch through one accessor in
  `unit-cost.sh`, for the repository of the holding's pull request, when it
  chooses where to post. The switch is #1114's opt-in for workflow-tool content
  in pull requests; until #1114's reader exists the accessor answers omit, and
  when it exists the accessor calls it and nothing else changes. The accessor
  answers include only when the reader says include; a missing reader, a failed
  read, or any other answer is omit. This feature adds no setting of its own.
- **R12. Retry.** A removal record whose capture wrote no entry (`pending
  github`, `no coordinator`, `several coordinators`, a failed record read, a
  failed post) is kept, and every later sweep tries it again. A record whose
  unit another capture has recorded in the meantime is deleted without a capture
  (R5). A written entry deletes its record. No record is deleted for its age:
  one still pending 24 hours after `removed_at` is listed by every sweep as
  `stale`, in its log and on its output, so a person sees it.
- **R12a. Who finishes a capture.** A sweep with `GH_TOKEN` unset or empty makes
  no GitHub call: it archives what survives, computes the figures that need no
  GitHub read, keeps the record with the outcome `pending github`, and posts
  nothing; its `gh` calls, when it has a token, run with `GH_CONFIG_DIR` an
  empty directory, so no stored login is ever used. A sweep with the token
  finishes every pending record. Two places start one, each detached and never
  inside a koto action or gate: the end of the teardown pass, and the
  coordinator's wait guidance, which starts `unit-removed.sh sweep` in the
  background at each wake. Each finished entry goes to the record the unit's
  dispatch named (R3), never to the sweeping coordinator's own unless it is that
  one.
- **R13. Nothing on the unit's items.** With the setting off, no part of this
  feature writes to a pull request or an issue the unit opened or worked on:
  every write of an entry goes through `record-append.sh`, with `--on none` on
  the session store and on a GitHub record to the coordinator's own record
  issue, and no script this feature adds or changes runs any other `gh` write.
- **R14. Last lines and log.** A capture's last stderr line is one of:
  `unit-cost: kept the cost entry in the session`, `unit-cost: posted the cost
  entry on
  <owner/repo#n>`, `unit-cost: the record already holds this unit's cost entry`,
  `unit-cost: the post failed (record-append exit <n>)`, `unit-cost: the post did
  not finish in time`, `unit-cost: the entry could not be computed`. The sweep
  appends to `removals.log` beside the removal records one line per record it
  handles, `<UTC time> <dispatch id> <outcome>`, the outcome one of `captured`
  (the first two last lines), `already recorded`, `post failed` (the next
  two), `read failed` (the record couldn't be read or the entry not computed),
  `timed out` (the capture was stopped at 120 seconds), `no coordinator`,
  `several coordinators`, `pending github` (R12a), `invalid input` (a removal
  record whose fields fail their patterns, deleted). A record still kept 24
  hours after its removal gets one more line, `stale` (R12). The post's own
  25-second bound is `post failed`; `timed out` is only the whole capture
  stopped at 120 seconds.

### Non-functional

- **R15. Never in niwa's way.** The on-reap step writes the removal record,
  starts the sweep in the background and exits 0 without waiting for it. It
  exits 0 also when it records nothing (no reap key, a key equal to the session
  id, an unwritable state directory), printing one line why. The sweep's capture
  of one unit is bounded as the pass's: reads not taken within 90 seconds are
  `time limit` and the entry is written with the rest; a capture still running
  at 120 seconds is stopped, writes nothing, and its record is kept (`timed
  out`). A sweep re-reads the directory before it releases its lock and handles
  any record added since, so the entry for every recorded removal exists, or its
  record is kept with an outcome, when the last sweep exits.
- **R16. One capture per record.** A sweep takes a lock per pending record
  before it captures it, so two sweeps on one host (two coordinators waking
  together, or a pass and a wake) never capture or post one record twice; a
  record whose lock is held is passed over by the other sweep. A lock left by a
  sweep that died is taken over once its holder's pid is gone or it is older
  than the capture's 120-second bound plus a minute for the archive before
  it. A sweep with nothing pending does nothing.
- **R17. Untrusted input.** The removal record, the koto request and the
  archive are read under today's capture rules: only numbers, ids, timestamps
  and closed-set words are kept, each matched to its shape (`unit-cost.sh`'s
  repository, number, sha, branch and dispatch-id patterns), and only those
  matched values reach a command. A figure read from a value that fails its
  shape is `not recoverable`, `invalid input`; a removal record whose dispatch
  id, session id or instance path fails its pattern is deleted with the log
  outcome `invalid input` and no capture.
- **R18. Compatible entries.** The schema stays `unit-cost/1`: every existing
  field keeps its name, type and meaning, and `opened` is the one new key.
- **R19. Documented.** `skills/coordinate/references/unit-cost.md` has a section
  headed `## Capture after a removal` (the removal record, the sweep, the coordinator
  rule, retry), and documents `opened`, the floor reasons for failing heads, the
  switch and where it is set (#1114), and the last lines of R14. A guide
  shows the on-reap line a workspace adds, alone and combined with another
  on-reap command.

## Acceptance Criteria

Each criterion names the requirements it verifies. Suites run with stubbed
`gh`, `koto`, `niwa` and `claude`, as today's do.

- [ ] (R1, R2, R8) The on-reap step, given a reap key that is a dispatch id, an
  instance path that no longer exists, transcripts under the stub Claude home
  and a koto `work-on` session whose execution directory was in the instance,
  leads to one `cost` entry in the dispatching coordinator's session with
  measured worker tokens, the session's per-state times, the plan shape,
  `dispatch` from the koto request, and job-state figures `not recoverable`,
  `no source`.
- [ ] (R2) With the transcripts removed as well, the entry is still written,
  with token figures `not recoverable`, `no source`.
- [ ] (R15) The step exits 0 after writing the removal record while a stub
  sweep blocked on a fifo is still running (the test reads the record, then
  releases the fifo); with no reap key, with a reap key equal to the session id,
  and with an unwritable state directory it writes no record, prints one line,
  and exits 0.
- [ ] (R3) With `requested_by` live, the entry goes to it. With it ended and one
  live run of the same scope slug, to that run. With none, no entry, the record
  kept, the log outcome `no coordinator`; with two, `several coordinators`. A
  unit whose sessions name no coordinator request gets `no coordinator` and the
  7-day rule.
- [ ] (R3, R6) A unit absent from the coordinator's Holdings, with its Unit
  recorded at dispatch, gets its entry with that milestone `measured`.
- [ ] (R6) With both a Holdings row and a dispatch-time Unit that differ, the
  row's milestone is written; with neither, `not recoverable`, `no source`.
- [ ] (R4) The pass's normal mode writes `niwa list`'s dispatch id; with a
  removal record for the instance holding a different id, it still writes `niwa
  list`'s and prints a line naming both; its removed mode with a removal record
  writes the record's id and the stub `niwa` records no `list` call; with
  neither, null and `missing` names `niwa.dispatch.id`, `no source`.
- [ ] (R6a) A leg-bound dispatch through `dispatch-worker.sh` writes a leg key
  holding the dispatch's Unit; a message-path dispatch writes none; a Unit
  outside the pattern is not written.
- [ ] (R5) The pass's capture then a removal of the same unit leaves one entry
  and the second capture's last line is the already-recorded line; a removal's
  capture then the pass's removed mode leaves one entry the same way; two
  captures with null dispatch ids and different keys both write; two with the
  same key and null ids leave one; a pass capture and a sweep capture of one unit
  held at a barrier inside the lock, then released together, leave one entry.
- [ ] (R7) A unit with a merged, an open, a draft and a closed-unmerged pull
  request (all meeting conditions 1, 2 and 4, created after dispatch) lists the
  merged one in `pulls`, the open and the draft in `opened`, and the closed one
  in neither; one created before dispatch is in neither. The case in
  `unit-cost_test.sh` that expects open pull request 47 to be uncredited now
  expects it in `opened` and still out of `pulls`.
- [ ] (R7) 101 open candidates give 100 `opened` entries and `missing` naming
  `opened`, `entry size`; on a public host an open pull request in a private
  repository is `{repo: "not public"}`.
- [ ] (R9) A pull request whose 65 heads' runs the stub serves over four pages
  gives the full failing-head count `measured`; the same with the budget spent
  after two pages gives `bound` and `missing` `failing_heads`, `time limit`; a
  failed page read gives `read failed`; a page outside its shape gives `invalid
  input`; reads stop at the green head (the stub records no read for a later
  head); with no green head every head is read and green is `not recoverable`;
  a pull request with fewer than 100 runs gives the count today's suite expects.
- [ ] (R10, R11, R13) On the session store with no reader, with a stub reader
  that answers omit, fails, or prints something else, the capture runs
  `record-append.sh --on none` and the stub `gh` records no write call; with a
  stub reader that answers include, it runs `--on <the holding's pull request>`,
  with no pull request `--on <the Unit's issue>`, else `--on none`; a
  GitHub-record run posts on its record issue in each case. Each case's
  last stderr line is the R14 line for where the entry went.
- [ ] (R15) A capture whose stub GitHub read hangs ends its reads at the budget
  with those figures `time limit` and still writes the entry; one whose stub
  post hangs past 120 seconds is stopped, writes nothing, and its record is kept
  with the log outcome `timed out` (the suite shortens both bounds through their
  variables).
- [ ] (R12, R14) A record kept for `no coordinator` is captured at the next
  removal once a coordinator is live; kept after a failed record read or a
  failed post, it is captured at the next removal; one whose unit already has an
  entry is deleted with no capture; one with `removed_at` 25 hours old and
  still pending is kept and listed `stale`. Each handled record adds one
  `removals.log` line with its outcome.
- [ ] (R12a) With `GH_TOKEN` unset, a sweep archives, keeps the record `pending
  github`, and the stub `gh` records no call and `record-append.sh` no post;
  with a token, a later sweep posts the entry to the record the dispatch named
  and deletes the record.
- [ ] (R16) Two sweeps started together over one pending record post one
  entry; a record lock left by a killed sweep whose pid is gone is taken over and
  the capture runs; a sweep with no pending record makes no call.
- [ ] (R17) A removal record, request and archive carrying shell metacharacters
  in the repository, number, sha, branch and dispatch id, and a non-numeric
  figure, produce no command with those values (the stubs record every argument),
  the figures they feed `not recoverable`, `invalid input`, and a removal record
  with a bad dispatch id deleted with the log outcome `invalid input`.
- [ ] (R18) Every key of an entry the pass captures from the suite's fixture,
  before and after this change, other than `opened`, has the same name and JSON
  type.
- [ ] (R14, R19) `references/unit-cost.md` contains the heading `## Capture
  after a removal`, the strings `#1114`, `opened` and
  `removals.log`, and each last line of R14; the guide contains the
  on-reap line and a combined example.
- [ ] (R1-R19) `unit-cost_test.sh`, `unit-cost-on_test.sh`,
  `teardown-pass_test.sh` and `teardown-pass_engine_test.sh` pass; the only
  existing cases whose expectations change are the ones R7, R9 and R10 name
  above.

## Out of Scope

- The fleet's cost series and its join over coordinator records: it reads what
  this writes.
- Any change to koto or niwa; the on-reap command and the reap key are used as
  niwa ships them.
- Changing the workspace configuration itself: turning removal capture on is
  one entry in the workspace's on-reap command, documented here and made where
  the workspace's configuration lives.
- Other tool content in pull requests (the Review panel table, handoff
  comments, verification notes), which #1114 makes opt-in.
- Units no coordinator dispatched, such as a session a person started by hand.
- Back-filling entries for units removed before this lands.
- A holding that tracks several pull requests through the land step (the land
  half of #712).
- Removals niwa doesn't see: an instance deleted while its session is never
  deleted is captured only when niwa reaps the session.
- A shared or cloud koto session store, and removals on another host: the
  capture reads this host's stores, as the pass does.

## Known Limitations

- Capture after a removal depends on the workspace's on-reap command running
  this step. A workspace that doesn't declare it gets today's behaviour: entries
  only from the pass.
- A removal capture reads transcripts from Claude Code's `projects/` directory,
  which Claude Code may prune on its own schedule; a unit whose transcripts are gone gets its
  token figures `not recoverable`.
- koto keeps a worker's sessions while any session in its dispatch hierarchy is
  alive and for a retention period after; a removal captured after that loses
  its per-state times and plan shape.
- The milestone recorded at dispatch is read only for units dispatched after
  this lands; an earlier unit whose Holdings row is gone still gets `not
  recoverable`.
- A unit with no coordinator request (a person's own dispatch) is kept as `no
  coordinator` and listed `stale` after 24 hours, since a removal can't tell it
  from a coordinator dispatch whose coordinator hasn't started yet; someone
  removes such a record by hand.
- A removal's entry waits for a sweep that holds a token: until a teardown pass
  ends or a coordinator wakes on the host, it is `pending github`.
- An entry is written once. A pull request open at capture is listed in
  `opened` and never moved to `pulls`; a reader joins its later merge on its
  number.
- A floor is not a measurement: a reader summing failing heads leaves `bound`
  values out, or reports the sum as a floor.

## Decisions and Trade-offs

- **Trigger on niwa's removal, not on the coordinator's loop.** A sweep inside
  the coordinator's loop would catch only that coordinator's units and only when
  its loop runs; units removed by a person, by another coordinator, or while the
  coordinator is stopped would wait or be missed. niwa runs one workspace command
  for every session it removes, with the dispatch id, which is every path the
  brief names. The cost is a dependency on the workspace declaring it (Known
  Limitations).
- **Detached capture.** niwa bounds an on-reap run to its timeout (10 seconds by
  default) inside a 30-second budget for the whole step, and a capture takes up
  to 120. The on-reap step records the removal and starts the capture without
  waiting; niwa kills a run's process group only on timeout, so a capture
  started in the background outlives the step.
- **One entry per unit by dispatch id.** The capture key changes with the day
  and the job id; the dispatch id is niwa's own per-dispatch identity, so it is
  what "the same unit" means. A re-dispatch under a new dispatch is a new unit.
- **`opened` beside `pulls`, not inside it.** Adding open pull requests to
  `pulls` would give `merged_at` and `merge_commit` a null value, changing their
  type for every reader. A separate key keeps `pulls` exactly as readers expect.
- **The issue fallback goes off with the pull request.** The owner ruled pull
  requests out by default; an issue comment on the unit's issue puts the same
  bookkeeping in front of the same maintainers, so the default keeps the entry
  in the coordinator's session and the switch restores both. The coordinator's
  own record issue is its container, not the unit's, and keeps its entries.
- **Ambiguous coordinator, no entry.** Writing to one of several live runs of a
  scope would put the entry on a record its reader may not read; keeping the
  record and retrying until one run is live keeps the entry where the series
  looks.
- **Floors use the existing `bound` state.** The schema already defines `bound`
  as a lower bound, and the brief requires no new state word; the `missing`
  entry names the figure so `complete` reads false.
