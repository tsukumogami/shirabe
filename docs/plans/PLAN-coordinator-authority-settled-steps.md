---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Hard Constraint. The build waits on workspace authority work niwa hasn't
  shipped, in another repository, so it can't land with these documents.
  The documents merge first, and each step lands later as its own pull
  request once that niwa work is released.
tracking_level: none
upstream: docs/designs/DESIGN-coordinator-authority-settled-steps.md
milestone: "Coordinator authority-settled steps"
step_count: 6
---

# PLAN: Coordinator authority-settled steps

## Status

Active

## Scope Summary

The coordinate skill stops deciding who settles a merge, close, release or
handed-back step from a start-time copy and its own bound-or-root rule. Each of
those steps runs one check action, `settle-check.sh`, that reads the step's
point fresh through one reader, `authority-read.sh`, and takes, routes or holds
the step on what the answer says. Teardown and the always-expected review keep
today's sources. The design is
`docs/designs/DESIGN-coordinator-authority-settled-steps.md`; the acceptance
criteria every step is checked against are in
`docs/prds/PRD-coordinator-authority-settled-steps.md`.

**The work doesn't start yet.** It waits on workspace authority work niwa
hasn't shipped, and builds nothing around its absence:

- a per-point declaration that a step needs review, shown in the answer;
- a per-point answer for a root session, without which every root
  coordinator's finishing step would hold;
- an addressable target for a step the answer sends to the dispatcher or keeps
  from the author;
- tsukumogami/niwa#422, the separate dispatch bug that lets a grantless session
  dispatch a granted child.

Two more dependencies don't block a start, because the skill keeps today's
source until they land: a teardown point in the answer, and where a review goes
when the answer names the session as settler.

## Decomposition Strategy

The reader first, then a walking skeleton, in the design's three phases.
Step 1 is the first phase on its own: the one reader, `authority-read.sh`,
with `posture-read.sh` and `state-stored-set.sh --rules` moved onto it and
their output unchanged. It changes no routing, so the reader is proved
before any step depends on it. Steps 2 and 3 are the second phase. Step 2
crosses the whole path for one step, the merge at `land`: the verdict, the
evidence key and the transition that follows the sealed token, all against a
fake `niwa` first on PATH. Step 3 adds the merge's second read and the
forged-record and mid-run suites. Steps 4 to 6 are the third phase: the
verdict, reopen and roadmap-close states, the handed-back steps, then the fold
table, `posture_ask` and the skill text.

None of it lands with this plan: the plan merges ahead of its build, and each
step lands later in its own pull request, after the steps it depends on,
once the niwa work above ships. Step 1 is the first of those pull requests.

## Steps

### Step 1: one reader answers every authority read the skill makes

**Goal**: `authority-read.sh` becomes the only code under `skills/coordinate/`
that runs `niwa authority check`, and `posture-read.sh` and
`state-stored-set.sh --rules` call it in place of their own calls, printing
and storing what they do today. No step's routing changes. It closes the PRD
criterion One reader, and the reader's half of Refused answers and Holds.

**Acceptance Criteria**:

- [ ] With a fake niwa giving an accepted answer, `authority-read.sh
  --session <id> --point merge-pr` prints the answer as JSON and exits 0.
- [ ] With no niwa on PATH and no executable `$NIWA_BIN`, no session id, or no
  instance root it prints `skipped`; a read past `NIWA_LOOKUP_SECONDS` prints
  `timeout`; a non-zero exit prints `failed`; an unknown schema, or a `state`,
  `decider`, `author_exclusion`, `level` or grant value outside the
  vocabularies `posture-read.sh` accepts today, prints `refused`. Each gives
  its reason on stderr.
- [ ] Asked with no `--point`, it accepts an answer that has no `points`
  entry, as the `--rules` read needs.
- [ ] Against the same fake niwa fixtures, `posture-read.sh` and
  `state-stored-set.sh --rules` print the same output and write the same
  `coord/posture.json` before and after the change; a test that pins the old
  call's argument order is updated to the reader's call, and no assertion on
  output changes.
- [ ] A search finds `niwa authority check` run from exactly one script under
  `skills/coordinate/`, `authority-read.sh`.

**Check**: Run the new `authority-read` test and the existing
`posture-read_test.sh` and `state-stored-set_test.sh` under
`skills/coordinate/scripts/` against the fake niwa fixtures; every case
passes, the before-and-after output comparison is empty, and the search lists
`authority-read.sh` alone.

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/posture-read.sh,
skills/coordinate/scripts/state-stored-set.sh

**Type**: code

**Complexity**: testable

### Step 2: a merge at land is taken, routed or held by a fresh authority read

