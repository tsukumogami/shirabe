# Plan Review — PLAN-upstream-link-legality

**Verdict:** FAIL

`./target/debug/shirabe validate docs/plans/PLAN-upstream-link-legality.md --visibility=public`
exits 0 with no output. Structure is conformant: the five single-pr required
sections (`Status`, `Scope Summary`, `Decomposition Strategy`, `Issue Outlines`,
`Implementation Sequence`) are present in canonical order and match
`plan_execution_mode_sections()` in `crates/shirabe-validate/src/formats.rs:56`
exactly; all seven outlines carry Goal, Acceptance Criteria and Dependencies;
`issue_count: 7` matches seven `### Issue` headings; every `<<ISSUE:N>>`
reference (1×2, 3, 4, 5, 6) resolves to an existing outline.

The FAIL rests on four defects, all cheap to fix, none requiring
re-decomposition: one issue's acceptance criterion cannot be satisfied when that
issue lands, two acceptance criteria point a verifier at a list the cited
document does not contain, one declared dependency's justification contradicts
the plan's own file lists, and one PRD acceptance criterion is uncovered.

## Coverage map

### Design implementation phases

| Design phase | Issue | Notes |
|---|---|---|
| First, the declaration layer alone | Issue 1 | Two types, three fields, eight literals, both unit tests, terminal-status agreement test — all present |
| Second, the check | Issue 2 | Function, call site, two codes, valid-codes message, test set |
| Third, the reference sweep | Issue 3 | Prose only; see Finding 3 for scope mismatch |
| Fourth, skill contracts + plan pre-flight script | Issues 4, 5, 6 | `/brief` (4), `/plan` + `validate-plan.sh` (5), `/scope` + `/explore` (6) |
| Fifth, evals and fixtures | Issues 4, 6, 7 | Brief evals in 4, scope evals in 6, execute evals + fixtures in 7 |

No design phase is uncovered.

### PRD requirements

| Req | Issue | Req | Issue |
|---|---|---|---|
| R1 | 1 + 2 | R14 | 5 (AC1, AC4) |
| R2 | 1 (AC2, AC3) | R15 | 6 (AC5) |
| R3 | 1 (AC3) | R16 | 5 (AC3) |
| R4 | 1 (AC4) | R16.1 | 6 (AC6, last clause) |
| R5 / R5.1 / R5.2 / R5.3 | 1 (AC3, AC5); prose in 3 | R17 | **partial — see Finding 5** |
| R6 | 2 (AC1, AC2) | R18 | 7 (AC3) |
| R7 | 2 (AC2, AC3, AC6) | R19 | 7 (AC2) |
| R8 | 2 (AC9) | R20 | 2 (AC8) + no-modified-tests in 1/2 |
| R9 | 2 (AC4) | R21 | 2 (AC2, AC7, AC11) |
| R10 | 2 (AC5) | R22 | 4 (AC6), 6 (AC3, AC6), 7 (AC2, AC5) |
| R11 | 4, 5, 6 | R23 | 7 (AC1, AC3, AC4) |
| R12 | 4 (AC1, AC3); **grading partial — Finding 4** | R24 | 2 (AC8) |
| R13 | 4 (AC3, AC4, AC6) | R25 | 2 (AC10), 3 (AC4) |

Every requirement maps to an issue. Two PRD *acceptance criteria* — not
requirements — are dropped: the `is_known_check_code` exactly-two-codes /
no-required-section-list-change criterion (R17), and the eval-grades-the-
announcement half of the `/brief` criterion (R12).

No acceptance criterion in the plan traces to nothing. Issue 1 AC6
(terminal-status agreement test), Issue 5 AC5–AC7 (`validate-plan.sh`), Issue 5
AC6 (Phase 7 argument boundary) and Issue 6 AC4 (durable artifact record) trace
to the design's Solution Architecture, Security Considerations and Mitigations
rather than to the PRD, which is legitimate.

## Sequencing verification

**Is Issue 5 genuinely independent of Issues 1–3? Yes — confirmed.** Issue 5's
files (`skills/plan/SKILL.md`, `skills/plan/references/phases/phase-7-creation.md`,
`skills/plan/scripts/validate-plan.sh`, `validate-plan_test.sh`,
`skills/plan/evals/evals.json`) share nothing with Issues 1–3
(`crates/shirabe-validate/src/formats.rs`, `checks.rs`, `validate.rs`,
`crates/shirabe/src/main.rs`, `references/pipeline-model.md`, three format
references). Content is independent too: the value `/plan` records is
PLAN→ROADMAP, which is legal under R5's table *and* under today's prose
(`skills/plan/references/quality/plan-doc-structure.md` already documents a
roadmap as a legal plan upstream), so nothing Issue 5 produces depends on the
declarations existing or on the sweep having run. `grep -n '\-\-upstream'
skills/plan/SKILL.md` returns nothing — the flag genuinely does not exist yet.

