# Verdict: FAIL

## Prior findings — status

All seven required changes from the previous review are resolved:

1. AC1's vacuous pass is gone. The new first delivery-shape criterion contrasts `atomic` against `consolidated` on the same input and requires the two runs to differ only in the header — a no-op implementation now fails it, since both would fall back to today's single-pr default and produce identical output.
2. AC5's unfalsifiable "readable from the document" clause is gone; the schedulable-graph criterion under Tracking preference carries R12 in checkable form.
3. A criterion now exercises all three precedence levels (flag > header > default) for delivery shape in one test with three distinct observables.
4. A criterion now covers the tracking default when a delivery preference is stated but tracking is not (R9).
5. All six {`single-pr`,`multi-pr`} × {`none`,`issues`,`issues-and-milestone`} combinations are now required and each names its observable.
6. R3 (header name collision) and R6 (renumbered from R12 — the value-confirmation guard) each have a covering criterion now (the "delivery-shape header's name... is not `Execution Mode`" criterion, and the "value-confirmation guard... runs against each resulting unit" criterion).
7. The approval-gate criterion names the observable as "which of the two [activation] paths the run takes," tested at every tracking level for both single-pr and multi-pr — this correctly discriminates against the old execution_mode-keyed gate (a multi-pr plan with tracking `none` must now take the automatic path).

## Factual claims — re-verified, all still hold

1. **execution_mode enum/location** — `skills/plan/references/phases/phase-3-decomposition.md:502-531` confirms the "hard constraint or incremental-value" branch language the Problem Statement now cites directly; `skills/plan/references/phases/phase-7-creation.md` confirms milestone+issue creation is multi-pr-only. Confirmed as re-cited.
2. **Validator posture-class mechanism** — unchanged from prior review; still applies generally via `is_notice(&ve, posture)` in `crates/shirabe/src/main.rs:741`, not just to `--lifecycle`. AC-S1's "non-blocking draft / blocking ready" phrasing maps cleanly onto `--mode=draft`/`--mode=ready`.
3. **`plan-to-tasks.sh` `#N` keying** — unchanged, still confirmed at `skills/plan/scripts/plan-to-tasks.sh:245` and the `process_multi_pr` table walk.
4. **Reviewability ceiling has no concrete value anywhere** — unchanged, still confirmed circular between `CLAUDE.md:59-69` and `references/coordination-strategy.md:134`. The PRD's new Definitions section states this explicitly and correctly.
5. **New claims added in this revision, checked**: `references/fixes/claude-md-conventions.md` exists and does define `## Execution Mode: auto|interactive` (line 61) and `## Roadmap Issues: optional|required` (line 64) — matches R3's collision claim and R1's precedence-pattern citation. `## PR Grouping Policy: coarsest-legal` is confirmed in `CLAUDE.md:46` (not in claude-md-conventions.md itself, but the PRD only cites it as an example of the precedence pattern, not as living in that file — accurate as written). `skills/plan/SKILL.md:60` ("multi-pr requires human approval") confirms R11's claim that the current approval gate is keyed on `execution_mode`, not on GitHub-artifact creation.

## New findings (requirement-to-criterion traceability, re-run from scratch on R1-R20)

- **R7's precedence-order clause is untested.** R7 requires the tracking level to resolve "in the same precedence order as R1" (flag > header > default). The precedence-order criterion under "Delivery-shape preference" tests exactly this for delivery shape, but no criterion under "Tracking preference" tests flag-overrides-header-overrides-default for the tracking level itself. The six-combination criterion and the default criterion both fix the *value* of the tracking preference by declaration; neither exercises a flag-vs-header conflict for tracking the way the delivery-shape precedence criterion does. A build that hard-codes tracking resolution to read only the CLAUDE.md header (ignoring an invocation flag) would still pass every tracking criterion.

- **R17's documentation-completeness clause is weaker than what it requires.** R17 requires both headers documented "with its accepted values, its default, and its precedence order." The current covering criterion ("the delivery-shape header's name... is not `Execution Mode`, and the two headers appear as separate rows") only checks the name and row-separation — it doesn't check that either header's documentation entry actually states its accepted values, default, or precedence order. This is a regression from the previous draft's criterion, which explicitly named those three content elements. As worded now, a documentation entry that names the header correctly but omits its accepted values/default/precedence would still pass.

- **R14's third branch is not exercised.** R14 requires the R13 field to name one of three branches: hard constraint, incremental-value judgment, or stated delivery preference. The covering criterion under "The shape record" contrasts only two of the three — the hard-constraint branch (forced split) versus the stated-preference branch (`atomic` with no constraint) — and asserts they're distinguishable. No criterion constructs the third case: a `consolidated` repository where decomposition reveals genuine incremental value with no hard constraint and no stated `atomic` preference, and checks that the R13 field correctly names the incremental-value branch (and not one of the other two). That case is exactly today's pre-existing split trigger, so it's the branch most likely to be mis-attributed by a careless implementation, and it's the one branch left unverified.

## Required Changes

1. Add a tracking-preference precedence criterion (flag overrides header overrides default) parallel to the existing delivery-shape one, to close R7's coverage gap.
2. Restore explicit content requirements to the documentation criterion (R17): each header's entry must state its accepted values, its default, and its precedence order — not just its name and row placement.
3. Add a criterion exercising the incremental-value branch of R13/R14: a `consolidated` repository, no forcing constraint, decomposition reveals genuine per-unit value — the R13 field must name the incremental-value branch, distinguishable from both other branches.
