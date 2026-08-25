---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-cascade-post-verify-seed.md
milestone: "Cascade post-verify seed"
issue_count: 4
tracking_level: none
---

# PLAN: Cascade post-verify seed

## Status

Active

## Scope Summary

Fix `/execute`'s finalization cascade verifying its own work against the PLAN it
just deleted, and close the test gap that let the defect survive ten weeks and
three filings. The change lands in two files: `skills/execute/scripts/run-cascade.sh`
and `skills/execute/scripts/run-cascade_test.sh`.

The work is four issues. The first is plumbing: `git commit` writing to stdout
ahead of the JSON report, which PRD R7a puts in scope explicitly, and `add_step`
being unable to emit a null `target`, which PRD R7 requires. Neither is an
optional extra a reviewer should try to cut — no `--push` scenario can assert
anything until both land. The second is the fix proper: a seed parameter on
`lifecycle_probe`, an anchor resolver reading the cascade's own record, and a
three-way split of the post-verification. The third is eight `--push` scenarios,
the half that stops the next regression. The fourth is the mutation check that
proves those scenarios discriminate, plus the issue triage.

One pull request. The issues are sequential, each is small, and splitting them
across pull requests would leave the repository in a state where the test suite
asserts against output the script does not yet produce.

## Decomposition Strategy

Sliced as a walking skeleton in reverse: the plumbing that makes observation
possible goes first, then the behaviour change, then the tests that observe it,
then the proof that the tests can fail.

The grouping rule is one issue per reviewable concern. Issue 1 is two one-word
edits to functions the rest of the plan does not touch, and a reviewer should be
able to see them alone rather than buried in the fix. Issue 2 is the whole
behaviour change and nothing else. Issue 3 is test-only. Issue 4 produces no code
at all.

The sequence is forced rather than chosen. Issue 3 cannot be written before issue
1, because every assertion it makes parses stdout as JSON and stdout is not JSON
until `git commit -q` lands. Issue 4's mutation is meaningless before issue 2,
because the mutant it applies is the restoration of code issue 2 removes.

## Issue Outlines

### Issue 1: make `--push` output observable

**Goal**: Two edits to `run-cascade.sh` so a `--push` run emits parseable JSON
and `add_step` can record a null target.

**Acceptance Criteria**:
- `git commit` at line 885 becomes `git commit -q`, so stdout in a `--push` run
  carries only the report emitted by `emit_result`.
- `add_step`'s `target` parameter accepts the literal token `null` and emits JSON
  null, using the same `--argjson`-or-`--arg` treatment `found_in` already gets
  at lines 334-337 and 350. Every existing call site passes a real path and is
  unaffected. Verified by emitting a step with `target` `null` and checking
  `(.target | type) == "null"` — the string `"null"` is what the unfixed build
  produces and is the failure this edit exists to prevent.
- The existing eighteen scenarios still pass.

**Dependencies**: None.

**Type**: fix

**Files**: `skills/execute/scripts/run-cascade.sh`

**Notes**: Both edits are prerequisites rather than the subject. The script's
usage block already promises "Output: JSON to stdout"; under `--push` it has
never kept that promise, which is why eighteen green dry-run scenarios never
surfaced it.

### Issue 2: seed the post-verification on a surviving anchor

**Goal**: Replace the hardcoded `$PLAN_DOC` seed on the post-cascade probe with
an anchor resolved from the cascade's own record, and split the verification
three ways.

**Acceptance Criteria**:
- `lifecycle_probe` takes a second parameter, the seed path, and interpolates it
  at line 297 instead of `$PLAN_DOC`. The `pre` call passes `$PLAN_DOC` and its
  behaviour is unchanged.
- A new `resolve_anchor` helper walks `STAGED_FILES`, keeps only entries passing
  `[[ -f ]]`, and returns the highest-precedence survivor by basename prefix:
  DESIGN, then PRD, then BRIEF, then ROADMAP. It returns 1 with no output when
  nothing survives. No filter disqualifies a surviving candidate; the prefix test
  orders survivors only.
- With an anchor and a clean check, the step records `ok` with `target` set to
  the anchor.
- With an anchor and a non-clean check, the step records `failed`, sets
  `ANY_FAILED=true`, and carries the validator's findings summary in `detail`.
- With no anchor, the step records `skipped`, `target` null, and a detail
  containing `no recorded chain document survived to verify against`. It does not
  set `ANY_FAILED=true` and does not report `L05`.
