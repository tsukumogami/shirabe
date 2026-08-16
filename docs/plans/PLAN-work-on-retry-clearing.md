---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
upstream: docs/designs/DESIGN-work-on-retry-clearing.md
milestone: "Work-on Retry Clearing"
issue_count: 7
---

# PLAN: /work-on Retry Clearing

## Status

Active

## Scope Summary

Six gates in `/work-on` hold a context key that a re-entry can satisfy with the
previous round's artifact. This PLAN removes those keys on the paths that
re-enter, verifies each removal with `koto context exists`, and prints a stdout
diagnostic naming the escalate outcome when a removal does not take.

Six phase files change and one script is new. No gate declaration changes, so
`skills/work-on/koto-templates/work-on.md` is not edited and there is no mermaid
companion to regenerate and no eval fixture to rebuild. The verification uses
koto's own gate predicate rather than a proxy for it, which is what lets the
presence gates already on main stay as they are.

## Decomposition Strategy

**Vertical by retry edge, then the checks.** Issues 1 through 3 are one per
group of retry edges, sliced so each is a coherent change to files that move
together: the three panel files share a byte-identical block, the two edges into
`analysis` share a key, and `finalization` stands alone. Issue 4 is the prose
correction that depends on the panel block existing to describe. Issues 5 and 6
are the harness and its CI wiring, and issue 7 the evals.

The slicing rule is one issue per set of files that must change together for the
tree to stay coherent. Issues 1-3 are independent of each other and can land in
any order; nothing between them shares a file or a key.

The harness (issue 5) cannot be written first, and this is worth stating because
the usual instinct is to invert it. The harness extracts the shipped blocks out
of the phase files rather than carrying pasted copies, so there is nothing to
extract until issues 1 through 3 have shipped them. That constraint is the
point: a pasted copy would keep passing after the shipped text drifted, which is
the failure mode this whole change exists to close.

## Issue Outlines

### Issue 1: fix(work-on): clear the panel artifacts on the retry path

**Goal**: A `blocking_retry` from any of the three review panels removes all
three panel keys before submitting, so no panel advances on the verdict it
recorded before the code changed.

Add a Retry Loop clearing block to `phase-4a-scrutiny.md`, `phase-4b-review.md`
and `phase-4c-qa.md`. The block hoists the phase's outcome field into an
`OUTCOME_FIELD` variable on its first line — `scrutiny_outcome`,
`review_outcome`, `qa_outcome` — and everything below that line is byte-identical
across the three. The diagnostic has to name the phase's own field, so the
variable is what keeps the rest identical. It removes
`scrutiny_results.json`, `review_results.json` and `qa_results.json`, confirms
each is absent with `koto context exists`, and on a survivor prints the key, the
outcome not to submit, and `blocking_escalate` as the way to a terminal state,
then exits 1.

All three keys are cleared from every panel, not only the raising panel's: a
retry returns through `implementation` and walks forward into every panel at or
above the raiser, and the code they reviewed is about to change.

Rewrite `phase-4a-scrutiny.md`'s Retry Loop section. Two of its sentences are
load-bearing and both must go: the claim that `koto context` has no verb
removing a key (false since koto v0.11.5) and the statement that what keeps an
earlier pass from advancing is the submitted `scrutiny_outcome` (the mechanism
being replaced).

The block carries no `koto context exists` guard before removing. `remove` is
idempotent on a never-written key, so there is nothing to guard, and `ctx_exists`
reports `false` for an unreadable store as well as an absent one — a guard would
skip a key whose real artifact is still there.

**Acceptance Criteria**:
- Each of the three phase files carries the clearing block on its
  `blocking_retry` path.
- The three blocks are byte-identical below their first line.
- `grep -c "koto has no verb that removes a key" skills/` returns 0.
- `phase-4a-scrutiny.md` no longer states that the submitted outcome is what
  prevents an earlier pass from advancing.
- Each block's diagnostic names `blocking_escalate`.

**Dependencies**: None.

**Type**: implementation

**Files**: `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/references/phases/phase-4b-review.md`, `skills/work-on/references/phases/phase-4c-qa.md`

**Complexity**: testable

### Issue 2: fix(work-on): clear plan.md on both edges into analysis

**Goal**: `analysis` does not advance on the plan it is being re-entered to
replace, on either edge that re-enters it.

Two edges reach the `plan_artifact` gate with a stale `plan.md`, and both need
the block. `implementation` submits `implementation_status: scope_expanded_retry`
and routes to `analysis`; `analysis` self-loops on `plan_outcome:
scope_changed_retry`. Covering one and reasoning that the other follows leaves
the defect live on the uncovered edge.

