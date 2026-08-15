# PRD Jury -- Completeness Review: scope-artifact-persistence

PASS

(Round 1 verdict was FAIL. This file records the round-2 re-review of the
rewritten document; the round-1 findings are summarized under "Round 1
disposition" rather than reproduced in full.)

Target: `docs/prds/PRD-scope-artifact-persistence.md`
Reviewer scope: completeness only -- decision coverage, requirement-to-criterion
coverage, BRIEF scope-boundary coverage, the four absorb defects, eval accuracy.

Every settled decision from the exploration now reaches a requirement. Every item
on the BRIEF's Scope Boundary IN list reaches a requirement. All four named
absorb defects carry a requirement *and* a criterion. The eval-suite requirement
is now accurate against the recorded family and carries positive coverage rather
than a negative screen. That closes the failure mode this review exists to catch.

Four defects remain. None hides a missing decision, and all four are one-line
fixes, which is why they do not hold the verdict -- but two of them will produce
a dead end during implementation if they reach the DESIGN unchanged, so they
should be fixed before this PRD is Accepted.

---

## Round 1 disposition -- all eleven findings

| # | Finding | Disposition |
|---|---------|-------------|
| 1.1 | Content-boundary carve-out had no requirement | **Closed.** R10 + criterion that each affected format reference names the absorbed case as an exception. |
| 1.2 | D1's `R<n>` citation rule vanished | **Closed.** R16 + criterion; the Out of Scope bullet now distinguishes it from the ~374-name repair campaign; the D1 Decisions entry carries the rider. The rollout call D1 left open is answered by R28 plus the corpus regression criterion -- R16 emits nothing on a document declaring no absorption. |
| 1.3 | Eval requirement under-counted the family | **Closed and improved.** R24 forbids type-level mapping references, requires positive `absorb`/`keep` coverage above BRIEF-to-PRD, and floors the scenario count. The criterion names scenarios 18, 19, 20, so it is a diff. The positive half is verified by the first judgment criterion. |
| 1.4 | D4 firewall and first follow-on dropped | **Closed.** The firewall is the last sentence of R15. Both follow-ons are named in Out of Scope, the BRIEF-to-PRD fold with its ~55-candidate population and its gates. |
| 1.5 | Re-entry case unaddressed | **Closed.** R2 + a criterion. |
| 1.6 | `/work-on` correction; prior-artifact contradictions | **Closed.** R23 says `/work-on`; the D5 entry carries the R14/R15 reason. Open Question 3 now covers the DESIGN's Decision 9 and that PRD's R14 together. |
| 2 | R4/R7/R8/R12/R13/R17 (old numbering) had no criteria | **Five of six closed.** Old R8 (author before the carry table, now **R13**) still has none -- see below. |
| AC vacuity | old AC3, AC16, AC17 | **Closed.** The fixture-parity criterion that replaced AC3 is the strongest single addition in the rewrite: it makes "the two chains differ only in content" mechanically checkable instead of a setup note. |

The instrument labels (**[mech]** / **[judg]**) and the Known Limitation about
graded-not-gated behaviour are additions I did not ask for and they materially
improve the document: they make it visible which criteria are decided by a weekly
cron eval rather than a merge gate.

---

## Defect 1 -- R13 still has no acceptance criterion (reported closed; it is not)

**R13.** "The carry check SHALL be evaluated against contribution text that
already exists, never against a prediction that it will be written."

No criterion tests the ordering. The nearest candidate -- "An absorb whose
contribution does not carry leaves both documents on disk and records the
failure" -- verifies R14's abort path and passes identically under a
prediction-based procedure, since an agent can predict `carried: false` as easily
as it can observe it. A build that keeps the current step order ships green.

This is the requirement D2 traded the independent reviewer away for: "The
reviewer's one real contribution -- judging an artifact rather than a prediction
-- is bought for free by R13." The document says so in its own Decisions section.
It should not be the one requirement with no verification.

**Suggested criterion (mech):** The absorb procedure cannot produce a carry-table
row for a contribution section that does not yet exist on disk; the procedure's
step order places contribution authoring strictly before carry-table
construction. Verified by inspection.

R12 (no gate on the verdict) also has no criterion naming it, but the paired eval
does discriminate weakly -- a confirmation gate or reviewer spawn would not reach
`absorb` in a non-interactive eval run. Acceptable, and consistent with how R26
and R27 are handled.

---

## Defect 2 -- the regression criteria are jointly unsatisfiable today (BLOCKING for the DESIGN)

> - **[mech]** A corpus-wide test walks every document under `docs/`, runs
>   `shirabe validate`, and asserts **exit 0** with no new check code emitted.
> - **[mech]** `git diff --exit-code docs/` is clean in the same job, proving no
>   existing document was edited to make the corpus pass.

The corpus does not exit 0 today, and this work is fenced out of fixing it.

Verified in this worktree: five documents carry an `upstream:` whose target does
not exist.

- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md`,
  `BRIEF-legend-vs-classdef-reconciliation.md` and
  `BRIEF-table-diagram-reconciliation.md` point at
  `docs/designs/DESIGN-roadmap-plan-standardization.md` (stranded by the
  Accepted-to-Current directory move; the file lives at
  `docs/designs/current/`).
- `BRIEF-cascade-outline-ac-completeness.md` and
  `BRIEF-single-pr-plan-validation.md` point at
  `docs/plans/PLAN-roadmap-plan-standardization.md` (deleted at finalization by
  design; `docs/plans/` holds one unrelated file).

All five carry `schema: brief/v1`, so the schema gate passes and hard failures
fire. R6 is error-severity and is not Plan-scoped --
`crates/shirabe-validate/src/checks.rs:767`: "The check runs for every format,
not just Plan. A dangling `upstream:` is wrong however it arose." This matches
the exploration's own finding that `shirabe validate` "exits 2 on them right
now." (I confirmed the five dangling targets and read the check; I did not build
and run the binary.)

So the first criterion fails on the pre-existing corpus, and the second forbids
the repair -- correctly, because repairing dangling references is fenced out of
scope as a repair campaign. As written the job can never go green.

**Fix:** drop `exit 0` and keep only the clause that is actually the intent --
no finding carrying a check code this work introduces. Or freeze the current
findings as a baseline the job diffs against, which additionally catches
regressions in existing codes.

**Second, smaller problem with the same pair.** `git diff --exit-code docs/`
compares the working tree to HEAD. It proves the *test run* did not rewrite
files in place -- a real and worthwhile guard -- but not the stated claim, that
"no existing document was edited to make the corpus pass," since an edit
committed on the branch leaves the working tree clean. The stated claim needs a
merge-base diff restricted to documents that existed before the branch, which is
awkward here because this chain necessarily adds documents under `docs/`. Either
narrow the rationale to what the command proves, or specify the merge-base form
with the new chain artifacts excluded.

---

## Defect 3 -- R25 is under-specified in one respect (the premise is sound)

**R25.** "`docs/guides/doc-validation.md` SHALL document any check family this
work adds." Criterion: the guide "names every check family this work adds."

The premise holds and the guide is already stale, which is direct evidence for
including it. `doc-validation.md:23-25` describes R6 as a Plan-doc rule --
"Format-specific rules -- Plan docs: upstream file existence and git tracking
(R6)" -- while the code says the opposite. Whatever else R25 produces, that line
should be corrected in passing.

What is under-specified is "check family." The guide has no such term; its "How
it works" section enumerates three groups (schema gate, FC01-FC04,
format-specific rules), and this work's additions do not map cleanly onto them:
R8's contribution-section requirement is FC-class, R9 reuses the existing
canonical-order check rather than adding one, R16 is a new format-specific rule,
and R21's non-resolution exclusion is an exception to an existing rule rather
than a new check. A criterion marked **[mech]** that asks whether the guide names
"every check family" cannot be decided without first deciding which of those four
count.

**Fix:** replace "check family" with "check code," which the crate and the guide
both already use (FC01-FC16, FC99, L01-L08, R5-R9), and name the additions
explicitly in the criterion -- the contribution-section requirement check, the
`R<n>` citation-resolution check, and the absorption-declaration exclusion from
path resolution. Then the criterion is a grep.

---

## Defect 4 -- R22's third sentence defers a decision without naming it as open (minor)

**R22:** "The PRD-level contract for what `exit_artifacts:` holds under a fully
folded chain SHALL be stated so the guard has a defined seed." Its criterion
reads "seeded per R22's stated contract."

The PRD does not state the contract, so the requirement asks for a statement it
does not make and the criterion verifies conformance to something that does not
yet exist. Either state it (one clause: what `exit_artifacts:` holds when every
chain artifact folded) or move it to Open Questions alongside the record surface,
which is the same shape of deferral and is handled correctly there.

---

## Coverage tables (round 2)

**Requirements with no criterion:** R12 (weakly covered by the paired eval --
acceptable), **R13 (none)**, R26 and R27 (standing negative constraints, no
criterion by design and consistent with the document's own convention).
Everything else carries at least one criterion that discriminates.

**The four absorb defects:**

| Defect | Requirement | Criterion |
|--------|-------------|-----------|
| `upstream:` re-point replaces rather than splices | R17 | covered |
| Missing retirement guard before deletion | R15 | covered, both tiers |
| Post-absorb re-validation checks only the survivor | R18 | covered -- the revert criterion spells out all five steps |
| Write-target set omits upper-hop absorb paths | R19 | covered, by inspection |

**BRIEF Scope Boundary:** all eight IN items reach a requirement; the
content-boundary half of item 3 is now R10. No OUT item is pulled back in; the
Out of Scope section gained one exclusion (the isolated-clone eval mechanism)
which is a narrowing with a stated reason and is paired honestly with Known
Limitation 2.

**Eval accuracy:** R24 plus its criterion now matches the decisions record.
Scenarios 18, 19 and 20 are named for rewrite; 21 is left alone, which is what
the decisions file recommends since R14 preserves the abort semantics 21
asserts; the count floor and the negative screen cover 7, 17 and 21 without
mandating edits that may not be needed.

---

## Fix list before Accepted

1. A criterion for R13 (defect 1).
2. Drop `exit 0` from the corpus criterion and narrow the `git diff` rationale
   (defect 2) -- this one is a dead end for the DESIGN if it ships as written.
3. R25: "check code" not "check family," with the three additions named; correct
   the guide's stale R6 line while there (defect 3).
4. R22: state the `exit_artifacts:` contract or move it to Open Questions
   (defect 4).
