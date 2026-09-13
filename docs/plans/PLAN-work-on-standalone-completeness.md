---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "Work-on standalone completeness"
issue_count: 10
upstream: docs/designs/DESIGN-work-on-standalone-completeness.md
---

# PLAN: work-on standalone completeness

## Status

Active

Tracking level `none`: this plan files no GitHub issues, so the Draft to Active
gate auto-fires rather than waiting for approval.

## Scope Summary

The completeness work from `DESIGN-work-on-standalone-completeness.md`: making
the document-chain cascade reachable from a single-issue run, converting the
finishing obligations from prose into enforced states, and relocating the shared
cascade machinery. The multi-pr migration described in the same design is **not**
in this plan and becomes its own, afterwards.

## Decomposition Strategy

**Walking skeleton**, and the skeleton is chosen for the integration risk rather
than by default.

The riskiest thing in this work is not any individual gate — it is whether a
single tick behaves as the design assumes as it crosses the new states. That
semantic has now been stated wrongly three times in one afternoon by people
reading the source: an `accepts:` block does not stop a tick chaining through a
state, only a conditional transition does. So the first issue builds the three
graph elements with minimal bodies and proves a tick stops where it should. Every
later issue thickens a state that already exists and whose traversal behaviour is
pinned by a test.

Building the gates first and the graph last would invert that: each gate would
be individually correct and the integration defect would surface at the end,
which is the shape this repository has just spent a day paying for.

### Why this is one pull request and not several

Recorded here so the mode is not re-litigated later.

The units of this work are not independently valuable. `cascade_entry` without
`cascade_run` is a state that routes into nothing. The script relocation without
the matching repoint breaks `/execute`. Splitting them would produce pull
requests that are not standalone increments, which is exactly what the
value-confirmation guard exists to catch — so multi-pr fails its own test here
rather than being merely unattractive.

The repository declares no Delivery Preference, so the default is `consolidated`
and one PR is the expected shape. No split trigger fires, so no
`split_rationale` is recorded.

A separate constraint the modes cannot express is worth naming: the accepted PRD
requires this work and the migration to land as two ordered pull requests in one
repository, and shirabe has no execution mode for that — `pr_group` exists only
under `coordinated`, which is the multi-repo mode. The ordering is instead
enforced structurally, by the migration's plan not existing until this one lands.
That is sturdier than an instruction, but it is a workaround, and it has been
filed as such rather than absorbed silently.

## Issue Outlines

### Issue 1: Skeleton: the three graph elements, and a test that pins tick traversal

**Complexity**: critical

**Goal**: Add `cascade_entry`, `cascade_run` and the `partial` edge into
`done_blocked` to `work-on.md` with minimal bodies, wired so a tick traverses
them as the design specifies. Prove it with a test before anything is thickened.

**Acceptance Criteria**:

- [ ] `cascade_entry` exists, carries no `accepts:` block, and both its outgoing
      edges are gate-decided.
- [ ] `cascade_run` exists and carries **at least one conditional transition**
      (routing on `cascade_status`), not merely an `accepts:` block.
- [ ] A test drives a single tick from `ci_monitor` through to a terminal and
      asserts what that one invocation did — not what each state would do in
      isolation.
- [ ] **That test fails if `cascade_run`'s transitions are made
      all-unconditional**, even with its `accepts:` block left in place. This is
      the criterion's whole point: collapsing three edges into one is a tempting
      simplification because two share a target, it leaves the evidence block
      untouched, and a reviewer asking "does this state still require evidence?"
      sees nothing wrong. Only a driven tick catches it.
- [ ] A run with no anchor reaches a terminal without the tick stopping at
      `cascade_run`.
- [ ] `scripts/validate-template-mermaid.sh`, `check-template-directives.sh` and
      `check-template-interpolation.sh` pass.

**Dependencies**: None

### Issue 2: Relocate the cascade script, repoint `/execute`, and guard the path

**Complexity**: testable

**Goal**: Move `run-cascade.sh` and `run-cascade_test.sh` from
`skills/execute/scripts/` to `skills/work-on/scripts/`, repoint `execute.md`'s
invocation, and add a fail-closed existence assertion on the relocated path.

**Acceptance Criteria**:

- [ ] Both files live under `skills/work-on/scripts/` and the existing cascade
      test suite passes unchanged at the new location.
- [ ] `execute.md` invokes the relocated path; no reference to the old path
      remains anywhere in the repository.
