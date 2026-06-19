# Testability Review

## Verdict: PASS

Every requirement R1-R22 is independently testable, each AC is binary pass/fail against a recorded or inspectable artifact, all requirements are covered, and the four prior failures plus the two missing edge-case ACs are resolved.

## Issues Found

None blocking. Minor observations (non-blocking, do not affect verdict):

1. R2b / R18 ("smart defaults ... announce themselves"): the announcement is now made objectively testable by R18's AC ("emits an announcement in the invocation output naming the behavior and its override"). An output-string assertion is binary. Resolved — noting only that the test must assert on captured invocation output, which the AC states.
2. R8 AC ("the spent PLAN is gone from the record before it merges"): "gone" is binary and checkable (presence/absence of the PLAN artifact on the record at merge gate). Acceptable as written.

## Resolution of prior-pass failures

- **R5 "reviewer can read the whole effort" (subjective) -> RESOLVED.** R5 now states durable documents (BRIEF/PRD/DESIGN/PLAN) held on the record; its AC checks concrete contents present at creation: "contains the PLAN, the upstream BRIEF/PRD/DESIGN, and a per-repo PR index." Presence check, binary.
- **R11 "too large to review" (subjective) -> RESOLVED.** R11 now binds the split trigger to a "workspace's configured reviewability ceiling" (a recorded preference), and Decisions/Trade-offs explicitly converts the subjective judgment into "an objective, recorded check." AC requires a documented split trigger that "is recorded." Binary.
- **R18 "visible announcement" (subjective) -> RESOLVED.** R18 AC requires an announcement "in the invocation output naming the behavior and its override, and is suppressible/overridable by an explicit flag." Output-string and flag-behavior assertions, binary.
- **R17 needing an inspection check -> RESOLVED.** R17 AC now reads "By inspection, a single canonical definition of the capstone contract exists, and /scope, /work-on, and the CLI reference it without restating it." This is an inspection-based structural check (one source of truth + three references, no restatement), binary.

## Edge-case coverage

- Cyclic merge order (R13): covered — AC "never emits a merge order with a cycle; rejected or auto-resolved." Binary.
- Atomic refusal (R16): covered — AC "refused with reshaping guidance rather than producing a plan that assumes simultaneous merge." Binary.
- Context-reset (R9): covered — AC "re-discovers the active capstone from durable state, with no separate session file required." Binary.
- Default-ON-overridden-OFF (previously MISSING) -> NOW PRESENT. AC: "With the workspace default ON, an effort run with a per-invocation override to OFF produces no coordinating record and the current single-repo behavior. (R1, R2, R3)" Binary.
- Cascade partial-failure (previously MISSING) -> NOW PRESENT. AC: "If the cross-repo finalize/consume cascade fails partway, the coordinating record does not merge and the failure is surfaced. (R8, R21)" Binary.
- Abandonment (R20): covered — AC "closes the coordinating record without merging and leaves its planning artifacts in a documented state, not silently orphaned." Binary.
- Mid-effort PLAN change (R22): covered — AC "Editing the PLAN mid-effort re-derives the PR index and merge order." Binary.

## Coverage Gaps

None. Requirement-to-AC map (R1-R22; note R18/R19 are the Non-functional entries, so the set R1-R22 is complete with no missing numbers):

- R1: AC1, AC2, AC5
- R2: AC2 (R2a), AC5, AC18 (R2b)
- R3: AC3, AC5
- R4: AC1
- R5: AC4
- R6: AC6
- R7: AC7
- R8: AC8, AC9
- R9: AC10
- R10: AC11
- R11: AC12
- R12: AC13
- R13: AC14
- R14: AC7
- R15: AC15
- R16: AC16
- R17: AC17
- R18: AC18
- R19: AC19
- R20: AC20
- R21: AC9, AC21
- R22: AC22

Every requirement has >= 1 covering AC.

## Non-functional observability

- R18 observable: yes — invocation-output assertion + flag override behavior.
- R19 observable: yes — AC asserts "No new long-running service or state store is introduced; coordination uses only the record, git/gh, and niwa worktree creation," verifiable by inspecting the dependency/service surface.
- R17 inspection-based: yes — see resolution above; structural single-source-of-truth + reference-without-restatement inspection.

## Summary

The revised PRD resolves all four prior testability failures: R5 and R11 replaced subjective phrasing with concrete presence checks and a configured reviewability ceiling, R18's announcement became an output-string-plus-flag assertion, and R17 is now an inspection-based single-source check. Both previously-missing edge-case ACs (default-ON-overridden-OFF, cascade partial-failure) are present and binary. All R1-R22 are independently testable, each AC is pass/fail, and every requirement maps to at least one AC with no coverage gaps.
