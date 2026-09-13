# PLAN Review: work-on-standalone-completeness

## Verdict

FAIL

## Per-criterion falsifiability

**Issue 1** (`docs/plans/PLAN-work-on-standalone-completeness.md:70-98`). All six criteria are sound. The "fails if `cascade_run`'s transitions are made all-unconditional" criterion (:87-92) is the strongest in the plan: it names the exact regression, states why a reviewer reading `accepts:` would miss it, and the repository already has the harness pattern to build it (`skills/execute/scripts/settled-branch-record_test.sh` drives real `koto` ticks against a template in an isolated repo). A wrong implementation that collapses the three edges would fail this test as written. Constructible, falsifiable.

**Issue 2** (:100-122). All four criteria discriminate: byte-for-byte location, a zero-hit grep for the old path, and an assertion ordering test ("observing the failure precedes any transition") are all directly checkable. Sound.

**Issue 3** (:124-144). The anchoring criterion (:135-139) is explicit that no script covers it and hands the obligation to review rather than pretending it is mechanical — that is honest, not weak. Sound.

**Issue 4** (:146-172). The "test fails when a document is transitioned on disk but missing from the finalization commit" criterion (:161-165) is the second load-bearing one and is constructible: a test can transition a document on disk without committing it and assert the evidence check reports it. It also carries an explicit escape hatch if the harness can't build it. **However**, this issue's criteria never test the thing R5 actually requires: that the caller's recovery guidance for `partial` **matches** `/execute`'s two-shape guidance (`execute.md:735-740`). The PRD's own acceptance criterion is explicit — "verified by comparing both paths against the same shape" (PRD:371-373) — but Issue 4 only requires that `partial` "carry[ies] the failing step's detail and the shape-specific recovery guidance" (:169-170), without requiring a comparison to the existing text. A wrong implementation that invents its own (incorrect or generic) recovery wording for the two shapes would still pass every stated criterion here. This does not discriminate against the exact defect R5 exists to prevent.