Add the clearing block over `plan.md` to `phase-4-implementation.md` on the
`scope_expanded_retry` path and to `phase-3-analysis.md` on the
`scope_changed_retry` path. Same shape as issue 1: remove, confirm absent with
`koto context exists`, print and exit 1 on a survivor. The diagnostic names
`partial_tests_failing_escalate` in the implementation file and
`scope_changed_escalate` in the analysis file — each phase's own route to a
terminal state.

**Acceptance Criteria**:
- Both phase files carry the block over `plan.md` on their own retry outcome.
- Each names its own escalate outcome in the diagnostic.
- Neither file's first-pass path changed.

**Dependencies**: None.

**Type**: implementation

**Files**: `skills/work-on/references/phases/phase-3-analysis.md`, `skills/work-on/references/phases/phase-4-implementation.md`

**Complexity**: testable

### Issue 3: fix(work-on): clear summary.md on the finalization retry

**Goal**: Neither `finalization` nor `deferral_approval` is satisfied by a
`summary.md` written before the fixes that follow an `issues_found`.

Add the clearing block over `summary.md` to `phase-5-finalization.md` on the
`finalization_status: issues_found` path. Its diagnostic names
`deferral_requested`, which routes to `deferral_approval` — `finalization` has
no escalate edge, so the requirement that a terminal state stay reachable is met
by a different exit here than in the other phases, and the block must name the
one this state actually has.

`deferral_approval` gates on the same key and is entered exactly once, which
makes it look safe. It is not: `finalization` upstream sits on a cycle, so that
single entry can happen carrying a pre-fix summary. Clearing on the
`issues_found` edge is what covers it.

**Acceptance Criteria**:
- `phase-5-finalization.md` carries the block over `summary.md` on
  `issues_found`.
- The diagnostic names `deferral_requested`, not an escalate outcome the state
  does not accept.

**Dependencies**: None.

**Type**: implementation

**Files**: `skills/work-on/references/phases/phase-5-finalization.md`

**Complexity**: simple

### Issue 4: docs(work-on): state the retry contract in the panel orchestration reference

**Goal**: The reference a maintainer reads to understand the three-panel retry
loop says what a `blocking_retry` does to all three artifacts.

`review-panel-orchestration.md` describes the retry cap and the outcomes each
panel accepts but says nothing about the artifacts. Add the all-three clearing
contract: a retry from any panel invalidates every panel's verdict, because the
return trip through `implementation` changes the code all three reviewed.

**Acceptance Criteria**:
- The reference states that a `blocking_retry` clears all three panel keys, from
  whichever panel raised it.
- It does not restate the block itself; the phase files own that.

**Dependencies**: Blocked by Issue 1.

**Type**: docs

**Files**: `skills/work-on/references/review-panel-orchestration.md`

**Complexity**: trivial

### Issue 5: test(work-on): drive the shipped clearing blocks against real koto

**Goal**: Every claim the three preceding issues make is demonstrated against a
real koto session running the real template, not asserted in prose.

Write `skills/work-on/scripts/retry-clearing_test.sh`, modelled on
`skills/execute/scripts/settled-branch-record_test.sh`: extract the shipped
blocks out of the phase files at run time with an `extract_block` awk pass,
point `HOME` at a temp tree so no session lands in the developer's `~/.koto`,
and skip cleanly with exit 0 when koto is absent from PATH.

The suite must NOT paste copies of the blocks. It extracts them, which is what
makes an edit to a shipped block fail here.

Cases, in order:

- Each of the six gates: key removed, the phase's advancing outcome does not
  advance, and koto's response names the gate.
- Each of the six: key present, the advancing outcome advances. First-pass
  parity.
- Traversal from each of the three panel entry points: after a `blocking_retry`
  raised at that panel, all three panel keys are absent and no panel advances on
  `passed`.
- Both edges into `analysis` clear `plan.md`, driven separately — a case for
  `scope_expanded_retry` and a case for `scope_changed_retry`. They are
  different edges in different files and one can ship without the other.
- `issues_found` clears `summary.md`, and neither `finalization` nor
  `deferral_approval` then advances on it.
- The block exits 0 when a key it removes was never written.
- With the ctx directory made unwritable: the block exits non-zero, prints on
  stdout with stderr sent to `/dev/null`, and names both the outcome to avoid
  and the escalate outcome.
