---
schema: prd/v1
status: Draft
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
  every pull request it opened; its failing-head count is whole or marked as a
  floor; and by default nothing of it is written into the repository it changed.
upstream: docs/briefs/BRIEF-fleet-cost-capture.md
source_issue: 1093
---

# PRD: Fleet cost capture

## Status

Draft

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
  milestone (or `none`), the plan shape and every pull request the unit opened.
- Nobody runs a step for the capture, whether the unit leaves through the
  teardown pass, `niwa destroy` or a reap.
- A failing-head count is either taken over every head or marked as a floor.
- By default no pull request, and no issue in the repository the unit changed,
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
  dispatched it, including units already taken off that coordinator's list of
  live workers, so that clearing the Agent View doesn't lose cost data.
- As a coordinator whose pass removes a unit it already saw removed, I want the
  second capture to post nothing, so that the series counts the unit once.
- As the series reader comparing rework across units, I want a failing-head
  count over every head of a long branch, or one marked as a floor, so that a
  short count never sits in a sum as a measurement.
- As a maintainer of a repository that adopted shirabe, I want a worker's pull
  request to carry no cost entry, so that the review thread holds the review
  and nothing about tools I don't use.

## Requirements

### Functional

- **R1. Capture on every niwa removal.** When niwa removes a session it
  dispatched (the session's reap key is a dispatch id) through any step that
  runs the workspace's on-reap command (`niwa destroy`, `niwa reap`, and the
  reaps `niwa dispatch`, `niwa create` and `niwa watch` run first), the unit
  gets a `unit-cost/1` entry, with no step run by hand.
- **R2. Same figures as the pass.** An entry captured after a removal computes
  every figure by the definitions in `skills/coordinate/references/unit-cost.md`
  from what survives on the host: the Claude Code project directories of the
  instance, the koto sessions whose execution directory was in the instance, and
  the unit's koto request. Figures whose source went with the removal (the job's
  `state.json`) are `not recoverable` with reason `no source`, as in the pass's
  removed mode.
- **R3. The dispatching coordinator's record.** The entry is written to the
  record of the coordinator that dispatched the unit: the session the unit's
  koto request names as `requested_by`, or, when that run has ended, the live
  coordinator run of the same scope. With neither, nothing is written and the
  removal's log says why; a later removal or capture tries again (R12).
- **R4. Dispatch id on every entry.** Every entry for a unit niwa dispatched
  carries its `"niwa.dispatch.id"`: from `niwa list` when the pass sees the
  instance, else from the removal's reap key. The pass's removed mode takes it
  from the removal's record when niwa no longer lists the instance.
- **R5. One entry per unit.** A capture posts nothing when the record already
  holds a `cost` entry with the same capture key or the same
  `"niwa.dispatch.id"`. This holds in both orders: the pass then a removal, and
  a removal then the pass's removed mode.
- **R6. Milestone without the Holdings row.** The milestone is read from the
  Holdings row whose Worker is the topic; when no row names the topic, from the
  Unit recorded for the dispatch at dispatch time. With neither, it is `not
  recoverable` with reason `no source`.
- **R7. Every pull request the unit opened.** `pulls` keeps its meaning (merged
  pull requests, `via` `holding` or `session`). A new list, `opened`, holds each
  pull request that meets credit's conditions 1, 2 and 4 and was created at or
  after dispatch but is open at capture (drafts included), as `{repo, number,
  via}`; a closed, unmerged pull request is in neither list. `opened` follows
  `pulls`' limits (100 entries, the `entry size` reason) and its public-host
  rule (`{repo: "not public"}`).
- **R8. Plan shape.** The plan shape keeps its definition and its source, the
  unit's koto sessions, for a capture after a removal as in the pass.
- **R9. Failing heads over every head.** Failing heads are counted from the runs
  of every head of each of the unit's pull requests, up to and including the
  green head, however many runs the branch holds. When the capture can't read
  every head's runs (its time ran out, a read failed or was cut at its bound),
  `failing_heads` is `bound` with the count over the heads it read, and
  `missing` names `failing_heads` with that read's reason.
- **R10. Off the repository by default.** With the workspace setting off (the
  default), no capture writes into a pull request or an issue of the repository
  the unit changed: on the session store the entry is kept in the coordinator's
  session (`record-append.sh --on none`); a run on a GitHub record still posts
  on its record issue. With the setting on, the session store posts as today
  (the holding's pull request, else the Unit's issue, else nowhere).
- **R11. The setting.** The workspace turns the placement on with one variable
  in its configuration's environment, read at capture; any value but the one
  documented on-value is off. The capture's last stderr line says where the
  entry went.
- **R12. Retry.** A removal whose capture didn't write an entry (no coordinator
  found, a failed read of the record, the post failed) is kept and tried again
  at each later removal on the host, until it is written or 7 days have passed
  since the removal, after which it is dropped with one log line.
- **R13. Nothing in pull requests.** No part of this feature writes into a pull
  request's title, body, comments or commits, with the setting off.

### Non-functional

- **R14. Never in niwa's way.** The step niwa runs at a removal returns within 2
  seconds, exits 0 whenever it recorded the removal, and never changes the
  outcome of the niwa step that ran it; the capture itself runs after it
  returns, bounded as the pass's capture is (its reads within 90 seconds, the
  whole within 120).
- **R15. One capture at a time.** Two removals at once never run two captures
  of one unit at the same time, and a capture that dies leaves nothing that
  blocks the next one for longer than its bound.
- **R16. Untrusted input.** A capture after a removal reads the archive, the
  removal record and the koto request under the same rules as today's capture:
  only numbers, ids, timestamps and closed-set words are kept, each matched to
  its shape, and no value from them reaches a command except a matched
  repository, number, sha or dispatch id.
