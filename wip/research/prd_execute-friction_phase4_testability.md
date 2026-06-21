# PRD execute-friction — Phase 4 Testability Review

VERDICT: PASS

## Findings

### Requirement → criterion coverage (all 8 requirements have a verifiable counterpart)

- **R1 (existing branch/PR targeting) → AC1**: PASS. "lands the implementation commits on that branch and finalizes that PR — no new `impl/<slug>` branch and no second draft PR are created." Fully binary: check `git log` on the named branch for the commits, check the PR list for absence of a second PR and absence of `impl/<slug>`. Observable, no subjective judgment.

- **R7 parity (no-existing-PR still creates impl/<slug>) → AC2**: PASS. "Running `/execute` with no existing-PR context still creates the `impl/<slug>` branch and draft PR and drives to the done-signal (R7 parity)." This is the explicit parity counter-case to R1. Binary: branch exists, draft PR exists, done-signal reached. Good — the negative-of-R1 case the brief requires is present and checkable.

- **R2 (pause) → AC3**: PASS. "after all issues are implemented the run stops with a draft PR open AND the PLAN file still present and the upstream BRIEF/PRD/DESIGN still at their pre-finalization statuses." Three independently observable conditions: PR state == draft, PLAN file exists on disk, frontmatter `status:` of upstream docs unchanged. Verifiable by a developer who didn't write the PRD.

- **R2 resume → AC4**: PASS. "Resuming a paused run executes the finalization cascade (PLAN deleted, upstream transitioned) and completes the landing." Binary: PLAN file absent, upstream `status:` advanced, PR landed. The resume-completes-it case the brief asks for is present.

- **R3 (docs coverage) → AC5**: PASS, with a noted soft edge. "A plan whose DESIGN/PRD indicates user-visible surface yields either a documentation work item or a documentation-coverage check result before the run can reach its done-signal; a plan with no user-visible surface does not." This carries BOTH the fires-when-present and does-NOT-fire-when-absent cases — exactly the negative case required. Verifiable: feed a plan with a `docs/guides/*` reference / named CLI flag, observe a doc work-item or check artifact; feed a plan with none, observe its absence. Soft edge: "indicates user-visible surface" leans on the DESIGN's detection signal (D3 lists three candidate signals — prose `docs/guides/*` ref, named CLI flags, frontmatter flag). The criterion is testable once the DESIGN fixes the signal; the PRD correctly defers the exact trigger to D3 while keeping the pass/fail observable (work-item-or-check-result exists vs. does-not). Acceptable at requirements altitude — not a FAIL.

- **R4 (template PR) → AC6**: PASS. "The PR produced by `/execute` finalization has a conventional-commit title and a two-part body with no manual fix-up applied." Binary: title matches conventional-commit regex (`type(scope): subject`), body has the project's two named sections, and the run did no fix-up pass. "two-part body" references "the project's two-part structure" (R4) — an objective external standard, not a subjective "clean" judgment. Checkable.

- **R5 (finalization guard) → AC7**: PASS. "A run whose finalization did not complete is reported as incomplete by a check that a human can run from the CLI and that CI can run; a fully finalized run reports complete." Reports both the incomplete and complete cases (the required incomplete-vs-complete pair). Binary: the check exits/prints complete vs. incomplete. Both invocation surfaces (CLI + CI) named.

- **R6 (durable artifact) → AC8**: PASS. "A friction/report-upstream artifact produced during a run is retrievable from a durable location after finalization cleanup and after the PR's squash-merge." Binary and tests the specific destructive sequence (cleanup + squash-merge) that R6 must survive: produce artifact, run cleanup, squash-merge, then assert the artifact is still retrievable. Strong edge coverage.

- **R8 (--auto with/without pause) → AC9**: PASS. "Under `--auto` without a pause request, the run drives to the done-signal without stopping; under `--auto` with a pause request, it stops at the reviewable draft (R8)." Both autonomy cases present — the no-stop-without-pause negative case the brief flags is explicitly checkable (run `--auto` sans pause, assert no stop), and the with-pause case asserts the stop. Binary.

### Criteria verify rather than restate

- No criterion is a bare echo of its requirement. Each adds observable conditions: AC1 adds "no second PR / no `impl/<slug>`"; AC3 enumerates the three intact-chain observables; AC8 names the cleanup+squash-merge sequence. The criteria are verification conditions, not paraphrases.

### Each requirement independently testable

- R1–R8 are each verifiable in isolation. R3 is the vaguest ("indicates user-visible surface") but the PRD bounds it via D3's candidate signals and the criterion's observable output, so it does not cross into non-testable. R7/R8 (non-functional) are still mechanically checkable (parity branch/PR creation; `--auto` stop behavior).

### Negative / edge cases (the brief's named trio)

- Parity preserved (R7) — AC2: present, checkable.
- Docs-check does-not-fire-when-absent (R3) — AC5 second clause "a plan with no user-visible surface does not": present, checkable.
- Autonomy no-stop-without-pause (R8) — AC9 first clause: present, checkable.
- All three required negative cases are explicitly covered.

### No criterion tests something unrequired

- Every AC maps to an R. No orphan criteria.

## Summary

Every acceptance criterion is binary and objectively verifiable by a developer who didn't author the PRD — each names observable conditions (branch/PR state, file presence, frontmatter status, regex-checkable title, check exit state) rather than subjective quality judgments. All eight requirements have a corresponding verifiable criterion, and every required negative/parity case (R7 no-existing-PR, R3 does-not-fire-when-absent, R8 no-stop-without-pause, R2 resume, R6 survives-cleanup-and-squash) is present and checkable. The only soft spot is R3/AC5's "indicates user-visible surface," which depends on a detection signal the PRD deliberately defers to DESIGN (D3) while keeping the pass/fail output observable — acceptable at requirements altitude and not grounds for failure.
