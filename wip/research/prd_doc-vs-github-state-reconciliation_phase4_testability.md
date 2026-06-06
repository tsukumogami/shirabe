# Testability Review

## Verdict: PASS

The 24 acceptance criteria are individually testable: each names a concrete trigger and a concrete observable outcome, the four self-disable paths each have dedicated coverage, and both Sub-check C directions are explicitly exercised. Two narrow gaps exist (Sub-A and Sub-B silent-pass cases lack explicit ACs), but they are minor and listed below as suggested additions rather than testability failures.

## Untestable Criteria

None. Every AC names a concrete trigger and a verifiable outcome. The borderline cases below were considered and judged testable:

1. **AC17 ("the voice matches the existing FC05/FC06/FC07 notice form").** Anchored to concrete precedent strings in `crates/shirabe-validate/src/checks.rs`. A reviewer can compare actual FC09 notice strings against the FC05/FC06/FC07 output for shape (prefix, entity naming, observed-vs-expected pattern). Testable via string-comparison assertions, even though "voice" reads slightly subjective.

2. **AC8 ("contains no transport-specific code").** Verifiable by static inspection: grep the check function for transport-layer symbol references (e.g., `reqwest`, `Command::new("gh")`, HTTP-client crate imports). A test plan can specify the grep patterns to assert absence.

3. **AC16 ("independently reviewable as a single-line diff").** Verifiable by inspecting the `is_notice` membership site in `validate.rs` and confirming a single arm removal flips FC09's exit-code contribution. Testable via a unit test that toggles the membership and asserts the exit code on a doc with FC09 defects changes from 0 to non-zero.

## Missing Test Coverage

Two narrow happy-path / silent-pass gaps. Neither blocks the PRD's testability verdict, but each deserves an AC bullet so the implementer can derive a passing-case fixture from the AC list alone:

1. **Sub-check A silent-pass (no AC).** ACs cover the firing case ("doc claims done AND GitHub shows open -> notice"). There is no AC for the matching no-defect case: "doc claims done AND GitHub shows closed -> Sub-check A emits no FC09 notice for that row." Without this, a regression that fires Sub-A on every done-claimed row (false positive) would not be caught by an AC-derived test plan. Suggested AC: *"A plan or roadmap doc whose diagram has a node assigned `done` and whose corresponding table row is in a terminal state, when the actual GitHub issue is observed closed, produces no FC09 notice for that row (R1, R2)."*

2. **Sub-check B silent-pass (no AC).** Symmetric to the above. ACs cover the firing case ("doc claims open AND GitHub shows closed -> notice"). There is no AC for the matching no-defect case: "doc claims open AND GitHub shows open -> Sub-check B emits no FC09 notice for that row." Suggested AC: *"A plan or roadmap doc whose diagram has a node assigned `ready` or `blocked` and whose corresponding table row is open, when the actual GitHub issue is observed open, produces no FC09 notice for that row (R1, R2)."*

3. **Sub-check C silent-pass for PR-Closes alignment.** ACs cover both Sub-C firing directions (PR over-claims, doc-anticipates-no-PR). There is no AC stating that a `Closes #N` line that aligns with a `done`-claimed row whose issue is observed closed produces no Sub-C notice. Minor; the firing-direction coverage probably exercises the same code path, but an explicit silent-pass AC would let a test plan author derive the green case. Suggested AC: *"In a PR context where a `Closes #N` line names an issue the doc shows `done` and GitHub shows closed, Sub-check C emits no FC09 notice for that row."*

4. **Transient HTTP 5xx is covered by AC20** (row contributes no notice and the check proceeds), and **token-never-logged is covered by AC23** (scan of process output finds no token). Both edge cases the testability brief explicitly named are present.

5. **Token-never-logged across stderr and notice bodies (AC23)** specifies "process output (stdout and stderr), and any log surface." Testable; the assertion is a substring search over captured streams. No gap.

## Summary

The PRD's 24 acceptance criteria are individually testable and collectively cover every requirement at least once. The four self-disable paths (R6 missing-creds, R7 missing-PR-context, R8 rate-limit, R9 cross-repo 403/404) each have a dedicated AC; both Sub-check C directions are explicit; bounded-behavior (AC21, AC22) and token-never-logged (AC23) are both exercisable against the mock client surface Decision 4 establishes. The only weakness is the absence of explicit silent-pass ACs for Sub-A and Sub-B (the no-defect cases) — three suggested bullets above close the gap. Verdict: PASS.
