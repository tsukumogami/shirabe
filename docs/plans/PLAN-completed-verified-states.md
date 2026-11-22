---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-completed-verified-states.md
milestone: "Completed and Verified milestone states"
step_count: 9
---

# PLAN: Completed and Verified milestone states

## Status

Active

## Scope Summary

The design adds a `roadmap/v4` schema whose milestones read Not started, In
progress, Completed, Verified or Dropped, and one status definition,
`skills/roadmap/references/milestone-statuses.json`, that the Rust crates embed
and the coordinate scripts read with jq. Every reader that compares status words
today (`is_terminal_roadmap_status` in `table.rs`, `feature_is_terminal` in
`populate.rs`, FC21 in `checks.rs`, and the picker, dispatch check and closeout
read behind `lib_roadmap_features`) asks the table's four properties instead.
On a v4 roadmap the coordinator records Completed at the merge, in its pending
roadmap edit or a new one, a verdict owed refuses only its own milestone's
delivery, `--verdict` and `--reopen` write Verified and In progress through the
table's transition list, and `shirabe roadmap migrate` moves a v2 or v3 roadmap
to v4. Roadmaps on v1, v2 and v3 behave as before, apart from Done, Shipped and
Closed now being read alike everywhere.

The successor case of a verdict owed (a coordinator whose only open unit owes a
verdict handing over) is the `--successor` mode of
`PLAN-coordinate-successor-role.md`. This plan narrows the refusal for other
milestones' and dependents' briefs and leaves a delivery brief for the owing
milestone refused, which is the behaviour that plan's worker-dispatch criterion
already expects.

## Decomposition Strategy

Walking skeleton. Step 1 crosses the whole path the design opens on one input:
the data file, the Rust status table, the validator and populate, run on a
`roadmap/v4` fixture with a Completed milestone. Step 2 brings the shell side
onto the same table, so from step 3 on every behaviour change reads statuses
from one place. The later steps each add one behaviour a coordinator or an
author sees: the v4 checks, a verdict owed no longer gating other work,
Completed recorded at the merge, verdicts and reopens on v4, the progress view
wording, the migration, and the word-comparison check with the release notes.
Everything lands in one pull request: the repository prefers consolidated
delivery, and no step needs another to reach the default branch first.

## Steps

### Step 1: a roadmap/v4 fixture with a Completed milestone validates and renders it apart from Verified

**Goal**: `shirabe validate` and `shirabe roadmap populate`, run on a
`roadmap/v4` fixture whose milestones read Not started, In progress,
Completed, Verified and Dropped, read every status through the new
`milestone-statuses.json` table (embedded by a new `statuses.rs`), so the
data file reaches both Rust readers end to end. On v1 to v3 fixtures both
commands produce exactly what they produce on the default branch today.

**Acceptance Criteria**:

- [ ] `shirabe validate` on the five-status `roadmap/v4` fixture exits 0.
- [ ] `shirabe roadmap populate` on that fixture renders the Completed row
  unstruck with class `completed` and its dependent with class `ready`, the
  Verified row struck with class `done`, and the Dropped row struck with class
  `dropped`, declares the `completed` and `dropped` classes, and
  `shirabe validate` passes on the result.
- [ ] For every `roadmap/v1`, `v2`, `v3` and schema-less fixture in the
  crates' tests, validate and populate output captured on the default branch
  before the change are byte-identical after it.
- [ ] A `roadmap/v3` fixture with one milestone at Shipped and one at Closed
  passes `shirabe validate` with exit 0, and populate renders both rows struck
  with class `done` and each one's dependent with class `ready`.
- [ ] A fixture pair, one `roadmap/v3` and one `roadmap/v4`, where Milestone 2
  depends only on a Dropped Milestone 1 and Milestone 4 only on a Completed
  (v4) or Done (v3) Milestone 3: populate renders Milestone 2 with class
  `blocked` and Milestone 4 with class `ready` in both, although the v4
  Dropped row is struck.
- [ ] `statuses.rs`'s unit tests assert the four property values of every
  status in the design's table, for `v1-v3` and `v4`, and the table version
  `shirabe --version` prints equals the `version` field of
  `milestone-statuses.json` (the test reads the file).

**Check**: Capture validate and populate output for every roadmap fixture on
the base commit, then run `cargo test -p shirabe-validate statuses` and
`cargo test -p shirabe populate` and the new fixture tests, and diff the
captured outputs against the new ones: no difference except the Shipped and
Closed fixture. Run `shirabe roadmap populate` on the five-status fixture and
see the five rows and two new classes as listed.

**Dependencies**: None

**Files**: `skills/roadmap/references/milestone-statuses.json`, `crates/shirabe-validate/src/statuses.rs`, `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/formats.rs`, `crates/shirabe/src/populate.rs`

### Step 2: the coordinate scripts read status properties from the same table

**Goal**: `lib_status` in `state-common.sh` loads
`milestone-statuses.json` from the scripts' own directory
(`$HERE/../../roadmap/references/`), picks the schema family from the
roadmap's `schema:` line (`v4` for `roadmap/v4`, `v1-v3` otherwise), maps a
status to its entry through each entry's `spellings` (the table's `open`
entry lists Not started and In progress; any other value falls to `open`), and
`lib_roadmap_features` emits the four properties for each milestone; `pick-facts.sh` and `closeout-read.sh`
read those properties instead of comparing words. On v1 to v3 roadmaps the
picker's and closeout's output does not change.

**Acceptance Criteria**:

