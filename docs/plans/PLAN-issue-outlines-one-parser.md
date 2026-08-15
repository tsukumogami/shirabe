---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "One parser for the Issue Outlines section"
issue_count: 5
upstream: docs/designs/DESIGN-issue-outlines-one-parser.md
---

# PLAN: One parser for the Issue Outlines section

## Status

Active

## Scope Summary

Collapse the three readers of a single-pr PLAN's `## Issue Outlines` section
into one walk in `shirabe-validate`, expose it to the shell extractor through a
`shirabe plan outlines` subcommand, and promote the unresolvable-dependency
finding to an error under a new `FC17` while the cases that already fail closed
stay notice-level. Implements `docs/designs/DESIGN-issue-outlines-one-parser.md`.

## Decomposition Strategy

Horizontal, and the design's Decision Drivers are why. The components have a
clear prerequisite order rather than a runtime interaction to de-risk: the
record has to exist before a check can read it, before a subcommand can
serialize it, before a shell script can consume the serialization. There is no
end-to-end path to thin-slice — the "integration" here is one process boundary
whose shape is settled in the design, so a walking skeleton would build the
same five pieces in the same order while pretending the first was a throwaway.

Five issues, one per implementation step in the design's Implementation
Approach. Each is completable in a session and leaves the tree building and
green: the parser change preserves behavior, the check is additive, the
subcommand is additive, the extractor swap is behavior-preserving against its
existing suite, and the last is documentation and CI configuration.

Execution mode is **single-pr**. Neither escape condition holds. No hard
constraint forces multiple PRs: nothing here has to reach main before the next
step can be invoked, no merge gate sits between steps, and one repository is
involved. And the units are not independently useful — a `shirabe plan
outlines` subcommand with nothing calling it, or an extractor consuming a
subcommand that does not exist yet, is a building block a reader waits on
rather than observable value. The usable increment is the whole change: one
parser, both consumers, the error that stops the run.

The value-confirmation guard therefore has one unit to check, the PR itself,
and it passes: after it lands, a PLAN that validates clean extracts to the
graph its author declared, which is the outcome the PRD's user stories ask for.

## Issue Outlines

### Issue 1: refactor(validate): one walk of the Issue Outlines section

**Goal**: Replace `parse_issue_outlines` and `parse_outline_acs` with a single
`OutlineSection` walk carrying everything all three consumers need, and move
FC14 and L06 onto it.

**Acceptance Criteria**:
- [ ] One function walks `## Issue Outlines`. `parse_outline_acs` is gone and
      `check_l06` reads acceptance-criteria entries off the returned blocks.
- [ ] Only a heading matching `### Issue <N>: <title>` opens a block.
      `### Dependencies` opens a dependencies sub-section of the open block.
      Any other `### ` line inside the section is recorded in
      `nonconforming_headings` and is not a block boundary.
- [ ] Each block carries `number` and `title` parsed from its heading,
      `goal_declared`, `acceptance_criteria_declared`, the acceptance-criteria
      entries, `dependencies_declared`, `dependencies_none`, `waits_on` as
      resolved sibling numbers, `unresolved_dependencies` verbatim,
      `issue_type`, and `files`.
- [ ] Dependency values strip a trailing period before the `None` test, so
      `**Dependencies**: None.` resolves as an intentional absence and produces
      no finding.
- [ ] `**Dependencies:**` with the colon inside the bold parses identically to
      `**Dependencies**:`.
- [ ] Dependency references resolve against the numbers parsed from headings,
      not against outline position, so a non-consecutively-numbered PLAN
      resolves correctly.
- [ ] The acceptance-criteria tolerance is L06's: only the three canonical
      checkbox shapes count, and a non-canonical bullet is dropped without
      leaving the AC state.
- [ ] FC14 keeps its four sub-checks and their existing messages, reading the
      new fields, and reports a non-conforming heading at notice level.
- [ ] `cargo test --workspace` passes with no pre-existing test modified.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/checks.rs`

### Issue 2: feat(validate): FC17 errors on an unresolvable outline dependency

**Goal**: Give the unresolvable-dependency finding its own error-level check
code so a single-pr PLAN that would lose an edge fails validation instead of
emitting a notice.

**Acceptance Criteria**:
- [ ] A new `FC17` check emits one error-severity finding per entry in a
      block's `unresolved_dependencies`, naming the outline key, the token
      verbatim, and the accepted forms.
- [ ] `FC17` is registered in `is_known_check_code` so `--check FC17` selects
      it, and is absent from `is_intrinsic_notice` and from `posture_class`, so
      it is an error under both draft and ready posture.
- [ ] FC14 stays notice-level and keeps reporting its structural sub-checks and
      the non-conforming-heading finding at that level.
- [ ] A single-pr PLAN with `**Dependencies**: 3` exits non-zero under
      `shirabe validate`; the same PLAN with `**Dependencies**: Issue 3` and a
      third outline exits 0.
- [ ] `cargo test --workspace` passes with no pre-existing test modified.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`

### Issue 3: feat(cli): shirabe plan outlines emits the parsed section as JSON

**Goal**: Expose the single walk to out-of-process consumers through a `plan`
subcommand group whose `outlines` subcommand writes a versioned envelope to
stdout.