- [ ] A fail-closed assertion on the relocated path runs **before the cascade
      mutates anything**, so an unresolved `${CLAUDE_PLUGIN_ROOT}` fails early
      rather than mid-cascade. Verified by pointing it at a tree without the
      script and observing the failure precedes any transition.
- [ ] `skills/work-on/` contains no reference to any path under
      `skills/execute/`.
- [ ] Both skills' `requires.tsv` reflect the move.

**Dependencies**: None

### Issue 3: Anchor detection gate on `cascade_entry`

**Complexity**: testable

**Goal**: Implement the `command` gate that searches `docs/plans/` for a PLAN
whose Implementation Issues table names this issue, routing `cascade_entry`'s
two edges.

**Acceptance Criteria**:

- [ ] An issue named in a PLAN's table is detected; one that is not is not.
- [ ] The search pattern is **anchored**, so an issue number cannot match as a
      substring of another and cascade the wrong chain. **Review obligation:**
      nothing mechanical enforces this — `check-template-interpolation.sh` does
      not cover it — so the anchoring is checked by a reviewer when the gate is
      written, and the pull request says it was.
- [ ] A caller-supplied plan path short-circuits the search when present.
- [ ] A run with no anchor emits no cascade-related output at all: the no-anchor
      path produces no agent-facing cascade language.

**Dependencies**: <<ISSUE:1>>

### Issue 4: `cascade_run`'s evidence: the observed post-state, read from the commit

**Complexity**: critical

**Goal**: Give `cascade_run` its evidence schema: `cascade_status` plus the three
facts that constitute a completed cascade, with the commit half read from the
commit's own paths.

**Acceptance Criteria**:

- [ ] Evidence comprises: the anchor absent from disk; each upstream document at
      its expected status; and the finalization commit containing each of those
      documents.
- [ ] The third fact is established **from the commit** (listing the commit's own
      paths), not from the working tree.
- [ ] **A test fails when a document is transitioned on disk but missing from the
      finalization commit.** That is the exact state the cascade's staging defect
      produces, so it is the case this evidence must be able to see. If it cannot
      be constructed in the harness, the pull request says so explicitly and
      names what stands in its place rather than leaving the gap implicit.
- [ ] No criterion here depends on the cascade script's step-level `ok`, which is
      unreliable in six measured places and is being hardened separately.
- [ ] `partial` routes to `done_blocked` carrying the failing step's detail and
      the shape-specific recovery guidance; `completed` and `skipped` route to
      `done`.
- [ ] **The recovery guidance matches `/execute`'s for both partial shapes**,
      which R5 requires and which nothing else in this plan checks. Verified by
      comparing against `execute.md:735-740`: a refused transition *without*
      `commit` and `push` at `ok` leaves nothing published and recovery is local;
      a refused transition *with* them published what it reached, so the remote
      carries that commit and recovery is a follow-up commit or a revert rather
      than a reset. Two callers of one script must not disagree about what a
      partial result means.

**Dependencies**: <<ISSUE:1>>, <<ISSUE:2>>

### Issue 5: `session_role` branch on `ci_monitor`

**Complexity**: testable

**Goal**: Add the `session_role` evidence field and branching transition so a
child routes straight to `done` and a root routes toward `cascade_entry`.

**Acceptance Criteria**:

- [ ] **The child used in these tests must be one that reaches `ci_monitor`.**
      A single-pr child does not: it is dispatched with `SHARED_BRANCH`, submits
      `pr_status: shared` and routes straight to `done`
      (`work-on.md:762-766`), bypassing the new branch for reasons that have
      nothing to do with `session_role`. Testing with one would pass a broken
      implementation. Today the child that qualifies is a **coordinated** child,
      which works on its own branch and lands its own per-repo pull request
      (`skills/execute/SKILL.md:316`, `:359-361`). If no such child can be
      constructed in the harness, say so and name what stands in its place.
- [ ] A qualifying child session does not reach `cascade_entry` and therefore
      never runs the anchor search.
- [ ] A root session routes to `cascade_entry`.
- [ ] The role comes from the discriminator the terminal-record fix establishes,
      not from a second implementation. A search for a second root-versus-child
      test returns nothing.
- [ ] If that discriminator has not landed, the work escalates rather than
      inventing a parallel mechanism.

**Dependencies**: <<ISSUE:1>>

### Issue 6: Root-only record retention on the new terminal ticks

**Complexity**: critical

**Goal**: Ensure every terminal tick this work introduces retains its context
record when a root session runs it, and that no child ever requests retention.

**Acceptance Criteria**:

