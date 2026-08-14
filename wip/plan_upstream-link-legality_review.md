# Plan Review — PLAN-upstream-link-legality

**Verdict:** PASS

Round 3. Both required changes and both recommendations from round 2 are applied
correctly. The dependency graph is now consistent between the outlines and the
sequence prose, the repo-wide sweep is satisfiable at the point it is asserted,
and Issue 3's narrowing leaves neither the PRD case nor the DESIGN case without
an owner. Two notes remain, neither blocking.

`./target/debug/shirabe validate docs/plans/PLAN-upstream-link-legality.md --visibility=public`
exits 0 with no output.

## Coverage map

Unchanged from round 2 and complete.

**Design implementation phases.** Declaration layer → Issue 1. The check → Issue
2. Reference sweep → Issue 3 (pipeline and PRD format), Issue 4 (brief format),
Issue 6 (scope references, plus the closing repo-wide assertion). Skill contracts
and the plan pre-flight script → Issues 4, 5, 6. Evals and fixtures → Issues 4,
6, 7. No phase uncovered.

**PRD requirements.** R1–R25 all map to an issue. The two acceptance criteria
that were uncovered in round 1 remain covered: R17's `is_known_check_code` clause
at Issue 2 AC10 (`:116`), R12's eval-grading clause at Issue 4 AC7 (`:176-179`).
No acceptance criterion traces to nothing.

**Ownership of every file carrying a forbidden shape**, after the redistribution:

| File | Line evidence | Owner |
|---|---|---|
| `references/pipeline-model.md` | `:113` tree diagram, `:137-139` "`/brief` crosses that boundary by taking a Roadmap as its upstream", `:121` nearest-produced rule | Issue 3 |
| `skills/prd/references/prd-format.md` | `:27` "nearest parent", `:29` "ROADMAP when no BRIEF was written" | Issue 3 |
| `skills/brief/references/brief-format.md` | `:31`, `:61-63` | Issue 4 |
| `skills/brief/references/phases/phase-0-setup.md`, `phase-2-draft.md` | `:55`, `:75` | Issue 4 |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | `:172` "the brief records that path in its `upstream:` frontmatter" | Issue 6 |

## Sequencing verification

**Dependency graph, outlines vs prose — consistent.** The outlines declare
1: None; 2: 1; 3: 1; 4: None; 5: None; 6: 3, 4, 5; 7: 6 (`:79, :122, :147, :181,
:218, :255, :279`). The sequence prose now states the same graph in both of its
summarizing paragraphs: "Issue 6 is where the strands join… so it waits on all
three" (`:299-303`) and "After Issue 1, three strands run in parallel: Issue 2,
Issue 3, and the pair Issue 4 and Issue 5, which depend on nothing. Issue 6 waits
on all three of Issue 3, Issue 4 and Issue 5" (`:305-308`). The stale
"(3-then-4, 5)" parallelization line is gone. Round-2 Finding 2 resolved.

**Issue 6's sweep criterion is now satisfiable at Issue 6's completion.** AC7
(`:248-253`) asserts the condition over `references/` and `skills/*/references/`.
Every file in the ownership table above belongs to Issue 3, Issue 4, or Issue 6
itself, and Issue 6 is blocked by both 3 and 4, so all of them have landed when
AC7 is evaluated. Round-2 Finding 1 resolved.

**Issue 3's narrowing did not leave the DESIGN case homeless.** AC1 (`:132-136`)
now reads "Neither `references/pipeline-model.md` nor
`skills/prd/references/prd-format.md` documents a ROADMAP as a legal upstream for
a PRD or a DESIGN," and both named files are in Issue 3's `Files` (`:150`). Per
PRD R5.2 the DESIGN case is not stated outright anywhere — it follows from the
nearest-produced rule, which lives at `prd-format.md:27` and
`pipeline-model.md:121`, both Issue 3's. Issue 3 AC3 separately requires that
rule to survive with the roadmap case removed. `skills/design/references/design-format.md`
carries no roadmap mention at all (`grep -rni roadmap` returns nothing), which is
why dropping it from `Files` in round 2 was correct and why the DESIGN case has
no third home to lose. Covered.

**AC7's grounding-input carve-out is correctly bounded.** "Language describing a
roadmap as a grounding *input* is not a violation… the sweep is about what a
document records, not what a skill reads" (`:250-253`) excuses
`skills/brief/references/phases/phase-1-discover.md` (`:19` "an anchor for
grounding", `:40` "Mode: Upstream ROADMAP", `:147` artifact-template field),
which was round-2 Finding 4's unowned judgment call. It does not excuse
`phase-2-draft.md:75`, which writes the field into frontmatter — that is
recording, and it is Issue 4's under AC3. Round-2 Finding 4 resolved.

**Earlier sequencing findings still hold.** Issue 5 remains independent of 1–3
(no file overlap; PLAN→ROADMAP is legal under both the new table and today's
prose; `/plan` still has no `--upstream`). Issue 4 remains genuinely unblocked
(its five files intersect nothing; AC1's justification and AC6's rewrite are both
self-contained). Issue 6 still genuinely needs 4 and 5 for AC1, AC2 and AC6.
Issue 7 still needs 6.

## Structure

Five single-pr required sections — Status, Scope Summary, Decomposition
Strategy, Issue Outlines, Implementation Sequence — present in canonical order,
matching `plan_execution_mode_sections()` at
`crates/shirabe-validate/src/formats.rs:56` exactly. Seven `### Issue` headings
against `issue_count: 7`, each carrying Goal, Acceptance Criteria and
Dependencies. Every `<<ISSUE:N>>` reference (1×2, 3, 4, 5, 6) resolves to an
existing outline; Issue 7 is referenced by nothing, which is correct for a leaf.

## Findings

**Note 1. The sequence section opens at a coarser granularity than it closes.**
`:286` still reads "Two chains run in parallel from the start and join at Issue
6," while `:305` reads "three strands run in parallel." Both are true at their
own resolution — two chains is validator-vs-skills, three strands is the
post-Issue-1 branch — and the outlines are unambiguous either way, so this is a
readability nit rather than a contradiction. The two paragraphs at `:299-303` and
`:305-308` also state Issue 6's three-way join twice in a row.

**Note 2. `pipeline-model.md`'s BRIEF-facing prose is closed by Issue 3 AC2
rather than by AC1.** The narrowing dropped BRIEF from AC1, but Issue 3 still
owns the file carrying `:113` (`Brief (upstream: Roadmap, per feature)`) and
`:137-139`. AC2's requirement that the file say the crossing "is recorded on the
PLAN alone" contradicts both sites and forces them, and Issue 6's AC7 catches any
residual. No gap in practice — worth knowing that the BRIEF half of Issue 3's
file is asserted by AC2 and the sweep, not by AC1.

**Note 3. Atomicity, complexity and execution mode are unchanged and sound.**
Issue 5 remains the widest spread and is still held together by the design's
argument that the script's sequence blindness is a hard dependency of the flag;
Issue 2 remains the largest but is one deliverable. No issue is really two. No
`**Complexity**` values appear, which is correct for single-pr — the outline
format at `skills/plan/references/quality/plan-doc-structure.md:197-211` requires
only Goal, Acceptance Criteria and Dependencies. The single-pr justification
(`:38-49`) rests on the regression window alone and holds: with Issue 4 unlanded,
a first PR of Issues 1–3 ships a validator that rejects what `/brief` still
normally produces.