**Goal**: `land` decides the merge from one read of `merge-pr` through Step
1's `authority-read.sh` and the new `settle-check.sh`, writes the read into the
step's evidence key, and follows the sealed token, never the start capture. It
closes the PRD criteria Declared merge (supervised and root), No declaration,
Excluded author, Refused answers, Holds, Record is evidence and Routing shown,
for the merge.

**Acceptance Criteria**:

- [ ] With a fake niwa answering `merge-pr` with the grant held, settler
  `session` and author exclusion off, `land` reaches the merge path; with
  settler `person` it routes the merge to a person and runs no merge; with
  settler `dispatcher` and a target it sends the merge to that target with
  its own reading and runs no merge; with settler `dispatcher` and no
  addressable target it holds the merge with reason `no-target`.
- [ ] With settler `session` and author exclusion on, `land` sends the merge
  to the target the answer gives, and holds it with reason `no-target` when
  none is given; with the grant not held and settler `session` with exclusion
  off, it holds the merge with reason `no-grant`.
- [ ] With no niwa on PATH, no session id, no instance root, a timeout, a
  non-zero exit, an unknown schema, an unknown `state`, `decider` or
  `author_exclusion` value, or no entry for `merge-pr`, `land` holds the merge
  and the report names the step, the point and a reason from the closed list.
- [ ] The fake niwa's log shows exactly one `--point merge-pr` read for the
  visit to `land`.
- [ ] The evidence key for the visit holds step, point, read time, result,
  state, settler, author exclusion, target, verdict and reason.
- [ ] The coordinator's next start report lists the visit's settle read
  (step, point, verdict, settler and hold reason), and editing the evidence
  key before that start changes no transition.
- [ ] Submitting a forged verdict field as evidence at `land` doesn't change
  the transition.

**Check**: Run the new `settle-check` engine test under
`skills/coordinate/scripts/` with the fake niwa fixtures; every case above
passes and the log assertion reports one read per visit.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/settle-check.sh,
skills/coordinate/scripts/land-check.sh,
skills/coordinate/scripts/coord-verdict.sh,
skills/coordinate/scripts/reconcile-report.sh,
skills/coordinate/koto-templates/coordinate.md

**Type**: code

**Complexity**: critical

### Step 3: the merge is taken only when land and land_merge both say take

**Goal**: `land_merge` gains `settle-check.sh` as its own sealed check, the
merge's second read, and its transitions follow that token rather than the
agent's submitted `merge` value. `land-merge.sh` refuses to call the merge
unless the visit's token says `take`. The start capture and the `posture_ask`
answer stop deciding the merge, and a Claude Code deny or ask rule on the
merge command holds it. It closes the PRD criteria Forged record, Done is
GitHub's, Review kept, Permission hold and Mid-run change, for the merge.

**Acceptance Criteria**:

- [ ] With the fake answer changed between `land` and `land_merge` from take to
  settler `person`, no merge runs and the merge goes to a person by the path
  `land` uses for a route.
- [ ] With the second read holding, submitting any `merge` value at
  `land_merge` reaches neither the merge command nor `merge_confirm`; the
  transition follows the sealed token.
- [ ] With the fake answer changed between two merges of one run, from take to
  settler `person`, the first pull request is merged and the second goes to a
  person.
- [ ] The fake niwa's log shows two `--point merge-pr` reads for a merge that
  reaches the command, and none of them acts on the start read.
- [ ] With an approval Standing row, a Reversals row, a relayed `posture_ask`
  answer, a forged review round and an edited `coord/posture.json` written, the
  merge has the same outcome as a run with no record rows.
- [ ] A merge sent to another settler is marked done only after GitHub reports
  the pull request merged, and a record row claiming it merged changes
  nothing.
- [ ] With the answer letting the session take the merge and a deny or ask
  rule on the merge command, the merge is held with reason `permission`.
- [ ] `bl_merge_posture` and `bl_human_holds_merge` are gone, and a coordinator
  the answer lets merge still sends a pull request it authored to its Verdicts
  reviewer first.

**Check**: Run the land and land_merge engine tests with the fake niwa and the
forged-record fixtures; each case reports the expected outcome and the read
count.

**Dependencies**: Step 2

**Files**: skills/coordinate/scripts/land-merge.sh,
skills/coordinate/scripts/board-lib.sh,
skills/coordinate/scripts/coord-verdict.sh,
skills/coordinate/koto-templates/coordinate.md

**Type**: code

**Complexity**: critical

### Step 4: verdict merges and the roadmap close read their own point at their state

