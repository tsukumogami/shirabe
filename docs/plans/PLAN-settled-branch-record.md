---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-settled-branch-record.md
milestone: "settled-branch record"
issue_count: 4
---

# PLAN: settled-branch-record

## Status

Active

## Scope Summary

Make `/execute`'s `orchestrator_setup` record the settled branch with a command
that exists, verify the record took, and bind that guarantee to the koto state
machine so the run cannot dispatch children against a branch it never settled on.

## Decomposition Strategy

Horizontal. The design names two edits with a clear seam between them — the
directive's shell block and the template's state definitions — plus a test and a
prose reconciliation. They are not layers of one runtime pipeline, so a walking
skeleton has nothing to skeletonize: there is no end-to-end path to thin out that
is not already one state's worth of work.

The ordering constraint is real but narrow. The gate (Issue 2) is meaningless
without the write it gates on (Issue 1), and the test (Issue 3) needs both. The
prose reconciliation (Issue 4) needs the gate to exist so it can describe it
accurately, but nothing needs the prose. That yields a chain with one leaf hanging
off the middle rather than a diamond.

Execution mode is **single-pr**. Neither escape condition holds: no cross-repo
landing order, no workflow that must reach main before it can be invoked, no merge
gate between steps. And the units are not independently useful — a merged Issue 1
without Issue 2 is the prose-only alternative the design explicitly rejected, and
a merged Issue 2 without Issue 1 gates on a key nothing writes. Landing them as
separate PRs would ship two states each of which is worse than either the
before or the after.

The design's implementation approach lists five steps; this plan has four issues.
The missing one is the sweep of the skills tree for the same defect shape, which
was discharged during `/design` rather than deferred: its result is recorded in
`DESIGN-settled-branch-record.md`'s Consequences, and the second instance it found
is filed as tsukumogami/shirabe#304. Nothing here re-does it.

## Issue Outlines

### Issue 1: fix: record the settled branch with a command that exists

**Complexity**: testable

**Goal**: Replace `koto context set` with a working write in the
`orchestrator_setup` directive, and verify in the same block that the value came
back out.

**Acceptance Criteria**:
- [x] The recording line reads `printf '%s' "$SETTLED_BRANCH" | koto context add {{SESSION_NAME}} settled_branch` -- `printf '%s'` and not `echo`, so no trailing newline enters the store
- [x] The block reads the value straight back and compares it to `$SETTLED_BRANCH`, and on mismatch prints a diagnostic naming the step, the value read, and the value expected
- [x] Both that diagnostic and the pre-existing `refusing unsafe settled branch` message are written to **stdout**, not stderr, so `2>/dev/null` does not swallow them
- [x] The directive prose tells the agent to submit `status: blocked` -- not `completed`, not `override` -- when the comparison fails
- [x] Running the block twice against the same session leaves one `settled_branch` key with the same value and no error on the second run
- [x] `spawn_and_await`'s read block is unchanged: `git diff` shows no edit inside either of its two ticks
- [x] CI green

**Dependencies**: None.

**Type**: code
**Files**: `skills/execute/koto-templates/execute.md`

---

### Issue 2: fix: gate orchestrator_setup on the recorded branch

**Complexity**: testable

**Goal**: Add a `context-matches` gate on `orchestrator_setup` and reference it
from the `completed` and `override` transitions, so the state cannot advance to
`worktree_discipline_check` without a well-formed recorded branch.

**Acceptance Criteria**:
- [x] `orchestrator_setup` declares a gate named `settled_branch_recorded` of type `context-matches`, keyed on `settled_branch`, with the pattern anchored at both ends as `^[A-Za-z0-9._/-]+$`
- [x] The `completed` and `override` transitions each carry `gates.settled_branch_recorded.matches: true` in their `when` clause
- [x] The `blocked` transition carries no gate reference, so a run with an unwritable store can still reach `done_blocked`
- [x] The template still compiles: `koto template compile` (or the repo's template-validation scripts) accepts the edited file and names no unresolved reference
- [x] The directive prose names the gate and says what to check when the state will not advance, in the shape `worktree_discipline_check`'s existing note uses for its own gate
- [x] No new entry is added to the template's `variables:` block -- `{{SESSION_NAME}}` is a koto runtime variable
- [x] CI green

**Dependencies**: Blocked by Issue 1.

**Type**: code
**Files**: `skills/execute/koto-templates/execute.md`

---

### Issue 3: test: prove the round trip and the fail-closed stop

**Complexity**: testable

**Goal**: A runnable test that demonstrates the adopt-path round trip and the
fail-closed behaviour, so both are evidence rather than assertions.

**Acceptance Criteria**:
- [x] The test drives a real koto session: it writes a branch name through the Issue 1 block and reads it back the way `spawn_and_await` does, asserting the two strings are byte-equal
- [x] The positive case uses an adopt-path-shaped branch name (`docs/<topic>`, not `impl/<slug>`), so a fallback that silently substituted `impl/<slug>` would fail the assertion
- [x] The negative case asserts that with the key absent the gate reports `matches: false` and `orchestrator_setup` does not advance on `status: override`
- [x] A third case asserts a value containing a shell metacharacter is rejected by the gate, which fails if a later edit drops either anchor from the pattern
- [x] The test passes locally and its output shows the compared strings, not just a pass line
- [x] It is wired into the `execute` suite of `scripts/check-bash-floor.sh` and into `check-execute-scripts.yml`, whose Linux leg installs koto through the project tool manifest so the cases run for real. It parses under bash 3.2 and skips cleanly there; the 3.2 leg has no koto, so its cases do not execute on the floor
- [x] No existing test is modified; a test that would have to change is reported as a finding instead
- [x] CI green

**Dependencies**: Blocked by Issue 1, Issue 2.

**Type**: code
**Files**: `skills/execute/scripts/settled-branch-record_test.sh` (moved from the `scripts/` path this outline first named, so the existing `skills/execute/scripts/**` CI path filter and the `execute` floor suite pick it up without a new workflow)

---

### Issue 4: docs: reconcile SKILL prose and evals with the gate

**Complexity**: simple

**Goal**: Bring `skills/execute/SKILL.md` and the `/execute` evals into agreement
with the gate, changing only what the contract change actually touches.

**Acceptance Criteria**:
- [x] `skills/execute/SKILL.md`'s `orchestrator_setup` bullet names the gate and the fail-closed behaviour, so the prose contract and the template agree
- [x] Evals 26 and 27 are re-read against the new contract; each expectation that still holds is left byte-identical
- [x] Any eval expectation that changed is changed because the contract changed -- the gate is new; the read site's fallback is not -- and the diff makes which is which obvious
- [x] `scripts/check-evals-exist.sh` still passes
- [x] CI green

**Dependencies**: Blocked by Issue 2.

**Type**: docs
**Files**: `skills/execute/SKILL.md`, `skills/execute/evals/evals.json`

## Implementation Sequence

Critical path: Issue 1 to Issue 2 to Issue 3. Each link is a hard dependency —
the gate needs a key something writes, and the test needs both halves in place
before either case means anything.

Issue 4 hangs off Issue 2 and is off the critical path. It can be written as soon
as the gate exists and does not block Issue 3.

There is no parallelization worth naming. Issues 1 and 2 edit the same file, and
Issue 4's only sibling opportunity (running alongside Issue 3) saves nothing at
this size.
