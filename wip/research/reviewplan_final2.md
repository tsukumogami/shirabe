# READY

Final readiness verification for `docs/plans/PLAN-multi-pr-plan-decoupling.md`, cross-checked
against `docs/designs/DESIGN-multi-pr-plan-decoupling.md` and `docs/prds/PRD-multi-pr-plan-decoupling.md`.
All commands were run directly in the worktree; nothing here is taken on the documents' word.

## 1. Decision E site table (11 rows, DESIGN lines 328-338)

`grep -cniE "(human[ -]approv|approval gate)"` run against every row's file:

| File | Table count | Actual | Match |
|---|---|---|---|
| skills/plan/SKILL.md | 1 | 1 | yes |
| skills/plan/references/quality/plan-doc-structure.md | 3 | 3 | yes |
| skills/plan/references/phases/phase-7-creation.md | 1 | 1 | yes |
| skills/plan/references/plan-format.md | 0 (implied) | 0 | yes |
| crates/shirabe-validate/src/lifecycle.rs | 3 (52,61,764) | 3 | yes |
| crates/shirabe-validate/src/transition.rs | 4 (263,469,1960,2011) | 4 | yes |
| docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md | 1 | 1 | yes |
| docs/designs/current/DESIGN-shirabe-artifact-decision-contract.md | 4 | 4 | yes |
| docs/designs/current/DESIGN-roadmap-plan-standardization.md | 7 | 7 | yes |
| docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md | 2 | **4** (lines 7,13,43,56) | **mismatch** |
| crates/shirabe/tests/fixtures/golden/corpus/real/PLAN-roadmap-plan-standardization.md | 1 | **2** (lines 73,75) | **mismatch** |

Both mismatches are on the two non-re-key rows (`amend` and `leave`). Neither row's action
is "zero out every occurrence" — the decision record is amended, not rewritten, and the
fixture is pinned and untouched — so no Issue-6/8 acceptance criterion depends on either
count, and neither PLAN issue repeats the wrong number. Non-blocking, but the DESIGN's
table is factually wrong on these two counts.

## 2. Issue 6 completeness sum

The eight re-key files' stated per-file counts (SKILL.md 1, plan-doc-structure.md 3,
phase-7-creation.md 1, plan-format.md 0, lifecycle.rs 3, transition.rs 4,
DESIGN-lifecycle-draft-ready-discipline.md 1, DESIGN-shirabe-artifact-decision-contract.md 4)
sum to 17, matching Issue 6's "seventeen occurrences to clear" claim (PLAN line ~292) and
matching the grep output verified in section 1. Confirmed.

## 3. Issue 8's claim on DESIGN-roadmap-plan-standardization.md

Grep confirms 7 occurrences, matching Issue 8's AC ("It is 7 before the change", PLAN line 399-401).
Confirmed.

## 4. Issue 6 discovery check

Ran `grep -rniE "multi-pr" skills/ crates/ docs/ | grep -iE "(human[ -]approv|approval gate)"`.
Twelve lines hit, across these files:

- skills/plan/references/quality/plan-doc-structure.md — Issue 6 re-key target
- skills/plan/SKILL.md — Issue 6 re-key target
- skills/plan/references/phases/phase-7-creation.md — Issue 6 re-key target
- crates/shirabe-validate/src/transition.rs — Issue 6 re-key target
- crates/shirabe-validate/src/lifecycle.rs — Issue 6 re-key target
- crates/shirabe/tests/fixtures/golden/corpus/real/PLAN-roadmap-plan-standardization.md — golden fixture, allowed (leave)
- docs/plans/PLAN-multi-pr-plan-decoupling.md — this feature's own PLAN, allowed (quotes retired phrasing)
- docs/designs/DESIGN-multi-pr-plan-decoupling.md — this feature's own DESIGN, allowed
- docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md — Issue 6 re-key target
- docs/designs/current/DESIGN-roadmap-plan-standardization.md — Issue 8 re-key target
- docs/designs/current/DESIGN-shirabe-artifact-decision-contract.md — Issue 6 re-key target
- docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md — decision record's own quotation, allowed