**Goal**: Verdict and reopen merges (`milestone_verdict`, `milestone_reopen`)
and the roadmap close (`roadmap_close_step`) each run `settle-check.sh` at
their state, with a held outcome added beside each state's existing ones.
These are the only finishing states, besides the merge at `land`, where the
coordinator takes a step itself. It closes the PRD criteria Mapping, Read at
the step, Forged record, Done is GitHub's, Permission hold, Record is evidence
and Routing shown, for these states.

**Acceptance Criteria**:

- [ ] `milestone_verdict`, `milestone_reopen` and `roadmap_close_step` each
  gain a held transition beside their existing outcomes (for
  `roadmap_close_step`, beside `closed` and `handed_over`); a held step is
  read again at its next visit.
- [ ] Verdict and reopen merges ask `merge-pr` and `roadmap_close_step` asks
  `close-issue`; the fake niwa's log shows one read per visit and no other
  point asked.
- [ ] With the grant held, settler `session` and author exclusion off, each
  state takes its step; with settler `person` it routes the step to a person
  and merges or closes nothing; with settler `dispatcher` and no target it
  holds with reason `no-target`; with the grant not held and settler `session`
  with exclusion off it holds with reason `no-grant`.
- [ ] With the answer letting the session take the step and a deny or ask rule
  covering the step's command, the step is held with reason `permission` and
  goes to no other settler.
- [ ] With Step 3's forged-record fixtures written, each verdict merge and the
  roadmap close has the same outcome as a run with no record rows.
- [ ] A verdict or reopen merge sent to another settler is marked done only
  after GitHub reports the pull request merged, and a record row claiming it
  merged changes nothing.
- [ ] Each visit's evidence key holds step, point, read time, result, state,
  settler, author exclusion, target, verdict and reason. After a merge sent to
  the dispatcher and a roadmap close held for `no-grant`, the next start report
  lists both reads with step, point, verdict, settler and reason; with the held
  close's entry edited from hold to take before that start, the report shows
  the edit and every transition is unchanged.
- [ ] A test fails if any gate, router or `need-check.sh` reads an evidence key
  or `coord/posture.json` to choose a settler or to take a step, allowing only
  the start report printing the entries and teardown's interim read under R9.

**Check**: Run the coordinate engine tests for `milestone_verdict`,
`milestone_reopen` and `roadmap_close_step` with the fake niwa and the
forged-record fixtures; each case reports the expected outcome, point and read
count, and the record-reader test passes.

**Dependencies**: Step 3

**Files**: skills/coordinate/koto-templates/coordinate.md,
skills/coordinate/scripts/settle-check.sh,
skills/coordinate/scripts/coord-verdict.sh,
skills/coordinate/scripts/reconcile-report.sh

**Type**: code

**Complexity**: critical

### Step 5: a handed-back merge, close or release goes to the settler the answer names

**Goal**: At `surface_check`, `need-check.sh` words a worker's
`reserved-step <merge|close|release>` need from a fresh `settle-check.sh` read
of that step's point, and `progress-view.sh` shows the settler and reason from
the stored need. An issue or pull request close and a release reach the
coordinator only this way, since the template has no state where it closes
either or cuts a release itself; a release unit a worker runs settles under
the worker's own grant and brief (R11). The `grant_check.state` routing and
the `--dispatcher` wording go; `reserved-step teardown` stays for a person
(R9). It closes the PRD criteria Holds and Teardown, and Read at the step,
Mapping, Mid-run change, Permission hold, Forged record and Done is GitHub's
for handed-back steps.

**Acceptance Criteria**:

- [ ] A handed-back merge asks `merge-pr`, a handed-back issue or pull request
  close asks `close-issue` and a handed-back release asks `cut-release`; the
  fake niwa's log shows one read per `surface_check` visit, and a release unit
  a worker runs asks no point.
- [ ] A `take` verdict has the coordinator take the step itself; `route person`
  words the cell for a person; `route target` names the answer's target; a
  `hold` words the cell as held with its reason. No cell reads
  `for dispatcher <instance>`.
- [ ] A timed-out read, a skipped read (no niwa; no session id; no instance
  root), an answer with no entry for the point and a settler with no target
  each hold the step, record the reason and send one report naming the step,
  point and reason, with the same wording for a bound and a root session.
- [ ] With the fake answer changed between a merge at `land` and a handed-back
  release in one run, from take to settler `person`, the merge is taken and the
  release goes to a person.
- [ ] With the answer letting the session take a handed-back close or release
  and a deny or ask rule covering its command, the step is held with reason
  `permission`.
- [ ] With Step 3's forged-record fixtures written, a handed-back close and
  release each have the same outcome as a run with no record rows; a close or
  release sent to another settler is marked done only after GitHub reports
  the issue or pull request closed or the release published.