- Both surviving arms preserve the existing `L06` detail composition unchanged:
  `"$L06_SUPPRESSED_DETAIL"` on the ok arm and the
  `${L06_SUPPRESSED_DETAIL:+ ($L06_SUPPRESSED_DETAIL)}` suffix on the failed arm.
  No test reaches this block today, so nothing else would catch its removal.
- `resolve_anchor` is called inside the post-verification block at line 906,
  after the `git rm` at 873 and the commit at 885. No candidate list is computed
  earlier and cached; the existence test is evaluated where the verification runs.
- The four `case` rungs are exhaustive over the five record-append sites by
  construction — those sites can contribute only a DESIGN, PRD, BRIEF or ROADMAP
  path — so no default arm is needed and none is added. A future sixth append
  site must add a rung rather than fall through, because falling through would
  disqualify a surviving candidate, which the precedence rule forbids.
- No path in the new code clears `ANY_FAILED`. The five sites at lines 579, 827,
  832, 850 and 876 are untouched.
- bash 3.2 compatible: no associative arrays, no negative subscripts, no
  `mapfile`, and the existing `${arr[@]:+...}` guard is used for the array walk.
- The existing eighteen scenarios still pass, and a hand-run `--push` cascade
  over a clean single-pr chain reports `completed`.

**Dependencies**: Issue 1.

**Type**: fix

**Files**: `skills/execute/scripts/run-cascade.sh`, `skills/execute/SKILL.md`

**Notes**: The seed-doc rule in `SKILL.md` lists the durable anchor as the
DESIGN at its terminal path or the BRIEF/PRD at Done, and never mentions the
ROADMAP. The implemented precedence ranks a surviving ROADMAP last and will
select it when no tactical member survives, so that bullet gains a clause. The
rule is otherwise already correct — this change brings the script into
compliance with it rather than the reverse.

### Issue 3: exercise the `--push` path from the suite

**Goal**: Eight new scenarios plus a pass-through logging stub variant, so CI
executes the post-verification branch for the first time.

**Acceptance Criteria**:
- Every new scenario establishes an upstream-tracking branch with
  `git push -u origin HEAD` after `commit_all`. `setup_test_repo` creates a
  file-based bare origin but sets no tracking branch, so the cascade's bare
  `git push` would otherwise abort the script under `set -e` with no JSON
  emitted.
- Surviving-DESIGN scenario: `completed`, step `ok`, `target` equal to
  `docs/designs/current/DESIGN-<slug>.md`. Fixture is `write_roadmap` (Feature 2
  stays `Planned`) plus DESIGN plus PLAN. Run once more with
  `WORK_ON_ALLOW_UNTRACKED_ACS=1` asserting the step's detail still carries the
  `l06_suppressed=1` marker: no scenario has ever reached line 906, so the two
  existing `allow_untracked_acs` scenarios do not guard this block.
- No-survivor scenario: `completed`, step `skipped`, detail carrying the literal
  phrase, and `target` a JSON null rather than the string `"null"` — assert
  `(.target | type) == "null"`, not `.target == "null"`, which passes against the
  unfixed `--arg` build and would make Issue 1's `--argjson` edit unobserved.
  Fixture is a PLAN whose only upstream is a ROADMAP built with
  `write_roadmap_done_single` and no embedded issue URLs.
- Non-DESIGN-anchor scenario: step `ok` with `target` equal to
  `docs/prds/PRD-<slug>.md`. Fixture is BRIEF at `Accepted` with no upstream,
  then PRD at `Accepted`, then PLAN.
- Blocked-DESIGN scenario: `partial`, step `failed`, detail containing
  `DESIGN at status 'Planned' (expected status 'Current'` and not containing
  `not found or not resolvable`, plus filesystem assertions that
  `docs/designs/DESIGN-<slug>.md` is still `Planned` and `docs/designs/current/`
  does not exist. Fixture is two single-pr PLANs sharing one DESIGN.
- Earlier-failure scenario: `partial` with the step at `ok`. Fixture is PLAN,
  then DESIGN, then an upstream that exists on disk with an unrecognized prefix
  (`docs/notes/NOTE-<name>.md`). The error node must sit above a node that staged
  successfully. Build this scenario second, right after the surviving-DESIGN one,
  and confirm before writing the rest that ready-posture validation seeded on the
  transitioned DESIGN comes back clean with the unrecognized upstream above it.
  If it does not, the fixture needs a recognized-prefix upstream whose node still
  returns `action: "error"`, and the assertion is unachievable until it does.
