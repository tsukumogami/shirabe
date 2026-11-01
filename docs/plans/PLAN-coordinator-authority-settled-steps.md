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
step_count: 7
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

Walking skeleton. Step 1 crosses the whole path for one step, the merge at
`land`: the reader, the verdict, the evidence key and the transition that
follows the sealed token, all against a fake `niwa` first on PATH. Later steps
add the merge's second read, then each remaining finishing step, then move the
start read and the standing-rule read onto the one reader, and end with the
skill text. None of it lands with this plan: the plan merges ahead of its
build, and each step lands later in its own pull request, in step order, once
the niwa work above ships. Step 1 is the first of those pull requests.

## Steps

### Step 1: a merge at land is taken, routed or held by a fresh authority read

**Goal**: `land` decides the merge from one read of `merge-pr` through
`authority-read.sh` and `settle-check.sh`, writes the read into the step's
evidence key, and follows the sealed token, never the start capture. It
closes the PRD criteria Declared merge (supervised and root), No declaration,
Excluded author, Refused answers, Holds, Record is evidence and Routing shown,
for the merge.

**Acceptance Criteria**:

- [ ] With a fake niwa answering `merge-pr` with the grant held, settler
  `session` and author exclusion off, `land` reaches the merge path; with
  settler `person` it routes the merge to a person and runs no merge; with
  settler `dispatcher` and no addressable target it holds the merge with
  reason `no-target`.
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

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/settle-check.sh,
skills/coordinate/scripts/land-check.sh,
skills/coordinate/koto-templates/coordinate.md

**Type**: code

**Complexity**: critical

### Step 2: the merge is taken only when land and land_merge both say take

**Goal**: `land-merge.sh` reads `merge-pr` again just before the merge command,
the start capture and the `posture_ask` answer stop deciding the merge, and a
Claude Code deny or ask rule on the merge command holds it. It closes the PRD
criteria Forged record, Done is GitHub's, Review kept and Permission hold, for
the merge.

**Acceptance Criteria**:

- [ ] With the fake answer changed between `land` and `land_merge` from take to
  settler `person`, no merge runs and the merge goes to a person.
- [ ] The fake niwa's log shows two `--point merge-pr` reads for a merge that
  reaches the command, and none of them acts on the start read.
- [ ] With an approval Standing row, a Reversals row, a relayed `posture_ask`
  answer, a forged review round and an edited `coord/posture.json` written, the
  merge has the same outcome as a run with no record rows.
- [ ] With the answer letting the session take the merge and a deny rule on
  the merge command, the merge is held with reason `permission`.
- [ ] `bl_merge_posture` and `bl_human_holds_merge` are gone, and a coordinator
  the answer lets merge still sends a pull request it authored to its Verdicts
  reviewer first.

**Check**: Run the land and land_merge engine tests with the fake niwa and the
forged-record fixtures; each case reports the expected outcome and the read
count.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/land-merge.sh,
skills/coordinate/scripts/board-lib.sh

**Type**: code

**Complexity**: critical

### Step 3: closes and verdict merges read their own point at their state

Roadmap closes, close-out issue and pull request closes, and verdict and reopen merges each run `settle-check.sh` at their state, with a held outcome added beside each state's existing ones, closing the PRD criteria Mapping, Read at the step, Forged record, Done is GitHub's, Permission hold, Record is evidence and Routing shown for closes.

### Step 4: a handed-back merge, close or release goes to the settler the answer names

`need-check.sh` and `progress-view.sh` word a worker's reserved step from a fresh read of its point, the `grant_check.state` routing and `--dispatcher` wording gone, teardown still for a person, closing the PRD criteria Holds and Teardown for handed-back steps.

### Step 5: a release the coordinator runs itself reads cut-release at its step

A release the coordinator runs itself takes, routes or holds on a fresh `cut-release` read, and a mid-run change to the answer applies at the next step, closing the PRD criteria Mid-run change, Mapping and Permission hold for releases.

### Step 6: the start read and the standing-rule read go through the one reader

`posture-read.sh` and `state-stored-set.sh --rules` call `authority-read.sh`, the grant fold table goes, and a search finds `niwa authority check` in exactly one script, closing the PRD criteria One reader and No new table.

### Step 7: the skill names the settler from the answer and the bound-or-root rule is gone

`SKILL.md`, the template and the references replace every bound-or-root sentence except teardown and the Verdicts reviewer, name the read, say a row may restrict but never widen, and the PRD's wording search passes as a test, closing the PRD criteria Wording, the `SKILL.md` read and the unchanged worker brief line.