- [ ] A handed-back teardown goes to a person, and with the fake answer
  changed, teardown's outcome is unchanged and follows the permission posture.
- [ ] `need-check.sh` has no `grant_check.state` branch and `progress-view.sh`
  has no `--dispatcher` option.

**Check**: Run `need-check_test.sh` and `progress-view_test.sh` with fake niwa
fixtures for each handed-back step and each hold reason, as a bound and as a
root session; every outcome and wording matches, and the teardown case is
unchanged.

**Dependencies**: Step 3

**Files**: skills/coordinate/scripts/need-check.sh,
skills/coordinate/scripts/progress-view.sh,
skills/coordinate/scripts/coord-verdict.sh,
skills/coordinate/koto-templates/coordinate.md

**Type**: code

**Complexity**: critical

### Step 6: the skill names the settler from the answer and the bound-or-root rule is gone

**Goal**: `SKILL.md`, the template and the references replace every sentence
that routes a merge, close or release by bound or root, name the read, and say
a record row may restrict but never widen. That covers the overview's landing
sentence, Bounds and Authority's escalation and denial paragraphs (the
confirmation rule for bound and root included), the Decisions grounds, the
record's `handed-over` state, the Verdicts rules' chain for who merges a
verdict pull request, the template's dispatch and roadmap-close passages, and
the close passage in `references/state-keys.md`. Only the sentence naming the
Verdicts reviewer keeps its wording (R10); teardown's sentence sends a
teardown to a person and names neither (R9). `posture-read.sh`'s grant fold
table goes, the start token's word comes from teardown's reading alone, and
`posture_ask` asks only about teardown. It closes the PRD criteria Wording,
the `SKILL.md` read, No new table and the unchanged worker brief line.

**Acceptance Criteria**:

- [ ] `grep -nE 'session is bound|root coordinator|where you are
  bound|grant_check\.state|--dispatcher'` over the coordinate skill's text and
  scripts, tests aside, matches only the Verdicts reviewer sentence, and runs
  as a test.
- [ ] A verdict or reopen pull request's merge is settled by the `merge-pr`
  read alone; no passage says it falls to the next one up the chain.
- [ ] `SKILL.md` names the read as `niwa authority check -C <instance>
  --session <id> --point <p>`, says a record row may restrict its answer but
  never widen it, and claims nothing about the answer being unforgeable.
- [ ] `SKILL.md` says, at the two passages, that they keep today's sources
  only until the workspace authority work names a teardown point and where a
  review goes, without citing dependency codes, so the Verdicts reviewer is
  the one rule left that names a parent and teardown's posture read is marked
  interim.
- [ ] `posture-read.sh` folds no grant into `permit`, `deny` or `confirm`, and
  no file under `skills/coordinate/` maps levels, grants or settlers except
  `settle-check.sh`'s step-to-point mapping.
- [ ] `posture_ask` asks only about teardown, and a start whose merge or close
  reading is unread but whose teardown reading is readable goes on without
  stopping there.
- [ ] `dispatch-worker.sh` builds a successor coordinator's grant from
  `grant_check` as it does today.
- [ ] The worker brief's `Named authority:` line is byte-for-byte unchanged.

**Check**: Run the wording test, `posture-read_test.sh`, the start-state
engine tests and `dispatch-worker.sh`'s tests, and compare the worker brief's
`Named authority:` line against main. The wording test reports the reviewer
sentence alone, the fold cases are gone, a start with an unread merge reading
and a readable teardown reading passes `posture_ask` by, a search under
`skills/coordinate/` for a table mapping levels, grants or settlers finds only
`settle-check.sh`'s step-to-point mapping, and the comparison is empty.

**Dependencies**: Step 4, Step 5

**Files**: skills/coordinate/SKILL.md,
skills/coordinate/koto-templates/coordinate.md,
skills/coordinate/references/loop.md,
skills/coordinate/references/state-keys.md,
skills/coordinate/scripts/posture-read.sh

**Type**: code

**Complexity**: testable

## Implementation Sequence

Steps 1, 2 and 3 run in order. Steps 4 and 5 each follow Step 3 and can land
in either order. Step 6 lands last. After Step 6, two passages still keep
today's sources: teardown reads the permission posture (R9) and the review
before a merge names the Verdicts rules' reviewer, which is the dispatching
coordinator when bound and a person at the root (R10). That reviewer sentence
is the one place the skill still names a parent, so the claim that the skill
keeps no rule of its own about levels, parents or who may decide a step holds
only once D4 and D5 ship and those two passages read the answer too. Moving
them is follow-up work for that point, not a step of this plan.
