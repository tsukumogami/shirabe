# Testability Review

## Verdict: PASS

Every acceptance criterion names a concrete input, an observable output (exit code, JSON parse, or named advisory text), and a posture, so a test plan can be written from the AC section alone — with two phrasing-dependent ACs that need tighter assertions and a handful of edge cases left uncovered.

## Per-Criterion Analysis

| AC | What I'd test | How I'd verify | Testable? |
|----|---------------|----------------|-----------|
| AC1 (draft-tolerable only, in-flight → exit 0) | Build a doc set triggering only L02/L06/L07; run in-flight | Assert exit code == 0 | Yes |
| AC2 (same set, review-ready → exit 2) | Same fixture, review-ready posture | Assert exit code == 2 | Yes |
| AC3 (always-enforced → exit 2 both postures) | Doc set with a parse failure or dependency cycle (L05/L03) | Assert exit 2 in-flight AND review-ready | Yes |
| AC4 (no posture arg → in-flight) | Run draft-tolerable-only set with no posture argument | Assert exit 0 | Yes |
| AC5 (#197 repro → exit 0 in-flight) | BRIEF at Draft, no downstream artifact, chain head | Assert exit 0 in-flight | Yes |
| AC6 (envelope still parses) | Run after change, capture JSON | Validate against `shirabe-validate/v1` schema + exit-code contract | Yes |
| AC7 (in-flight pass advisory names findings) | Draft-tolerable-only in-flight pass | Assert advisory text names each tolerated finding + "what it needs before ready" | Partially (see Untestable #1) |
| AC8 (review-ready failure advisory) | Draft-tolerable finding in review-ready | Assert advisory states "reverting to draft would pass" + names fixes | Partially (see Untestable #2) |
| AC9 (determinism) | Run identical docs + same posture in two environments | Assert identical exit code AND identical JSON | Yes |
| AC10 (classification documented) | Locate the documented classification | Assert single discoverable location exists and lists L02/L06/L07 vs L03/L04/L05 | Partially (see Untestable #3) |

## Untestable Criteria

1. **AC7 (advisory names each finding + "what it needs before ready")**: "what that finding needs before ready" is free prose with no asserted shape — a test can check that *some* text follows each finding name, but cannot verify the guidance is correct or useful without a human judging it. -> Specify the assertable contract: e.g. each tolerated finding's advisory line must contain the finding ID and a non-empty remediation clause, or pin expected substrings per finding in a golden/snapshot fixture.

2. **AC8 (review-ready failure advisory states reverting would pass)**: Same issue — "states that reverting to draft would pass" and "names what to fix" are subjective phrasings. Assertable only against an exact expected string. -> Pin the expected advisory substring(s) in a snapshot test (e.g. must contain "revert to draft" and the finding ID), so the assertion is mechanical rather than a reviewer judging tone.

3. **AC10 (documented in a single discoverable location)**: "discoverable" is subjective and "single location" has no machine check. A test can assert a known file contains the classification, but "discoverable" cannot be verified by a test. -> Name the expected file path (or assert exactly one file in the repo contains the full L02/L06/L07 + L03/L04/L05 mapping), turning it into a grep-count assertion.

## Missing Test Coverage

1. **R6 — always-enforced finding in review-ready posture**: AC3 covers always-enforced in *both* postures via a happy path, but no AC isolates a review-ready run where a draft-tolerable AND an always-enforced finding co-occur (does the exit-2 still fire, and does the advisory still explain correctly?). Add an AC for the mixed-finding review-ready case.

2. **R7 — L01 retains existing posture sensitivity**: R7 explicitly states "L01 remains posture-sensitive as it is today," but no AC exercises L01 to confirm it was not accidentally reclassified. Add an AC asserting L01 behaves identically before and after the change in both postures.

3. **R12 — `/scope` and cascade pass-through compatibility**: AC6 checks the envelope parses, but no AC verifies the actual downstream consumers (`/scope`, cascade) still consume the output successfully. Add an integration AC for at least one real pass-through caller.

4. **R13 / R9 — no network dependency on the gate path / context-read-but-not-gate**: R9 ("reading context to explain is permitted, to gate is forbidden") and R13 (no network in the verdict path) have no AC. The determinism AC (AC9) is adjacent but does not prove the verdict ignores ambient PR context. Add an AC: run identical docs+posture with ambient PR context present vs absent (or draft vs ready) and assert the verdict (exit code + JSON) is byte-identical, while advisory phrasing may differ.

5. **Error/edge conditions**: No AC covers the tool-error path (exit 1) — e.g. an unreadable doc or an invalid posture value. R12 names the exit-1 contract but no AC exercises it. Add an AC for a malformed-input / tool-error case asserting exit 1.

6. **R3 — CI asserts review-ready only when PR draft flag is false**: This caller-side behavior (CI maps draft→in-flight, ready→review-ready) has no AC. It is partly a DESIGN concern, but the behavioral contract ("CI asserts review-ready only when draft is false") is PRD-level and testable against the workflow. Add an AC for the CI posture-mapping behavior.

## Summary

The PRD is testable overall: nine of ten ACs name a concrete fixture, an observable signal (exit code or JSON parse), and a declared posture, and the L01-L07 finding IDs plus the `shirabe-validate/v1` envelope are real, identifiable artifacts in the codebase. The weaknesses are advisory-output ACs (AC7, AC8, AC10) that assert on subjective prose rather than pinned substrings, and missing coverage for the negative/edge paths — the exit-1 tool-error contract (R12), the explicit "context explains but never gates" guarantee (R9/R13), L01's preserved posture sensitivity (R7), and downstream pass-through compatibility (R12).
