# Plan Review — PLAN-upstream-link-legality

**Verdict:** FAIL

Round 2. All eight changes from the previous round are present and correct. One
of them — moving the repo-wide sweep assertion from Issue 3 to Issue 6 — relocated
the defect rather than removing it: Issue 6 now asserts a condition over files
Issue 3 owns, and Issue 6 has no dependency path to Issue 3. A second, smaller
defect: the Implementation Sequence contradicts itself, with its closing
parallelization line still encoding the 3→4 edge the revision deleted.

`./target/debug/shirabe validate docs/plans/PLAN-upstream-link-legality.md --visibility=public`
exits 0 with no output. Structure remains conformant: five single-pr required
sections in canonical order matching `plan_execution_mode_sections()`
(`crates/shirabe-validate/src/formats.rs:56`); seven outlines each carrying Goal,
Acceptance Criteria and Dependencies; `issue_count: 7` matching; every
`<<ISSUE:N>>` reference (1×2, 4, 5, 6) resolving.

## Round-1 changes verified

| # | Change | Status |
|---|---|---|
| 1 | `brief-format.md` moved to Issue 4's `Files`, removed from Issue 3's; Issue 4 `Dependencies: None` | Applied (`:183`, `:149`, `:180`) |
| 2 | Issue 2 AC8 cites PRD R24; Issue 7 AC4 cites PRD R22 | Applied (`:111`, `:272`) |
| 3 | Issue 3 AC1 bounded; sweep moved to Issue 6 | Applied (`:133`, `:248`) — **but see Finding 1** |
| 4 | Issue 4 AC7 grades the announcement; new AC6 covers the brief format reference | Applied (`:172`, `:175`) |
| 5 | Issue 2 gains the `is_known_check_code` criterion | Applied (`:116`) |
| 6 | `design-format.md` dropped from Issue 3 | Applied (`:149`) |
| 7 | Issue 7 AC4 folded into AC5 | Applied (`:272`) |
| 8 | Faulty half of the single-pr argument struck | Applied (`:38-49`) — the argument now rests on the regression window alone, which is the half that holds |

## Coverage map

Unchanged from round 1 and still complete. All five design implementation phases
map to issues (declarations → 1, check → 2, reference sweep → 3, skill contracts
plus the pre-flight script → 4/5/6, evals and fixtures → 4/6/7). All of R1–R25
map to an issue, and the two PRD acceptance criteria that were uncovered are now
covered: R17's `is_known_check_code` clause at Issue 2 AC10 (`:116`) and R12's
eval-grading clause at Issue 4 AC7 (`:175-178`). No acceptance criterion traces
to nothing.

The redistribution of the reference sweep changes only the ownership rows:

