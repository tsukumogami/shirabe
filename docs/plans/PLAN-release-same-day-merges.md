---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
upstream: docs/designs/DESIGN-release-same-day-merges.md
milestone: "Release same-day merges"
issue_count: 2
---

# PLAN: One PR set for a release, derived from its commits

## Status

Active

Decomposition of
[DESIGN-release-same-day-merges](../designs/DESIGN-release-same-day-merges.md),
closing issue #321. Two outlines, one pull request, no GitHub issues.

## Scope Summary

`skills/release/SKILL.md` derives a release's pull request membership twice and
the second derivation, keyed on the undefined `$LAST_TAG_DATE`, drops every
pull request merged on the previous tag's calendar day -- from the release
notes and from the Phase 2 security-labeled-PR precondition. The design settles
the mechanism: Phase 1 derives the set once from the commit range it already
establishes, parsing the `(#N)` suffix squash-merge writes into commit
subjects, and Phases 2 and 3 read that one value. Phase 1 also emits the
commits in the range that carry no pull request reference.

This plan covers the prose rewrite of three sections of `skills/release/SKILL.md`
and the two eval scenarios that pin the behavior at each call site. It covers
nothing else: no CLI subcommand, no workflow file, no other precondition check.

## Decomposition Strategy

**Horizontal, two units, one pull request.**

The design is a prose change to one skill plus its evals, so the slicing axis is
artifact rather than layer: one unit changes the skill, one changes the evals
that assert the skill's new behavior. The grouping rule is one issue per file
under `skills/release/`.

Execution mode is `single-pr` under the repository's default `consolidated`
delivery preference, so no split rationale is owed. The two units could not
usefully land separately in any case: eval scenarios asserting a behavior the
skill does not yet describe would fail on the first unit's absence, which is
why Issue 2 is sequenced behind Issue 1 rather than run beside it.

One cross-unit edge: Issue 2 depends on Issue 1.

## Issue Outlines

### Issue 1: fix(release): derive the release PR set from the commit range

**Goal**: Rewrite Phases 1, 2, and 3 of `skills/release/SKILL.md` so a
release's pull request set is derived once, in Phase 1, from the commit range,
and both consumers read it.

**Acceptance Criteria**:
- [x] Phase 1 names the release range and derives the pull request set from it,
      parsing the `(#N)` suffix anchored to the end of the commit subject, and
      states the squash-merge assumption the parse rests on.
- [x] Phase 1 also derives the commits in the range that carry no pull request
      reference.
- [x] The derivation reaches its consumers. Each phase block runs as its own
      shell invocation, so the three values are written to files under `wip/`
      rather than left in shell variables; review caught this and it is the
      difference between the fix working and the security precondition passing
      on an empty list.
- [x] Phase 2's sixth precondition reads labels for the derived set rather than
      running a `merged:>` search, and its treatment guidance (read the PR
      first, recommend one of standard/redacted/excluded, name the tiebreaker)
      keeps its shape. One sentence of it did change: the tiebreaker is now
      named on every recommendation rather than only on a borderline call. That
      was not planned here; it came out of the eval run, and the reasoning is in
      commit `ff61187`.
- [x] Phase 3 step 1 reads the range from the carrier and step 2 cross-checks
      the derived set against the subjects it gathered, rather than running a
      `merged:>` search.
- [x] Phase 1 prints the unattributed-commit list before the notes are drafted,
      which is what R4 requires, and Phase 3 step 5 reprints it beneath them.
- [x] `grep -c 'LAST_TAG_DATE' skills/release/SKILL.md` returns 0.
- [x] Executing the rewritten Phase 1 derivation against `v0.17.0..4859557`
      yields a set containing `297`, and executing the rewritten Phase 2 label
      read over that set inspects `297`'s labels. Both transcripts are recorded
      in the pull request body rather than asserted.
- [x] The `--dry-run` path and the first-release path (`LAST_TAG` empty) still
      behave as the skill describes; the Error Recovery table is consistent
      with the rewritten phases.
- [x] No file under `.github/workflows/` is modified and no CLI subcommand is
      added.

**Dependencies**: None.

**Type**: docs
**Files**: `skills/release/SKILL.md`

### Issue 2: test(release): cover same-day merges at both call sites

**Goal**: Add eval scenarios to `skills/release/evals/evals.json` that assert
the same-day-merge behavior at the Phase 2 precondition and the Phase 3 gather,
and run the suite.

**Acceptance Criteria**:
- [x] `skills/release/evals/evals.json` carries a scenario whose prompt names a
      pull request merged after the previous tag's timestamp but before the end
      of that tag's calendar day, asserting the Phase 3 gather includes it.
- [x] It carries a second scenario asserting the Phase 2 security precondition
      evaluates that same pull request, so a security-labeled change merged in
      that window reaches the describe/redact/exclude decision.
- [x] Each new scenario asserts the same-day condition specifically -- the
      assertions name the boundary, not the phase in general -- and at least one
      asserts that no `merged:>` date search is used.
- [x] `scripts/run-evals.sh release` has been run by an agent with
      `/skill-creator` loaded, per `CLAUDE.md` section "Skill Evals", and its
      results are reported in the pull request body.
- [x] Any failing assertion is fixed before the pull request is marked ready.
- [x] The pre-existing seven scenarios still pass, or a change to one is
      explained.

**Dependencies**: Blocked by Issue 1.

**Type**: docs
**Files**: `skills/release/evals/evals.json`

## Implementation Sequence

Two units on one branch, sequential. There is no parallelism to exploit and no
critical path worth drawing separately from the dependency.

1. **Issue 1** -- the skill rewrite. Open here: the eval assertions are written
   against the behavior this unit describes, so writing them first would pin
   text that does not exist yet. Verify against the real v0.17.0 to v0.18.0
   case as part of this unit and capture the transcripts, since that evidence
   is the pull request's claim that the defect is fixed.
2. **Issue 2** -- the evals. Add the two scenarios, then delegate
   `scripts/run-evals.sh release` to an agent with `/skill-creator` loaded and
   fix any failing assertion.

Then the shared close-out: `shirabe validate` over every changed document, the
lifecycle cascade that retires this PLAN and moves the upstream chain to its
terminal states, and the cleanup that removes this topic's non-durable scratch
files before the pull request can merge.

## References

- `docs/designs/DESIGN-release-same-day-merges.md` -- the upstream design.
- `skills/release/SKILL.md` -- the artifact both issues change.
- `CLAUDE.md` sections "CLI Surface" and "Skill Evals" -- the two constraints
  the acceptance criteria encode.