**Issue 5** (:174-192) and **Issue 6** (:194-213). Both have a criterion phrased generically as "a child session" without specifying which child. Per `skills/work-on/koto-templates/work-on.md:762-766`, `pr_creation` routes `pr_status: shared` (the single-pr child, `SHARED_BRANCH` set) straight to `done`, bypassing `ci_monitor` entirely — for reasons that predate this feature and have nothing to do with `session_role`. Only a child with its own PR (`pr_status: created`, i.e. a multi-pr child — confirmed by the design's own text, ":278-282" and ":161-164" of the design) reaches `ci_monitor` at all, and is therefore the only case that exercises the new branch. Testing Issue 5's "a child session does not reach `cascade_entry`" (:183-184) or Issue 6's "no child session requests retention ... demonstrated by running a parent to convergence over a child that reaches one of the new terminal states" (:204-206) against a single-pr child passes **regardless of whether `session_role` is implemented at all**, because that child never gets far enough to test it. This is exactly the case R12 names by name — "a multi-pr child — which reaches its own CI monitoring — is correctly suppressed by it" (PRD:397-399) — and the plan's own outlines do not require it.

**Issue 7** (:215-228). Both criteria discriminate (byte-identical command, dirty-vs-clean behavior). Sound, though it does not require wiring the same `dirty_merge_state` outcome/escalation shape execute.md uses — likely acceptable since work-on.md's routing differs, but worth a reviewer's eye.

**Issue 8** (:230-244). All three criteria discriminate cleanly.

**Issue 9** (:246-269). Strong: "correct rather than merely present" (:258-261) and "a placeholder or empty value fails the state" (:262-264) are exactly the right shape. One gap: nothing requires the classification table to enumerate every obligation the PRD's Context names (merge/rebase cleanliness, closing keyword, PR-body content beyond the mechanical CI check, code cleanup, summary shape, commit-message convention, design diagram). The criteria check that whatever rows exist are correctly classified, not that no obligation was silently dropped from the table entirely — R8's own text ("An obligation that is neither gated nor carried as evidence ... SHALL be dropped or recorded as deliberately advisory") implies completeness is part of the requirement.

**Issue 10** (:271-294). The cardinality and reachability criteria are well-constructed and match the two failure modes named in the design (miscounted states, obligations that reach no child). Rated `simple`, which undersells it given this exact defect class ("a stated cardinality disagreeing with its own enumeration") recurred twice in this project's own design doc — see below.

## Design and requirement coverage

Every row of the Solution Architecture's pull-request-1 component table (`docs/designs/DESIGN-work-on-standalone-completeness.md:464-476`) maps to an issue: the script relocation and guard to Issue 2, the template additions to Issues 1/3/4/5/6/7/8/9, the mermaid companion and `requires.tsv` reconciliation to Issue 10 (split correctly between the relocation half in Issue 2 and the new-tool-call half in Issue 10), and the prose-to-state moves to Issue 10. Nothing in PR1's architecture is unaccounted for.

Requirement coverage against the PRD is otherwise close: R1-R4, R5a, R6-R11, R13, R19-R19b are all reachable through named criteria, several nearly verbatim. Two gaps: R5 (recovery-guidance parity, above, Issue 4) and R12's specific multi-pr-child test case (above, Issues 5 and 6). R20 (enum unchanged) is untouched by any PR1 component and is reasonably left unaddressed here since it is a migration-scoped (PR2) constraint despite its numbering falling outside the excluded R14-R18 range.

## Atomicity and sequencing

Each issue is completable in one session; none bundles independently-shippable units. The critical path (1 → 5 → 6 → 10, `:300-302`) is correctly the longest dependency chain — 1→9→10 and 1→3→10 are both shorter. The claim that Issues 2, 7, 8 are available "in parallel with the skeleton" and that 3/4/5/9 "open together" (:304-311) is dependency-correct but glosses over the fact that nearly every issue edits the same file (`work-on.md`), including two ci_monitor-touching issues (5 and 7) opened as parallel — a practical drafting-conflict risk the plan doesn't flag via the optional `Files` field, though this is a minor note rather than a defect given single-pr mode is typically one continuous authoring session.

The single-pr mode argument (:45-66) is sound and well recorded: the units are genuinely not independently shippable, the repository's default is honored, and the cross-PR ordering constraint that shirabe's execution modes can't express is named honestly as a workaround rather than silently absorbed. This will not need to be re-litigated.

One structural gap: the PLAN's `## Dependency Graph` section (:296-298) is present as a bare heading with no mermaid diagram at all. `plan-doc-structure.md`'s Execution Mode Differences table (:126-129) lists only "Issue Outlines" and "Implementation Issues" as varying by mode — Dependency Graph is not listed as omittable in single-pr mode, and no example in `plan-doc-examples.md` shows single-pr's expected shape for it either way, so this reads as an unaddressed required section rather than a deliberate, recorded omission.

## The three load-bearing criteria

Issue 1's chain-traversal test (PLAN:87-92) is sound and constructible against real precedent in this repository. Issue 4's document-in-commit test (PLAN:161-165) is sound, constructible, and honest about its own escape hatch. Issue 10's reachability-naming criterion (PLAN:280-283) is sound and appropriately shaped as a review obligation, consistent with how the design itself frames the constraint (DESIGN:123-127). All three would catch the regression each is aimed at.

## Required changes

1. Add or sharpen a criterion to Issue 4 requiring the `partial` routing's recovery guidance be verified against `/execute`'s existing two-shape guidance (`execute.md:735-740`), not merely present — satisfying R5's own comparison requirement (PRD:371-373).
2. Revise Issue 5's and Issue 6's criteria to specify that the child session used to demonstrate non-reachability / non-retention is a multi-pr child (own PR, reaches `ci_monitor`) — not a single-pr child, which never reaches `ci_monitor` for reasons unrelated to this feature and would make the criterion pass vacuously.
3. Populate `## Dependency Graph` with the mermaid diagram the format spec requires (or record explicitly, as the plan does elsewhere for deliberate deviations, why single-pr mode omits it here).
4. Add a criterion to Issue 9 requiring the classification table to enumerate every obligation named in the PRD's problem statement and the design's Decision 3, not merely that listed rows are correctly classified.
