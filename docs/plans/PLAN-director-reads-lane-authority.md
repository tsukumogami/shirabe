---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-director-reads-lane-authority.md
milestone: "Director reads lane authority"
step_count: 5
---

# PLAN: Director reads lane authority

## Status

Active

## Scope Summary

A director reads what a lane it dispatched may do from niwa's authority
answer for that lane, found through niwa's list and lineage and read fresh on
every ask, and a cross-lane move of a lane's active-worker cap is refused by
the name of an authority niwa grants. Both reads go through
`authority-read.sh`, the one reader the settled-steps scoping
(tsukumogami/shirabe#1496) adds, and the skill defines no authority of its
own. The design is `docs/designs/DESIGN-director-reads-lane-authority.md`; the
acceptance criteria every step is checked against are in
`docs/prds/PRD-director-reads-lane-authority.md`.

The work can start on niwa 0.40.0: the lane read uses only what that version
answers, and the cap check refuses every cross-lane move until niwa grants a
cap-change authority. Its dependencies, none assumed shipped:

- the cap-change authority itself, which the workspace authority work's design,
  in progress, will name and grant; until then every cross-lane move is
  refused, which is the intended state;
- tsukumogami/niwa#422, without which a lane's recorded parent can look
  operator-launched, so "the parent is my dispatch" rests on that fix;
- tying a point's settler to the authority level, work that hasn't started, so
  the lane read reports what niwa answers and nothing past it;
- `authority-read.sh` from tsukumogami/shirabe#1496, not yet merged; Step 1
  adds it to that design's interface if it hasn't landed, and the
  settled-steps work then uses that file rather than adding another.

## Decomposition Strategy

Walking skeleton. Step 1 puts the shared pieces in place: the reader and the
ownership test the takeover already applies, moved where the cap check can
call it. Step 2 closes the cap gap end to end, Step 3 adds the lane read,
Step 4 the skill text, and Step 5 runs the PRD's whole-feature checks.
Everything lands in one pull request: the repository prefers one, no split
condition fires, and the text in Step 4 is only true once Steps 2 and 3 exist.

## Steps

### Step 1: the shared reader and the ownership test are in place

**Goal**: `authority-read.sh` exists with the interface and acceptance the
settled-steps design gives it, answers about a session other than the
caller's when given `--session` and `--instance-root`, and the takeover's
ownership test lives in `dispatch-common.sh` with `coordinate-open.sh`
calling it. It closes the PRD criterion One reader for the two new callers.

**Acceptance Criteria**:

- [ ] With a stand-in niwa first on PATH, `authority-read.sh --session <other
  id> --instance-root <other root>` runs one `niwa authority check -C <other
  root> --session <other id> --json` and prints the accepted answer.
- [ ] It prints `skipped`, `timeout`, `failed` or `refused` (exit 3, reason on
  stderr) for no niwa, a read past `NIWA_LOOKUP_SECONDS`, a non-zero exit, and
  a document of another schema or with a value outside niwa's vocabularies.
- [ ] `coordinate-open.sh`'s takeover tests pass unchanged after the ownership
  test moves into `dispatch-common.sh`.
- [ ] If `authority-read.sh` already exists from the settled-steps work, no
  second reader is added and only the missing cases above get tests. If it
  doesn't, `posture-read.sh` and `state-stored-set.sh --rules` move onto it in
  this step, and a search for `niwa authority check` under
  `skills/coordinate/` finds only the reader.

**Check**: Run the reader's test and `coordinate-open.sh`'s existing tests
under `skills/coordinate/scripts/`; every case passes.

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/coordinate-open.sh

**Type**: code

**Complexity**: testable

### Step 2: a cross-lane cap write is refused by the cap-change authority's name

**Goal**: `state-stored-set.sh --run cap` sorts each write into own or
cross-lane with the shared ownership test, leaves an own write untouched with
no read, and for a cross-lane write reads the mover's authority through
`authority-read.sh` and refuses with the fixed refusal and its case word,
writing nothing to the target record. It closes the PRD criteria for the cap
refusal, the failed, timed-out or `not-dispatched` read, the own cap at first
start and on a person's word, the driver-mismatch and no-writer-id cases, and
no niwa on the path.

**Acceptance Criteria**:

- [ ] A cap write to a record whose driver is the caller, or with no driver
  and a coordinator row naming the caller, succeeds and the stand-in niwa's
  log shows no call.
- [ ] A cap write to a record driven by another session, with the stand-in
  answering `bound` and an empty grant, exits non-zero with the `not-held`
  refusal naming the cap-change authority as one niwa grants, and the target
  record's Run section and entries are byte-identical afterward.
- [ ] The same write with the read failing, timing out, answering
  `not-dispatched`, or with no niwa on PATH, is refused with the
  couldn't-be-read refusal and its case word, and the target is unchanged.
- [ ] A cap write with `CLAUDE_CODE_SESSION_ID` unset is refused as
  cross-lane, whether or not the record has a driver.
- [ ] A coordinator's first-start cap write, run through the template's own
  order, succeeds with no read.
- [ ] A search of the changed files finds no literal naming the cap-change
  authority's token, and no rule for who holds it.

**Check**: Run `state-stored-set.sh`'s tests under
`skills/coordinate/scripts/` with the stand-in niwa; every case above passes.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/state-stored-set.sh,
skills/coordinate/koto-templates/coordinate.md

**Type**: code

**Complexity**: critical

### Step 3: a director reads a lane's grant and level from niwa

`lane-read.sh --lane <topic>... [--point <p>]...` finds each lane's path and dispatch id in `niwa list --json` and its session id in `niwa lineage show --json`, reads it through `authority-read.sh`, and prints the answer with `parent_is_mine` and `narrowed_by`, or `cant_tell` with the reason; closes the PRD criteria for the bound read, the changed grant on the next ask, a point's settler, each can't-tell case, a pause row narrowing, the bound plus a second's slack, and two lanes making exactly two `niwa authority check` calls on the stand-in's log.

### Step 4: the skill sends a reader to niwa for lane allowances and the cap rule

The Bounds and Authority text in `SKILL.md` and the template says a director reads a lane's allowances with `lane-read.sh`, never from the lane or the brief, and names the cap-change authority only as something niwa grants; closes the PRD criteria that the skill holds no definition, rule, level rule or grant table for it, and that a search for `niwa authority check` under `skills/coordinate/` finds only the reader.

### Step 5: the whole feature is checked on today's niwa

From a session that is neither the lane nor its dispatcher, on niwa 0.40.0, the lane read returns a bound answer for a real dispatched lane found from niwa's records alone, and a grant changed in the workspace configuration shows on the next ask; closes the PRD's end-to-end criteria for a director and a lane it dispatched.

## Proposed Follow-up

Not filed; proposed under the rule that a finding which doesn't block an
acceptance criterion becomes a step or a follow-up, not a wider design.

- **The skill holds a grant rule for lane coordinators.** The dispatch text in
  `skills/coordinate/koto-templates/coordinate.md` (around line 2833) says "A
  lane coordinator gets none", which decides inside the skill what grant a
  dispatched lane coordinator holds. That is the kind of allowance this
  feature says belongs to the workspace. A follow-up would have the skill
  dispatch a lane coordinator with whatever the workspace's role grants it and
  drop the sentence.