- ROADMAP-anchor scenario (PRD AC7): a PLAN whose only upstream is a surviving
  ROADMAP reports `completed`, step `ok`, `target` equal to
  `docs/roadmaps/ROADMAP-<slug>.md`, and **not** `skipped`. Fixture is the
  `scenario_plan_roadmap_no_design` shape with `write_roadmap`, so Feature 2
  stays `Planned`, the deletion branch never fires, and the ROADMAP is rewritten
  and staged at `:497`. This is the only scenario that proves a ROADMAP rung
  exists at all: drop `ROADMAP-*)` from `resolve_anchor` and every other
  criterion in this plan still passes.
- ROADMAP-ordering scenario (PRD AC8a): a chain with a ROADMAP, no DESIGN, a
  surviving PRD and BRIEF, and an in-flight sibling PLAN under a second ROADMAP
  feature reports `completed`, step `ok`, `target` equal to the PRD. This fails
  any ordering that ranks the ROADMAP above a tactical member. The two ROADMAP
  scenarios test opposite directions and neither substitutes for the other.
- Pre-probe argv scenario: in a `--push` run reaching the verification, the first
  `validate --lifecycle-chain` argv contains the PLAN path and the second does
  not, containing the anchor instead. Needs a new pass-through logging stub that
  logs `$*` then `exec`s the real binary; neither existing variant works, because
  both fake the validate result and short-circuit the run.
- No new scenario sets an `https://` origin or invokes `gh`.
- Every new scenario is registered in the runner block. Registration is manual
  and a function without a call line is silently a no-op.
- No new step in any scenario carries the detail substring
  `not found or not resolvable`.

**Dependencies**: Issue 1, Issue 2.

**Type**: test

**Files**: `skills/execute/scripts/run-cascade_test.sh`

### Issue 4: prove the tests discriminate, and triage

**Goal**: Show each new assertion fails against the unfixed behaviour, then
close out the three duplicate issue filings and file the two adjacent defects.

**Acceptance Criteria**:
- **Mutant A** restores `--lifecycle-chain "$PLAN_DOC"` at the post call site.
  These scenarios MUST fail under it: surviving-DESIGN, non-DESIGN-anchor,
  blocked-DESIGN, earlier-failure, ROADMAP-anchor, ROADMAP-ordering, and the
  argv scenario's second-call assertion. The run is not accepted if any of them
  passes.
- **Mutant B** makes the no-anchor arm record `ok` with `$PLAN_DOC` as target.
  The no-survivor scenario MUST fail under it. This mutant exists because mutant
  A cannot reach that arm at all: a run with no surviving anchor never calls the
  probe, so restoring its seed changes nothing there.
- Both mutants are reverted after the runs. The pull request body states each
  mutant as a one-line diff, the scenarios that failed, and the pasted `FAIL:`
  lines, so a reviewer can reproduce in one step.
- The pre-probe argv scenario's first-call assertion and the pre-probe-terminal
  scenario are excluded from both mutants, since each asserts behaviour neither
  mutant changes.
- The whole suite passes, and passes on the bash 3.2 floor via
  `scripts/check-bash-floor.sh execute`.
- `shirabe validate --pr-body <file> --pr-title <string>` passes before the pull
  request is opened.
- The pull request references shirabe#186 so merging closes it. shirabe#307 and
  shirabe#328 are closed as duplicates pointing at it.
- Two new issues are filed: `delete_plan` never entering `STAGED_FILES`, and the
  unguarded `git push` aborting the script before `emit_result`.

**Dependencies**: Issue 3.

**Type**: chore

**Files**: none (verification and issue tracker only)

## Implementation Sequence

Strictly sequential; there is no parallel work in this plan.

Open with **Issue 1**, because it is the only issue with no prerequisite and every
later assertion depends on it. Confirm the eighteen existing scenarios still pass
before moving on.

Then **Issue 2**, the behaviour change. At this point nothing observes it yet, so
the check is that the existing suite still passes and a hand-run `--push` cascade
reports `completed`.

Then **Issue 3**, which is the bulk of the work and the half that stops the next
regression. Write the surviving-DESIGN scenario first: it is the common case, and
getting its tracking-branch setup right establishes the pattern the other six
copy.

Close with **Issue 4**. The mutation check comes last because it needs the
finished suite, and the triage comes last because it references the pull request.

## References

- `docs/designs/DESIGN-cascade-post-verify-seed.md` — the approach and the four
  options rejected.
- `docs/prds/PRD-cascade-post-verify-seed.md` — the requirements and acceptance
  criteria each issue is written against.
- `skills/execute/SKILL.md` — the seed-doc rule the script contradicts.