- **R17. Compatible entries.** The schema stays `unit-cost/1`. Every existing
  field keeps its name, type and meaning; `opened` is a new key, and a reader
  that doesn't know it ignores it.
- **R18. Documented.** `skills/coordinate/references/unit-cost.md` says how an
  entry is captured after a removal, how the dispatch id, milestone and `opened`
  are read, how a floor is marked, and where entries go with the setting off and
  on; a guide says what a workspace adds to its configuration to turn removal
  capture on and how it combines with another on-reap step.

## Acceptance Criteria

- [ ] A suite removes a stubbed coordinator-dispatched unit through the on-reap
  entry (reap key a dispatch id, the instance gone, transcripts and koto sessions
  left) and ends with one `cost` entry on the dispatching coordinator's session
  carrying measured token figures, the per-state times, the plan shape and the
  dispatch id equal to the reap key, with no other command run between.
- [ ] The on-reap entry returns in under 2 seconds with exit 0 when it recorded
  the removal, while the capture it started is still running; with no reap key,
  or a reap key equal to the session id, it records nothing and exits 0.
- [ ] Given a removal whose `requested_by` session has ended and a live
  coordinator of the same scope, the entry is written to the live one; with no
  live coordinator of that scope, no entry is written, the log says `no
  coordinator`, and a second removal after a coordinator starts writes it.
- [ ] The pass's capture followed by a removal of the same unit leaves one
  entry; a removal's capture followed by the pass's removed mode for the same
  unit leaves one entry; each second capture's last stderr line says the record
  already holds the unit's entry.
- [ ] The pass's removed mode, with a removal record for the instance, writes
  `"niwa.dispatch.id"` from it and no `missing` entry for it.
- [ ] A capture with no Holdings row for the topic and a Unit recorded at
  dispatch writes that milestone, `state: measured`; with neither it writes `not
  recoverable`, `no source`.
- [ ] A unit with one merged and one open pull request (both on its branch,
  created after dispatch) lists the merged one in `pulls` and the open one in
  `opened`; a closed unmerged pull request appears in neither, and the pinned
  open-pull-request test case moves from absent to `opened`.
- [ ] A pull request with 65 heads whose runs span four pages is counted over
  every head (the suite's stub serves the pages), giving the full count `measured`;
  with the budget spent after two pages, `failing_heads` is `bound` and `missing`
  names `failing_heads`, `time limit`.
- [ ] On the session store with the setting unset, the capture calls
  `record-append.sh --on none` and no `gh` write to any pull request or issue is
  made; with the setting on, it calls `--on <the holding's pull request>` as
  today; a GitHub-store run posts on its record issue either way.
- [ ] Two removals of the same unit started together produce one capture run
  and one entry.
- [ ] A removal record older than 7 days is dropped at the next sweep with one
  log line and no capture.
- [ ] A grep of the change's non-test scripts finds no `gh pr comment`, `gh pr
  edit`, `gh issue comment` or `gh api` write call, and the only posting call is
  `record-append.sh`.
- [ ] The existing `unit-cost_test.sh`, `unit-cost-on_test.sh`,
  `teardown-pass_test.sh` and `teardown-pass_engine_test.sh` suites pass, with
  only the cases R7, R9 and R10 change edited, each edit named in the pull
  request.
- [ ] `references/unit-cost.md` documents removal capture, `opened`, the floor
  marking and the setting, and the guide shows the configuration a workspace adds.

## Out of Scope

- The fleet's cost series and its join over coordinator records: it reads what
  this writes.
- Any change to koto or niwa; the on-reap command and the reap key are used as
  niwa ships them.
- Changing the workspace configuration itself: turning removal capture on is one
  entry in the workspace's on-reap command, documented here and made where the
  workspace's configuration lives.
- Other tool content in pull requests (the Review panel table, handoff comments,
  verification notes), which #1114 makes opt-in.
- Units no coordinator dispatched, such as a session a person started by hand.
- Back-filling entries for units removed before this lands.
- A holding that tracks several pull requests through the land step (the land
  half of #712).
- Removals niwa doesn't see: an instance deleted while its session is never
  deleted is captured only when niwa reaps the session.

## Known Limitations

- Capture after a removal depends on the workspace's on-reap command running
  this step. A workspace that doesn't declare it gets today's behaviour: entries
  only from the pass.
- A removal capture reads transcripts from `~/.claude/projects/`, which Claude
  Code may prune on its own schedule; a unit whose transcripts are gone gets its
  token figures `not recoverable`.
- koto keeps a worker's sessions while any session in its dispatch hierarchy is
  alive and for a retention period after; a removal captured after that loses its
  per-state times and plan shape.
- The milestone recorded at dispatch is read only for units dispatched after this
  lands; an earlier unit whose Holdings row is gone still gets `not recoverable`.

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
  waiting; niwa kills a run's process group only on timeout, so a capture started
  in the background outlives the step.
- **One entry per unit by dispatch id.** The capture key changes with the day and
  the job id; the dispatch id is niwa's own per-dispatch identity, so it is what
  "the same unit" means. A re-dispatch under a new dispatch is a new unit.
- **`opened` beside `pulls`, not inside it.** Adding open pull requests to `pulls`
  would give `merged_at` and `merge_commit` a null value, changing their type for
  every reader. A separate key keeps `pulls` exactly as readers expect.
- **The issue fallback goes off with the pull request.** The owner ruled pull
  requests out by default; an issue comment in the same repository puts the same
  bookkeeping in front of the same maintainers, so the default keeps the entry in
  the coordinator's session and the setting restores both.
- **Floors use the existing `bound` state.** The schema already defines `bound`
  as a lower bound, and the brief requires no new state word; the `missing` entry
  names the figure so `complete` reads false.