- [ ] On every v1, v2, v3 and schema-less roadmap fixture in the coordinate
  tests, `pick-facts.sh` and `closeout-read.sh` output captured on the base
  commit is byte-identical after the change.
- [ ] On a `roadmap/v4` fixture where Milestone 2 depends on a Completed
  Milestone 1, `pick-facts.sh`'s JSON lists Milestone 2 in its pickable units
  and gives Milestone 1 `"takes_work": false` and no pickable entry; with
  Milestone 1 Dropped instead, Milestone 2 is absent from the pickable units.
- [ ] On a `roadmap/v3` fixture with one Shipped and one Closed milestone, each
  with a dependent, `pick-facts.sh`'s JSON lists both dependents as pickable
  and neither Shipped nor Closed milestone as pickable; on a `roadmap/v3`
  fixture where Milestone 2 depends only on a Dropped Milestone 1, Milestone 2
  is absent from the pickable units.
- [ ] With the table file removed, made unparseable, or given an unknown
  `version`, every script that sources `lib_status` exits non-zero with a
  message naming the file's path, and writes nothing.
- [ ] A shell test loads the table and asserts the same property values the
  Rust test asserts.

**Check**: Run `bash skills/coordinate/scripts/run-tests.sh` and the new
`lib-status_test.sh`, after capturing the base commit's picker and closeout
output for the existing fixtures, and see the existing suites pass, the
captured output unchanged, and the v4 and fail-closed cases as listed.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/state-common.sh`, `skills/coordinate/scripts/pick-facts.sh`, `skills/coordinate/scripts/closeout-read.sh`

### Step 3: shirabe validate refuses a Done roadmap/v4 roadmap with open milestones and a milestone whose block disagrees with its Progress row

**Goal**: On a `roadmap/v4` roadmap, `shirabe validate` refuses the roadmap's
own Done while any milestone doesn't close (by the table's `closes`), and
refuses a milestone whose block `**Status:**` and Progress table row read
different statuses; the diagram reconciliation accepts the `completed` and
`dropped` classes; and the format reference documents `roadmap/v4`. Step 1
already made FC21 read the table, so a v4 milestone at Done already fails and
is only covered by a test here.

**Acceptance Criteria**:

- [ ] A `roadmap/v4` fixture whose own status is Done, with one milestone
  Completed and one In progress, fails `shirabe validate` with one finding
  per open milestone naming it; the same fixture with both milestones Verified
  or Dropped passes, and so does one whose milestones are all Dropped.
- [ ] A `roadmap/v4` fixture whose Milestone 1 block reads Completed and whose
  Progress row reads In progress fails with a finding naming the milestone and
  both values; with the two matching it passes. A v4 roadmap with no Progress
  table passes this check.
- [ ] A `roadmap/v4` fixture with a milestone at Done fails, naming the
  milestone and the five allowed statuses (a regression test for step 1).
- [ ] A populated `roadmap/v4` diagram declaring and using `completed` and
  `dropped` passes FC07 and FC08; a v3 diagram using `completed` still fails
  as before.
- [ ] Neither new check fires on any `roadmap/v1`, `v2`, `v3` or schema-less
  fixture: the identity corpus's validate output is unchanged.
- [ ] `skills/roadmap/references/roadmap-format.md` has a `roadmap/v4`
  section with the five statuses and their four properties, the transition
  table, the fields that may change while a roadmap is Active, and the
  install-before-migrate rollout note; `shirabe validate` passes on it.

**Check**: Run `cargo test -p shirabe-validate` and `cargo test -p shirabe`
with the new fixtures under `crates/shirabe/tests/fixtures/roadmap-v4/`, and
the identity corpus test; see the new failure messages as listed and no
change on the corpus. Run `shirabe validate` on the format reference.

**Dependencies**: Step 1

**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/mermaid.rs`, `skills/roadmap/references/roadmap-format.md`

### Step 4: a milestone that owes a verdict no longer stops another milestone's or a dependent's dispatch

Code 49 and exit 10 apply only to a delivery brief for the owing milestone, the picker offers the owed verdict as a unit, and a coordinator taking a v4 roadmap up lists milestones that owe a verdict.

### Step 5: the coordinator records Completed at the merge in its pending roadmap edit or a new one

On v4, `roadmap-status.sh --unit` writes Completed and Delivered to block and Progress row, folding into the run's own pending edit with a fast-forward push or opening a new edit, and re-reads the pending edit's state when a push fails.

### Step 6: verdicts and reopens on roadmap/v4 set Verified and In progress and refuse moves the table doesn't list

`--verdict` works without a verdict-owed row, keeps the delivering-checker refusal, writes Verified or In progress with held-dependent lines, `--reopen` accepts Completed, and a Verified-to-Verified verdict or any other unlisted move is refused before anything is written.

### Step 7: the progress view shows landed milestones and stops calling passing pull requests verified

A Completed milestone reads `landed, verdict owed`, and the pull-request rows read `checks passed, ready to merge` and its held and paused variants.

### Step 8: shirabe roadmap migrate moves a v2 or v3 roadmap to v4 with a dry run

The command maps Done, Shipped and Closed by each milestone's latest verdict line, converts the v2 layout, writes atomically through an exclusive temp file, refuses paths outside the repository, and applies the design's check order.

### Step 9: CI refuses status-word comparisons outside the shared readers, and the release notes give the rollout order

`scripts/check-status-words.sh` runs in CI with the PRD's search pattern, and the format reference and release notes say to install the release on every coordinator host before migrating a roadmap.
