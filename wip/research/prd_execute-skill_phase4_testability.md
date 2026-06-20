# Testability Review

**Verdict:** PASS

The acceptance criteria are mostly binary and verifiable, and every value-preservation requirement (R8-R13) has a corresponding AC; a handful of conformance/inspection criteria lean on undefined external contracts and one requirement (R5's "removes them before the home merges") lacks a direct check, but none are fatal to testability.

## Untestable Items Found

1. **AC "/execute passes the parent-skill conformance checks (state schema, resume ladder, three exit names, security surfaces)"** (verifies R1, R2): Testable *only if* the "parent-skill conformance checks" exist as a runnable suite or documented checklist. The PRD asserts conformance to "parent-skill pattern v1" but does not name the artifact that defines pass/fail. A reviewer who didn't write the PRD cannot run this without locating that external contract. -> Cite the conformance check source (skill/doc/script path) so the criterion is self-contained, or restate the four sub-checks as concrete observable conditions.

2. **AC "/execute reads only status surfaces during a run (no child artifact bodies), verified against the metadata-only inspection contract"** (verifies R15): "Verified against the metadata-only inspection contract" presumes a defined contract and a way to observe what /execute reads. Proving a negative ("never reads bodies") is hard without an instrumentation/trace mechanism. As written it is closer to an assertion than a runnable check. -> Specify how body-reads would be detected (e.g., trace/log inspection, tool-call audit) and reference the inspection contract by name.

3. **R5 second clause — "removes them before the home merges"**: The ephemeral-artifact cleanup (PLAN + wip/ removed before the single PR / coordination PR merges) is a stated behavior with no dedicated AC. The finalization-cascade AC covers PLAN removal at completion but not the "before the home merges" timing/wip-hygiene aspect. -> Add an AC asserting no wip/ artifacts or PLAN doc remain in the merged PR for an owned-shape run (this also aligns with the workspace wip-hygiene rule).

4. **R8 / AC "intent-changing upstream change ... halts and escalates"**: Binary on the halt, but "classifies the impact" and the non-intent-changing (proceeds silently) branch is never exercised by any AC. Only the halt path is tested. -> Add an AC (or note) for a non-intent-changing drift that is absorbed and the plan proceeds, so the classifier's two outcomes are both demonstrated.

5. **R13 "the resulting pull request body documents what the plan did"**: "Documents what the plan did" is partly subjective (how much detail counts?) and has no AC. The crash-resume half of R13 is well covered by the interrupted-coordinated-run AC, but the self-documenting half is not. -> Add a check that the PR body contains the per-issue/plan summary (presence of specific sections), or accept it as descriptive and mark it non-acceptance.

6. **R11 done-signal detail — "merge-last pull request being the single, non-bypassable done-signal"**: The coordinated AC checks "plan done only when the coordination merge-gate passes in ready posture," which covers the gate but not the *non-bypassable* claim. "Non-bypassable" is asserted but no AC attempts to bypass it. -> Optional: add a negative check that the done-signal does not fire while the merge-last PR is unmerged.

## Suggested Improvements

1. Resolve the Open Question (thin /work-on milestone loop vs. author-dispatched one-at-a-time) before Accepted — the multi-pr AC ("no plan-level coordinator involved") is testable today, but its exact pass condition shifts depending on this answer.

2. The multi-pr exclusion is well testable: the AC "/work-on no longer contains the plan-orchestration path; invoking /work-on on a single issue behaves exactly as before" plus "each issue run independently ... no plan-level coordinator involved" together make R4/R7 falsifiable. "Behaves exactly as before" would be stronger with a named baseline (golden run or snapshot) to compare against.

3. R16 (no value regression) is a meta-requirement satisfied transitively by the R8-R13 ACs; confirm each of R8-R13 maps to at least one AC. Current mapping: R8->intent-drift AC, R9->carry-forward AC, R10->skip-dependents AC, R11->coordinated-merge-gate AC (partial), R12->finalization-cascade AC, R13->interrupted-resume AC (crash half only). R13's self-documenting half is the one gap.

4. R17/R3 (mechanism-neutral; accepts legacy four-column table unchanged) — R3's "MUST accept existing PLAN docs unchanged" is covered by the single-pr and multi-pr "no edit to the doc" ACs, but the specific legacy four-column table parse (Known Limitation #4) deserves its own fixture so that regression is caught directly.

## Summary

The PRD covers happy paths and the key edge cases (interrupted run with cross-branch resume, intent-changing drift halt, failed-issue dependent isolation), and the parity-or-better capabilities each have a verifiable AC except R13's self-documenting half and R5's pre-merge cleanup timing. The two conformance-style ACs (parent-skill checks, metadata-only inspection) are only as testable as the external contracts they reference, which the PRD names but does not locate. None of these gaps block the PRD; they are closeable by adding three ACs (pre-merge wip cleanup, non-intent-changing drift absorption, PR-body documentation) and pinning the conformance/inspection contracts by reference.