- [ ] A root session's terminal tick retains its record.
- [ ] **No child session requests retention**, and its parent's child-completion
      gate still converges. Demonstrated by running a parent to convergence over
      a child that reaches one of the new terminal states — which, per Issue 5,
      means a child that reaches `ci_monitor` in the first place. A single-pr
      child never gets there and would make this vacuous.
- [ ] A regression test fails if the behaviour is made unconditional — the
      template is also the child template, so an unconditional edit hands the
      flag to every child and wedges its parent.
- [ ] The mechanism is the one the terminal-record fix established, not a second
      implementation.

**Dependencies**: <<ISSUE:1>>, <<ISSUE:5>>

### Issue 7: `merge_state_clean` gate on `ci_monitor`

**Complexity**: simple

**Goal**: Add the merge-cleanliness gate, copied verbatim from `execute.md`.

**Acceptance Criteria**:

- [ ] The gate command is **byte-identical** to `execute.md`'s, as
      `validate-template-mermaid.sh` check 4 requires for a gate name shared
      across templates.
- [ ] A dirty merge state blocks; a clean one passes.

**Dependencies**: None

### Issue 8: Closing-keyword gate on `pr_creation`

**Complexity**: testable

**Goal**: Convert the closing-keyword obligation from prose into a gate.

**Acceptance Criteria**:

- [ ] A pull request body without the closing keyword fails the gate.
- [ ] The check uses `gh`, so it observes the real pull request rather than the
      agent's report of it.
- [ ] The obligation is removed from prose where it now duplicates the gate, or
      the prose explicitly defers to it.

**Dependencies**: None

### Issue 9: The pre-PR evidence state and the classification table

**Complexity**: critical

**Goal**: Add the new state between `finalization` and `pr_precheck` carrying the
pre-PR obligations, and commit the classification table.

**Acceptance Criteria**:

- [ ] Every obligation is classified **gate-enforced** or **evidence-carried**,
      recorded in a committed table naming the obligation, its class, and where
      it is enforced or carried. None is left in neither category.
- [ ] Each classification is correct rather than merely present: a gate-enforced
      row names a gate that exists on the state it names and fails when driven to
      failure; an evidence-carried row names a field the state's schema marks
      required.
- [ ] Each evidence field is typed to a **concrete referent** — a path, a commit
      identifier, or a named command's output — and a placeholder or empty value
      fails the state rather than satisfying it. Demonstrated per field.
- [ ] The design-diagram obligation is either within one reference-hop with an
      evidence field, or explicitly recorded as advisory with the reason.
- [ ] `finalization`'s existing three-way branch is untouched.

**Dependencies**: <<ISSUE:1>>

### Issue 10: Reachability sweep, mermaid companion, and declarations

**Complexity**: simple

**Goal**: Move the converted obligations out of prose where they now live in
states, update the mermaid companion, and reconcile both `requires.tsv` files.

**Acceptance Criteria**:

- [ ] For every obligation this work introduces or moves, the pull request names
      **the file it lands in and the state whose prose leads a child to it.** An
      obligation that cannot name the second half does not reach a child and is
      not done.
- [ ] Nothing this work introduces lives only in `skills/work-on/SKILL.md`.
- [ ] The mermaid companion has one entry per new state.
- [ ] Both `requires.tsv` files declare every new tool call.
- [ ] **Every stated cardinality in the changed documents matches its own
      enumeration.** A count that disagrees with the list it refers to is a
      findable defect and a reviewer should not be the thing that finds it; this
      plan's own design got it wrong twice. If asserting this mechanically is
      cheap given what `shirabe validate` already parses, do it; if not, it stays
      a review obligation and this work does not grow the validator.

**Dependencies**: <<ISSUE:1>>, <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>, <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>>

## Implementation Sequence

**Critical path:** 1 → 5 → 6 → 10. The skeleton must exist before the role
branch, which must exist before retention can be made root-only, and the sweep
closes last because it reconciles what everything else produced.

**Available immediately, in parallel with the skeleton:** issues 2, 7 and 8. None
touches the new states. Issue 2 is worth starting early despite not blocking the
skeleton, because issue 4 needs it.

**After the skeleton:** 3, 4, 5 and 9 open together. Issue 4 also waits on 2.

**Last:** 10, which depends on everything because its reachability sweep and its
cardinality check are assertions about the finished state of the work.

**The one to do first and get right:** issue 1. Its test is the most important
criterion in this plan. The traversal semantic it pins has been stated wrongly
three times by people reading the source, and every other issue in this plan
assumes it. If it is wrong, the rest is built on sand and the failure appears at
the end.