**Does Issue 4 genuinely need Issue 3? No — the stated justification is false.**
The Implementation Sequence says "Issue 4 joins after Issue 3, since it edits a
format reference the sweep touches." Issue 4's declared files are
`skills/brief/SKILL.md`, `references/phases/phase-0-setup.md`,
`references/phases/phase-2-draft.md` and `evals/evals.json`. Issue 3's are
`references/pipeline-model.md`, `skills/brief/references/brief-format.md`,
`skills/prd/references/prd-format.md`, `skills/design/references/design-format.md`.
The intersection is empty — Issue 4 touches no format reference at all. There is
no content dependency either: Issue 4 changes what `/brief` writes, Issue 3
changes what the prose says, and neither reads the other. If anything the
dependency runs backwards (see Finding 3).

**Does Issue 6 need both 4 and 5? Yes, for five of its six criteria.** AC1
requires `/plan`'s `--upstream` row (Issue 5) and the `/brief` "grounds, not
recorded" row (Issue 4); AC2's "matching what `/brief` and `/plan` enforce"
requires both confinements to exist; AC6's end-to-end `/scope` assertion requires
both. Verified against
`skills/scope/references/phases/phase-2-chain-orchestration.md:168-172`, which
today says outright "the brief records that path in its `upstream:` frontmatter"
— that sentence must change and it is in Issue 6's file list. AC3's claim also
checks out: the pre-authoring sentence is committed at
`phase-1-discovery.md:304` and `:341` and once in `skills/scope/evals/evals.json:373`,
three sites as stated. **AC5 (`/explore`) is the exception**: it edits
`skills/explore/references/phases/phase-5-produce-roadmap.md:43-49`, which passes
a VISION to `/roadmap` and depends on neither Issue 4 nor Issue 5.

**Issue 3's dependency on Issue 1** is nominal — no file overlap, no functional
coupling. Harmless but it lengthens the 1→3→4 chain that the plan itself
describes as parallelizable prose.

## Findings

**Finding 1 (material). Issue 4's dependency justification contradicts the
declared file lists.** Detailed above. Either the dependency is spurious and
Issue 4 should be `Dependencies: None`, or Issue 4's `Files` is missing
`skills/brief/references/brief-format.md` and the sweep's brief row belongs to
Issue 4. As written a reader cannot tell which, and the star-topology conflict
detection in `plan-to-tasks.sh` keys on `Files`, so the wrong answer produces the
wrong edge.

**Finding 2 (material). Two acceptance criteria cite the design for lists the
design does not contain.** Issue 2 AC8 says "The eight documents the design
names produce exactly the predicted findings." Issue 7 AC5 says "No eval outside
the five the design names changes." `DESIGN-upstream-link-legality.md` refers to
"the eight named documents" and "the five named eval expectations" but enumerates
neither — the eight-document table is `PRD-upstream-link-legality.md` R24 and the
five-eval table is R22. A verifier who did not write the plan opens the design,
finds no list, and cannot evaluate either criterion.

**Finding 3 (material). Issue 3's AC1 is repo-wide but Issue 3's scope is four
files, and the remainder belongs to an issue that lands after it.** AC1 requires
that no file under `references/` or `skills/*/references/` documents a ROADMAP as
a legal upstream for a BRIEF, a PRD or a DESIGN. Today
`skills/brief/references/phases/phase-2-draft.md:75` writes `upstream: <path to
upstream ROADMAP, omit field if none or if private>` into the brief's frontmatter
template, and `phase-0-setup.md:55` describes the flag as naming "the ROADMAP
this feature comes from". Both files are Issue 4's, and Issue 4 is blocked by
Issue 3. So at the moment Issue 3 completes, its own AC1 is false. The
implementer must either fail the criterion or reach into Issue 4's files.

**Finding 4 (material). R12's eval-grading obligation is not required by any
AC.** R12 states the omission announcement "is graded by the skill's eval suite
rather than by a string match," and the PRD's acceptance criterion says the eval
suite grades "that the run announced the omission and its reason." Issue 4 AC3
requires the announcement as behaviour; AC6 requires only that the two rewritten
scenarios "assert grounding without a recorded field." Nothing requires an eval
to grade the announcement.

**Finding 5 (minor). One PRD acceptance criterion is uncovered.**
"`is_known_check_code` gains exactly the two new codes, and no format's
required-section list changes" has no counterpart. Issue 2 AC6 covers
selectability and the valid-codes message but not "exactly two"; Issue 1 AC7 and
Issue 2 AC11 cover no-modified-tests but not the required-section lists.

**Finding 6 (minor). Issue 3 declares a file with nothing to change.**
`grep -rni roadmap skills/design/references/design-format.md` returns nothing.
Per R5.2 the DESIGN case follows from the nearest-produced rule, which lives in
`skills/prd/references/prd-format.md:27` and `references/pipeline-model.md:121`,
not in `design-format.md`. The declared write target is either wrong or the
DESIGN correction has no home.