Every hit falls in the expected set (Issue 6, Issue 8, or the three named exceptions). No
orphan site. I separately checked `docs/prds/PRD-multi-pr-plan-decoupling.md`, which does
contain "approval gate"/"human-approval" wording (R11, and an AC near line 315) but never on
a line containing the literal string "multi-pr" — so it doesn't surface in this grep. Read in
context, both PRD sites state the target/future predicate ("keyed on whether the activation
will create GitHub issues... rather than on execution_mode"), not the old mode-keyed claim as
present fact, so they are not a missed re-key site.

## 5. Leave/re-key reclassification of the three Current designs

Quote verified verbatim in `skills/design/references/design-format.md` lines 229-232: "The
directory move on `Planned -> Current` is load-bearing: it distinguishes designs that
documented historical decisions from designs that document the current architecture. A
reader scanning `docs/designs/current/` sees only currently-applicable designs." All three
files (`DESIGN-lifecycle-draft-ready-discipline.md`, `DESIGN-shirabe-artifact-decision-contract.md`,
`DESIGN-roadmap-plan-standardization.md`) carry `status: Current` in frontmatter, confirmed.

I agree with the reclassification. A `Current` design is explicitly documented as asserting
present architecture, not a historical snapshot; leaving stale mode-keyed gate language in
one after the gate is re-keyed would make the document false about the present, which is a
correctness defect the format's own stated purpose (only currently-applicable designs live
there) rules out. `leave` would have been right for a `Superseded` or dated decision record —
which is exactly how the DECISION record and the golden fixture are (correctly) treated.

## 6. Stale statements sweep

Searched both DESIGN and PLAN for "five prose sites", "seven sites", "four `leave` sites",
"six `re-key`", "twelve occurrences", and an unqualified /execute-drives-multi-pr claim.

- No hits for "five prose sites", "seven sites", "four leave sites", "twelve occurrences".
- No unqualified /execute-drives-multi-pr claim — the only assertion of that form
  (DESIGN Consequences, "Negative, with mitigations") is explicitly the refuted quotation:
  "an earlier draft of this section understated it by claiming the author could drive the
  plan by path... `/execute` does not drive multi-pr at all."
- **One real hit: DESIGN-multi-pr-plan-decoupling.md line 369** — "A file-scoped completeness
  grep over the six `re-key` files and a tree-wide discovery grep answer different questions
  and are both required." The current table has **eight** re-key files feeding Issue 6's
  file-scoped completeness check (plus a ninth re-key row, the DESIGN-roadmap-plan-standardization.md
  row, assigned to Issue 8) — not six. This is stale, left over from an earlier version of the
  table. **Correction: change "the six `re-key` files" to "the eight `re-key` files" at DESIGN
  line 369.** Non-blocking: Issue 6's own AC text in the PLAN independently and correctly says
  "over this issue's eight files" (PLAN line ~288), so the implementer is not misled by this
  sentence — it's an internal DESIGN inconsistency worth a one-word fix, not a plan defect.

## 7. Cross-issue conflict on DESIGN-roadmap-plan-standardization.md

Only Issue 8 lists `docs/designs/current/DESIGN-roadmap-plan-standardization.md` in its Files
section and edits it. Issue 6 mentions the filename once (PLAN line 272) only to state the
exclusion ("belongs to Issue 8"), and separately mentions the *golden fixture* file
`crates/shirabe/tests/fixtures/golden/corpus/real/PLAN-roadmap-plan-standardization.md` — a
different file, different directory, different prefix — purely as an unchanged-check, not an
edit target. No other issue's Files list or AC touches the DESIGN file. Confirmed clean.

## 8. Format conformance re a prior reviewer's claim

Checked `plan_execution_mode_sections()` in `crates/shirabe-validate/src/formats.rs`
(lines 230-255): for `execution_mode == "single-pr"` the required sections are `Status`,
`Scope Summary`, `Decomposition Strategy`, `Issue Outlines`, `Implementation Sequence`.
`Implementation Issues` and `Dependency Graph` are required only under `multi-pr` /
`coordinated`. The PLAN's frontmatter declares `execution_mode: single-pr` and has exactly the
required single-pr sections (it also carries an empty `## Dependency Graph` heading, which is
extra but not disallowed).

Ran `shirabe validate` against the plan twice — once with the pre-installed binary
(`~/.tsuku/tools/current/shirabe`, v0.17.0) and once built fresh from this worktree's
`crates/shirabe-validate` source (`cargo build --release -p shirabe`, ran the resulting
`./target/release/shirabe`). Both report:

```
All checks passed.
Advisory: Draft posture: no draft-tolerable findings to flag.
```

**The prior reviewer's claim is incorrect.** Neither `## Implementation Issues` nor a
populated `## Dependency Graph` is required for a `single-pr` plan, and the validator — run
from this repo's own current source, not just the installed binary — confirms the PLAN passes
cleanly as written.

## Verdict

`# READY`

Nothing found blocks or misdirects an implementer. Three minor, non-blocking accuracy nits
in the DESIGN doc (not the PLAN) are worth a follow-up cleanup pass but don't gate
implementation:
- DESIGN line 336 table: `DECISION-multi-pr-posture-detection-2026-06-06.md` states 2
  occurrences; actual is 4 (lines 7, 13, 43, 56).
- DESIGN line 338 table: the golden fixture states 1 occurrence; actual is 2 (lines 73, 75).
- DESIGN line 369: "the six `re-key` files" should read "the eight `re-key` files".