**Acceptance Criteria**:
- [ ] `shirabe plan outlines <PLAN.md>` writes one JSON object carrying
      `schema: "shirabe-plan-outlines/v1"`, the path, the execution mode, the
      outlines, and the non-conforming headings.
- [ ] Each outline entry carries number, title, key, line, the declared flags,
      `waits_on`, `unresolved_dependencies`, type, and files. Acceptance
      criteria are not in the envelope.
- [ ] Exit codes follow the established scheme: 0 when the document parsed, 1
      when it cannot be read or is not a PLAN, 3 on I/O failure. A document
      with unresolvable dependencies still exits 0 and reports them, because
      refusing is the consumer's call.
- [ ] The subcommand reads and never writes: no file is created, modified, or
      moved, and no reference out of the document is followed.
- [ ] `cargo test --workspace` passes with no pre-existing test modified.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe/src/main.rs`, `crates/shirabe/src/plan_outlines.rs`

### Issue 4: refactor(plan): plan-to-tasks reads the CLI instead of parsing

**Goal**: Delete the bash parsing loop, consume the envelope, and refuse rather
than emit a task set that is missing an edge.

**Acceptance Criteria**:
- [ ] `process_single_pr` contains no line-by-line parse of the section. It
      resolves a binary, calls `plan outlines`, and reads the envelope with
      `jq`.
- [ ] Binary resolution follows `run-cascade.sh`'s ladder — `$SHIRABE_BIN`,
      then `shirabe` on `PATH`, then a built release or debug binary — and a
      missing binary exits 1 with a message naming all three. There is no
      fallback parse.
- [ ] The script still works outside a git repository: the repo-root probe is
      best-effort and only feeds the built-binary fallbacks.
- [ ] The PLAN path is quoted and passed after `--`.
- [ ] An envelope whose `schema` is not `shirabe-plan-outlines/v1` is refused
      rather than read field by field.
- [ ] Any `unresolved_dependencies` in the envelope causes exit 2 naming each
      offending outline and token, before any task entry is built.
- [ ] An empty `outlines` list still exits 2 with the existing
      no-issue-outlines message, so the heading mismatch keeps failing closed.
- [ ] Naming, `o-` prefixing, 64-character truncation, collision suffixing,
      file-ownership edges, and task-entry assembly are unchanged.
- [ ] `bash skills/plan/scripts/plan-to-tasks_test.sh` passes with no
      pre-existing case modified. The harness gains a setup step that builds
      the binary and exports `SHIRABE_BIN`, copied from `run-cascade_test.sh`.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `skills/plan/scripts/plan-to-tasks.sh`, `skills/plan/scripts/plan-to-tasks_test.sh`

### Issue 5: docs(plan): record where the parse lives and widen the CI trigger

**Goal**: Point the contract at the single implementation and make the bash
suite run when the Rust parser it now depends on changes.

**Acceptance Criteria**:
- [ ] `plan-to-tasks-contract.md`'s single-pr section names the single
      implementation and the `shirabe plan outlines` surface, and states that
      an unresolvable reference is an error at validation and a refusal at
      extraction. The dependency and heading shapes it already documents are
      unchanged.
- [ ] The contract records the `shirabe` binary as a runtime requirement and
      names the resolution ladder.
- [ ] `.github/workflows/check-plan-scripts.yml` triggers on `crates/**` as
      well as `skills/plan/scripts/**`.
- [ ] No `wip/` path is referenced from any committed file.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: docs
**Files**: `skills/plan/references/plan-to-tasks-contract.md`, `.github/workflows/check-plan-scripts.yml`

## Implementation Sequence

The critical path is the whole plan: 1 → 3 → 4 → 5, with 2 hanging off 1.

Issue 1 is the only one with no predecessor, and everything else reads the
record it defines. Issues 2 and 3 are independent of each other and can run in
parallel once 1 lands — 2 adds a check that reads `unresolved_dependencies`, 3
serializes the same record, and they touch different files. Issue 4 needs the
subcommand to exist before it can call it. Issue 5 documents what 4 built and
widens the trigger that guards it, so it goes last.

Each ordering edge has a failure mode if inverted rather than being a tidiness
preference:

- **1 before 2.** FC17 reads `unresolved_dependencies`, which does not exist
  until the record does. Inverted, the check has nothing to read.
- **1 before 3.** The envelope serializes the record. Inverted, the subcommand
  defines its own shape and the JSON becomes a second statement of what an
  outline is — the duplication this plan removes, in a new place.
- **3 before 4.** The extractor calls the subcommand. Inverted, the bash suite
  fails against a binary with no `plan` group, and the pressure to keep the old
  parse as a fallback is exactly the option the design rejected on security
  grounds.
- **4 before 5.** The contract describes the surface the extractor uses.
  Inverted, it documents an arrangement that does not exist yet.

Verification runs at every step: `cargo test --workspace`, the bash suite from
issue 4 onward, and a whole-corpus validation diff against the baseline
captured before issue 1. The diff is expected to differ only in the ways the
PRD's Known Limitations enumerates — three fixtures losing a false-positive
`None.` finding, one fixture gaining an `FC17` error on its `#1` reference.

One check belongs at the end and not to any single issue: extract this PLAN's
own task graph and confirm the `waits_on` edges match the four declared above.
That check is how the defect was originally found, and running it against the
fixed extractor is the end-to-end demonstration the PRD's last criterion asks
for.