| Reference file documenting a forbidden shape | Owner |
|---|---|
| `references/pipeline-model.md:113, :137-139` (Brief upstream: Roadmap; "`/brief` crosses that boundary by taking a Roadmap as its upstream") | Issue 3 |
| `skills/prd/references/prd-format.md:29` (ROADMAP when no BRIEF was written) | Issue 3 |
| `skills/brief/references/brief-format.md:31, :61-63` | Issue 4 |
| `skills/brief/references/phases/phase-0-setup.md:55`, `phase-2-draft.md:75` | Issue 4 |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:172` ("the brief records that path in its `upstream:` frontmatter") | Issue 6 |

Every file that carries the forbidden shape is owned by some issue. Issue 6's new
AC7 is what now closes the `phase-2-chain-orchestration.md:172` sentence
explicitly rather than leaving it to a generous reading of AC1's "child-argument
table" — that is a genuine improvement over round 1.

## Sequencing verification

**Is Issue 4 genuinely unblocked? Yes — confirmed.** Its five files
(`skills/brief/SKILL.md`, `references/brief-format.md`,
`references/phases/phase-0-setup.md`, `references/phases/phase-2-draft.md`,
`evals/evals.json`) intersect no other issue's file list. Content is
self-contained too: AC1's justification ("a type whose legal parent set is
empty") is a statement about the declared table that reads correctly as prose
whether or not Issue 1's code has landed, and AC6's rewrite of `brief-format.md`
depends on nothing outside that file. The brief's whole surface does move in one
issue, as the sequence now claims. This resolves round 1's Finding 1.

**Is Issue 6's new sweep criterion satisfiable when Issue 6 completes? No.**
Issue 6 AC7 (`:248-250`) asserts that no file under `references/` or
`skills/*/references/` documents a ROADMAP as a legal upstream for a BRIEF, a PRD
or a DESIGN. Two of the files that do are `references/pipeline-model.md` and
`skills/prd/references/prd-format.md`, and both belong to Issue 3 (`:149`). Issue
6's declared dependencies are `<<ISSUE:4>>, <<ISSUE:5>>` (`:252`), and both of
those are `Dependencies: None`. There is no path from Issue 6 to Issue 3 —
Issue 3 hangs off Issue 1 on the validator chain, which the sequence itself
describes as running in parallel with the skills chain (`:283`). So Issue 6 can
complete with `pipeline-model.md:113` still reading `Brief (upstream: Roadmap,
per feature)` and `:137-139` still reading "`/brief` crosses that boundary by
taking a Roadmap as its upstream", at which point AC7 is false. This is round 1's
Finding 3 relocated, not fixed.

**Issue 5 independent of 1–3: still confirmed** (no file overlap; PLAN→ROADMAP is
legal under both the new table and today's prose in
`skills/plan/references/quality/plan-doc-structure.md`; `grep -n '\-\-upstream'
skills/plan/SKILL.md` still returns nothing).

**Issue 6 needs both 4 and 5: still confirmed** for AC1, AC2 and AC6, and it now
needs Issue 3 as well.

**Issue 7 needs Issue 6: confirmed** — the new-shape fixture is the shape Issue 6
produces.

## Findings

**Finding 1 (material, blocking). Issue 6's repo-wide sweep criterion has no
dependency on the issue that owns half the files it sweeps.** Detailed above. The
fix is one edge: add `<<ISSUE:3>>` to Issue 6's `Dependencies`. That is
consistent with the rest of the plan — Issue 6 is already the join point, and
adding Issue 3 to it makes the sweep the last thing the plan asserts, which is
exactly the reasoning the relocation was based on. It does not lengthen the
critical path, which runs 1→2.

**Finding 2 (material, blocking). The Implementation Sequence contradicts
itself.** Lines 290–294 state that the skills chain has two independent heads and
that Issue 4 no longer waits on the sweep. Line 300 still reads "The
parallelizable pairs are (2, 3) and (3-then-4, 5)" — the 3-then-4 serialization
the revision removed. An implementer reading the section's conclusion gets the
superseded ordering. The line needs rewriting to the new shape, and once Finding
1 is fixed it should also reflect that Issue 6 joins three predecessors rather
than two.

**Finding 3 (minor). Issue 3's AC1 still claims a case that moved to Issue 4.**
`:133` reads "No pipeline or format reference documents a ROADMAP as a legal
upstream for a BRIEF, a PRD, or a DESIGN," but the format reference carrying the
BRIEF case — `skills/brief/references/brief-format.md:61` — is Issue 4's file
now. Issue 3 owns the BRIEF case only through `pipeline-model.md`. As written the
criterion is false at Issue 3's completion whenever Issue 4 has not yet landed,
which is possible since the two are independent. Narrow the wording to the two
files Issue 3 owns, or say the BRIEF case is covered on the pipeline side only.

**Finding 4 (note, unchanged from round 1).
`skills/brief/references/phases/phase-1-discover.md` is in no issue's file
list.** It carries "Mode: Upstream ROADMAP" (`:40`), "An anchor for grounding:
either an upstream ROADMAP" (`:19`) and an artifact-template field `<upstream
ROADMAP path, OR "conversation only">` (`:147`). These read as input-mode
language rather than as statements about the frontmatter field, so they survive
the change on the most natural reading — but the verifier of Issue 6 AC7 has to
make that call unaided. One clause in AC7 excluding grounding-input language
would remove the judgment.

**Finding 5 (note). Atomicity and complexity are unchanged and remain sound.**
Issue 5 is still the widest spread (skill contract, shell script, shell tests,
eval) and is still held together by the design's argument that the script's
sequence blindness is a hard dependency of the flag. Issue 2 is the largest but
is one deliverable. No issue is really two. No `**Complexity**` values appear
anywhere, which is correct for single-pr — the outline format in
`skills/plan/references/quality/plan-doc-structure.md:197-211` requires only
Goal, Acceptance Criteria and Dependencies, with `Type` and `Files` optional.

**Finding 6 (note). The single-pr justification now holds as written.** The
rewritten argument (`:38-49`) concedes that Issues 1–3 form a defensible split on
paper and defeats it on the regression window — with Issue 4 unlanded, `/brief`
still writes a roadmap upstream, so the first PR ships a validator that rejects
what the chain normally produces. That is the correct argument and it is stated
without the faulty evaluability claim.

## Required changes

1. **Add `<<ISSUE:3>>` to Issue 6's `Dependencies`.** Its AC7 sweeps files Issue
   3 owns (`references/pipeline-model.md`,
   `skills/prd/references/prd-format.md`) and no dependency path reaches them.

2. **Rewrite the closing line of the Implementation Sequence** (`:300`). "(2, 3)
   and (3-then-4, 5)" encodes the deleted 3→4 edge and contradicts lines 290–294
   in the same section. It should also carry Issue 6's third predecessor once
   change 1 lands.

Recommended but not required: narrow Issue 3 AC1 so it does not claim the BRIEF
format-reference case that now belongs to Issue 4 (Finding 3), and add a clause
to Issue 6 AC7 excluding grounding-input language so the
`phase-1-discover.md` wording is not left to the verifier's judgment (Finding 4).