- With the store still broken, each escalate outcome still reaches its terminal
  state: `blocking_escalate` → `done_blocked` from each panel,
  `scope_changed_escalate` and `blocked_missing_context` → `done_blocked` from
  `analysis`, `partial_tests_failing_escalate` → `done_blocked` from
  `implementation`, `deferral_requested` → `deferral_approval` from
  `finalization`. Driven against koto, not read off the template.
- The three panel blocks are byte-identical below their first line.

Every case must be able to fail. A branch whose both arms are a no-op is not an
assertion, and the cleanup trap must restore write permission on the locked
directory or `rm -rf` cannot finish.

**Acceptance Criteria**:
- The suite passes locally with koto v0.11.5 or later on PATH.
- It exits 0 with a loud SKIP when koto is absent.
- Deleting a clearing block from any of the six phase files makes it fail.
- Every case's assertion is reachable in both directions.

**Dependencies**: Blocked by Issue 1, Issue 2, Issue 3.

**Type**: test

**Files**: `skills/work-on/scripts/retry-clearing_test.sh`

**Complexity**: complex

### Issue 6: ci(work-on): register the work-on shell suite

**Goal**: The harness runs on every PR that touches the scripts it checks, and
on the bash 3.2 floor.

Add a `work-on` suite to `scripts/check-bash-floor.sh`: append it to `SUITES`
and add its `suite_scripts` arm naming `skills/work-on/scripts/retry-clearing_test.sh`.
Add `.github/workflows/check-work-on-scripts.yml` modelled on
`check-execute-scripts.yml`: an ubuntu leg that installs tsuku and runs
`tsuku install -y` so koto arrives through the project tool manifest and the
assertions genuinely execute, and a macOS leg running
`scripts/check-bash-floor.sh --backend system work-on` for portability of the
shell itself.

The workflow's `paths:` filter must include the phase files, not only the script
directory. The harness reads the shipped blocks out of those files, so a change
to a phase file can break it while leaving `skills/work-on/scripts/**`
untouched.

**Acceptance Criteria**:
- `scripts/check-bash-floor.sh --list` shows the `work-on` suite.
- The workflow's `paths:` covers `skills/work-on/scripts/**`,
  `skills/work-on/references/phases/**`, and `scripts/check-bash-floor.sh`.
- The suite passes on the bash 3.2 floor.

**Dependencies**: Blocked by Issue 5.

**Type**: infrastructure

**Files**: `scripts/check-bash-floor.sh`, `.github/workflows/check-work-on-scripts.yml`

**Complexity**: simple

### Issue 7: test(work-on): update and run the evals

**Goal**: `/work-on`'s evals reflect the changed phase contract and are run, not
merely edited.

Update `skills/work-on/evals/evals.json` wherever an assertion describes the old
retry behaviour — in particular any assertion resting on the overwrite-to-clear
statement removed from `phase-4a-scrutiny.md`. Then run them: spawn an agent
with `/skill-creator` loaded and have it run `scripts/run-evals.sh work-on`.

Per CLAUDE.md, the CI existence check is not a substitute for running them. Fix
failing assertions before committing.

**Acceptance Criteria**:
- No eval assertion refers to a mechanism the phase files no longer describe.
- `scripts/run-evals.sh work-on` has been run and its failures fixed.

**Dependencies**: Blocked by Issue 1, Issue 2, Issue 3, Issue 4.

**Type**: test

**Files**: `skills/work-on/evals/evals.json`

**Complexity**: simple

## Implementation Sequence

**Batch 1 — the clearing blocks (issues 1, 2, 3).** Independent of each other
and of everything else; any order, and they can land together. Issue 1 is the
largest and carries the prose rewrite, so open with it.

**Batch 2 — prose and the harness (issues 4, 5).** Issue 4 needs only issue 1.
Issue 5 needs all of batch 1 on disk, since it extracts the shipped text. Issue
5 is the long pole: it is the only complex item and the one most likely to send
work back to batch 1, because a block that cannot be driven against real koto is
a block that needs rewriting.

**Batch 3 — wiring and evals (issues 6, 7).** Issue 6 needs a harness that
passes locally before it is worth putting on a runner. Issue 7 needs the phase
files final.

## References

- `docs/designs/DESIGN-work-on-retry-clearing.md` — the upstream design.
- `skills/execute/scripts/settled-branch-record_test.sh` — the harness pattern
  issue 5 follows: shipped-text extraction, `HOME` redirection, clean skip on a
  missing koto.
- `.github/workflows/check-execute-scripts.yml` — the workflow shape issue 6
  follows, including the tsuku install that brings koto to the ubuntu leg.
- `tsukumogami/koto#196` — the change that added `koto context remove`, released
  in koto v0.11.5.