**Finding 7 (minor). Issue 7 AC4 restates a requirement rather than verifying
one.** "Adding fixtures is recorded as a deliverable rather than as a change to
an eval outside the named list" is R23's closing sentence with no observable
test attached — it asks how the work is characterised, not what it produces. AC5
already carries the checkable half.

**Finding 8 (minor). Issue 6 AC5 rides a dependency it does not need.** The
`/explore` handoff fix (R15) touches one file that neither Issue 4 nor Issue 5
touches and needs neither. Bundled, it inherits a two-issue block for no reason.
Acceptable as a one-AC rider; worth naming so it is not read as a real
constraint.

**Finding 9 (note). Issue 5 is the atomicity borderline, and the design's
coupling argument carries it.** Eight criteria spanning a skill contract, a
shell script rewrite, new shell test cases and an eval is the largest spread in
the plan. It stays one issue because the design explicitly binds them — "The
script's sequence handling belongs in this phase … it is a hard dependency of
the flag: a plan with two upstream entries would otherwise pass a check that has
silently stopped running" — and splitting them would land a flag whose output
escapes the only continuous gate that validates it. Issue 2 is the largest single
piece but is one deliverable (one check function) and stays atomic. No issue is
really two.

**Finding 10 (note). The single-pr justification survives, but one of its two
arguments is wrong.** The plan writes: "'No document outside the named list
changes its findings' cannot be evaluated against a tree where the check has
landed and the skills have not." That is incorrect — R24's table is about
existing documents under `docs/`, and no skill change alters an existing
document's findings, so the criterion is fully evaluable with only Issues 1–3
landed. The defensible split therefore exists on paper: Issues 1+2+3 land a
working `shirabe validate` legality check with the prose agreeing, which is
observable value on its own. What defeats it is the residual the plan's other
argument names correctly: with Issue 4 unlanded, `/brief` still writes
`upstream: <roadmap>`, so between the two PRs the chain produces documents its
own newly-landed validator rejects at error severity. That is a real regression
window, and single-pr is the documented default (P1), so the mode selection
stands. The faulty sub-argument should be struck rather than left as precedent.

**Finding 11 (note on the review brief's premise). No complexity values are
assigned anywhere in this plan.** The request asks whether `testable` /
`critical` / `simple` are right for Issues 2, 5 and 3 — the document carries no
`**Complexity**` field on any outline, only `**Type**` (`code`/`docs`/`task`).
This is conformant: the Issue Outline Format in
`skills/plan/references/quality/plan-doc-structure.md:197-211` requires Goal,
Acceptance Criteria and Dependencies, with `Type` and `Files` optional and no
Complexity field; complexity belongs to the multi-pr Implementation Issues table
(the plan profile of `references/issues-table.md`), which single-pr omits. The
`**Complexity**` line in `phase-3-decomposition.md:222` applies to the wip
decomposition artifact, not to the PLAN doc. Nothing to correct — but the premise
that Issues 2 and 5 are marked critical and Issue 3 simple does not hold against
the document. The `Type` values that *are* present are right: Issues 1, 2 and 5
touch code or executable scripts, Issues 3, 4 and 6 are prose, Issue 7 is fixture
and eval data.

## Required changes

1. **Issue 4 dependency.** Resolve the contradiction between the Implementation
   Sequence's justification and the declared `Files`. Either set
   `**Dependencies**: None` and correct the sequence prose, or add
   `skills/brief/references/brief-format.md` to Issue 4's `Files` and move the
   brief row of the sweep into Issue 4 (removing it from Issue 3's file list).

2. **Issue 2 AC8 and Issue 7 AC5.** Cite the document that carries the list:
   `PRD-upstream-link-legality.md` R24 for the eight documents, R22 for the five
   evals. As written both criteria point at a design that enumerates neither.

3. **Issue 3 AC1.** Bound the criterion to what Issue 3 delivers, or move the
   repo-wide sweep assertion to the last issue that touches a reference file.
   Today it is false at the moment Issue 3 completes, because
   `skills/brief/references/phases/phase-2-draft.md:75` and
   `phase-0-setup.md:55` are Issue 4's files and Issue 4 lands after Issue 3.

4. **Issue 4 AC6.** Extend to require that the rewritten evals grade the
   announcement of the omission and its reason, not only grounding-without-a-
   recorded-field. R12 makes the eval suite the grading mechanism and the PRD's
   acceptance criterion states it explicitly.

5. **Issue 2 (add a criterion).** Cover the uncovered PRD criterion:
   `is_known_check_code` gains exactly the two new codes and no format's
   required-section list changes.

Recommended but not required: strike the faulty half of the single-pr argument
(Finding 10); drop or repoint `skills/design/references/design-format.md` in
Issue 3's `Files` (Finding 6); replace Issue 7 AC4 with something observable or
fold it into AC5 (Finding 7).
