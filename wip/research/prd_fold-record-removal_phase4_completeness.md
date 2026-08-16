# Completeness Verdict: PRD-fold-record-removal

## Verdict

FAIL

Seven blocking findings. The brief's IN list is fully covered and nothing
crosses the OUT list — the document is well-shaped at the scope level. It fails
on inventory: the independent grep found seven removal sites in the tree that no
requirement reaches, and one acceptance criterion (AC2) is unsatisfiable as
written because it contradicts R10's amendment-in-place mechanism. The author's
upstream research asserted "`folds.md` appears in zero eval files," which is
false, so the inventory the requirements were written against is wrong at the
source.

## Brief IN-scope coverage map

| Brief IN item | Covering requirement | Verdict |
|---|---|---|
| Removing `docs/folds.md` and the append step that writes it | R1 (file), R2 (append step) | Covered — but the append step is *also* specified in `skills/scope/evals/evals.json`, which no requirement reaches (B1) |
| Removing the fold-record verification step from the shared validation workflow, and the adopter-facing documentation describing it | R5, R9 | Covered |
| Removing the merge attribute that exists only to serve the record | R7 | Covered |
| Removing the citation-search exclusion | R6 | Covered |
| Replacing the two prose claims that cite the record as evidence | R8 (three bullets: the fully-folded-chain rule, the cascade's roadmap cell, plus `README.md` which the author added beyond the brief's two) | Covered, correctly widened |
| Amending the four shipped documents whose requirements and decisions the record discharges | R10 | Covered as stated and faithful to the brief's count of four — but the real count is higher (B3, B4), and the brief undercounted too |
| Recording why a shared fold log was removed and which alternative carriers were measured and rejected | R11 | Covered |

No orphan IN-scope items. Every brief IN bullet maps to at least one R-number.

## OUT-list crossing check

No requirement crosses the brief's OUT list.

- **The consolidation judgment itself** — untouched; Out of Scope bullet 1
  restates it. R2 changes only what the absorb procedure *records*.
- **The survivor-side trace** — R12/AC17 assert it is unchanged and byte-identical.
  Asserting non-change is a constraint, not work on an OUT item; this is the
  correct handling, since the trace is the carrier the removal depends on.
- **Re-deciding design-into-plan absorbability** — R10's second sentence is
  careful: the decision "stays shipped," only the supporting argument is
  restated. No crossing.
- **Building a replacement carrier** — R11 records *why not*; it builds nothing.
  Out of Scope bullet 2 names all seven measured carriers.
- **Fixing the CI defects as standalone work** — Out of Scope bullet 4 names all
  four defects and says they die with the step. No requirement repairs any of them.
- **Migration** — Out of Scope bullet 5.

## Independent inventory check

Command run (rubric's grep, plus an unfiltered pass and greps for `--record`,
`merge=union`, and `fold record`/`fold-record` case-insensitive):

```
grep -rn "folds\.md" --include="*.md" --include="*.yml" --include="*.sh" --include="*.rs" . | grep -v "^./wip/"
```

**Note on the rubric's grep itself:** its `--include` list omits `*.json`, which
is why the `skills/scope/evals/evals.json` hits do not appear in it. The
unfiltered pass is what surfaced them. Anyone re-running the prescribed grep to
confirm this inventory will reproduce the author's blind spot.

Full site list, and whether a requirement or criterion reaches it:

| # | Site | Reached by | Verdict |
|---|---|---|---|
| 1 | `.gitattributes:3-9` (comment block), `:10` (`docs/folds.md merge=union`) | R7 / AC3 | OK |
| 2 | `README.md:86-87` | R8 / AC12 | OK |
| 3 | `.github/workflows/validate-docs.yml:102-166` (whole `Verify the fold record` step) | R5 / AC4 | OK |
| 4 | `.github/workflows/check-scope-scripts.yml:25-31` — comment: "three readers … **the record checker's fold signature (the trigger)**" | **nothing** | **B2** |
| 5 | `skills/scope/scripts/check-citations.sh:52,56,69,75,99-101,114-121,145` (`--record` flag, default, record path-shape assertion, `:!$record` in both grep tiers, the "The record is not a chain document" comment) | R6 / AC5 | OK |
| 6 | `skills/scope/scripts/check-citations.sh:42-48` — header comment "the string has one owner even though **three sites read it**" | **nothing** (R6 binds the record exclusion; this comment is about `DOC_PATH_RE`) | **B2** |
| 7 | `skills/scope/scripts/check-citations_test.sh:117-129` (fixture write + "the fold record does not refuse a later hop") | R6 / AC6 | OK |
| 8 | `skills/scope/SKILL.md:855-861` (Append group in the closed write-target set + its justification) | R3 / AC8 | OK |
| 9 | `skills/scope/SKILL.md:544` — the `absorb` verdict definition: "…every link to it re-pointed, **and the fold recorded**" | weakly — no path string, so AC2 misses it; R2 binds the *procedure*, not the verdict definition | **B6** |
| 10 | `skills/scope/evals/evals.json:293` (expected_output narrative: "It **appends one row to docs/folds.md and git adds it** before anything is deleted") and `:304` (rubric criterion: "Plan appends the docs/folds.md row and git adds it **BEFORE** the git rm of the BRIEF") | AC2's `skills/` clause only; **no requirement** | **B1** |
| 11 | `skills/scope/references/phases/phase-2-chain-orchestration.md:667-669` (absorb step 6) | R2 / AC7 | OK |
| 12 | `skills/scope/references/phases/phase-2-chain-orchestration.md:823-827` — enum re-validation rationale: "`verdict:` … and `stage:` … both serialized into **the durable fold record**" | **nothing** (R2 binds the step sequence and rollback table; AC7 asserts only those) | **B6** |
| 13 | `skills/scope/references/phases/phase-3-exit-finalization.md:375` | R3 / AC8 | OK |
| 14 | `skills/scope/references/phases/phase-4-cleanup.md:111-121` (carve-out + 9-line justification) | R4 / AC9 | OK |
| 15 | `skills/execute/SKILL.md:596-600` | R8 / AC10 | OK |
| 16 | `skills/execute/scripts/run-cascade.sh:465` | R8 / AC11 | OK (see optional note on AC11's weak half) |
| 17 | `docs/guides/doc-validation.md:54-68` (`### Fold-record verification`) | R9 / AC13 | OK |
| 18 | `docs/designs/current/DESIGN-scope-artifact-persistence.md:19,231,308,330,412` (+ `:427,477,571,653-656` without the path string) | R10 / AC14 | Covered by R10 — but the body hits make **AC2 unsatisfiable** (**B7**) |
| 19 | `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:846` (inside `## Amendment — 2026-08-15`) | R10 / AC14 | OK |
| 20 | `docs/prds/PRD-scope-consolidation-over-skipping.md:414` (inside `## Amendment — 2026-08-15`) | R10 / AC14 | OK |
| 21 | `docs/prds/PRD-scope-artifact-persistence.md:161` (R15 bookkeeping clause), `:241` (R20 — the requirement backer), `:549` | R10 / AC14 | OK |
| 22 | `docs/briefs/BRIEF-scope-artifact-persistence.md:140` (status **Done**) — Scope Boundary IN: "A durable record, on the default branch, of what folded into what and on what [date]" | **nothing** (not among R10's four; no path string, so AC2 misses it) | **B4** |
| 23 | `docs/prds/PRD-scope-chain-mandatory-steps.md:784` (status **Done**) — Out of Scope: "The absorbability judgment, the citation preflight, the carry check, and **the fold record stay as shipped**" | **nothing** | **B3** |
| 24 | `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:313` and `:719` (status **Current**) — the clean-cancel carve-out is justified as being "in the shape **the fold record's carve-out already uses**" | **nothing** | **B3** |
| 25 | `crates/shirabe-validate/src/formats.rs:177-182` (doc comment on `ABSORBED_ENTRY_PATTERN`: "three sites read it … **the record checker's fold signature (the trigger)**") and `:193` ("it reaches a required-section splice and **a durable record column**") | AC17 names it only as an *exception* to byte-identity; no requirement mandates the correction | **B2** |

Sites 4, 6, 9, 12, 22, 23, 24, 25 share one root cause: R15/AC2 is a search for
the literal path `docs/folds.md`, and every one of these sites refers to the
record by description rather than by path. The dangling-reference sweep the PRD
relies on as its safety net cannot see them.

Sites checked and clean: no eval other than `skills/scope/evals/evals.json`
touches the record; `crates/` contains no code path that reads it (only the two
doc comments at site 25); `check-scope-scripts.yml`'s parity assertion keys on
`DOC_PATH_RE`, not on the record path-shape check, so R6 does **not** break it —
only its comment goes stale.

## R -> AC coverage map

| Requirement | Covering AC(s) | Verdict |
|---|---|---|
| R1 file removed | AC1 | Discriminating |
| R2 absorb procedure | AC7 | Discriminating |
| R3 closed write-target set | AC8 | Discriminating |
| R4 cleanup carve-out | AC9 | Discriminating |
| R5 workflow step | AC4 | Discriminating |
| R6 citation preflight + its test | AC5, AC6 | Discriminating |
| R7 merge attribute | AC3 | Discriminating |
| R8 three prose claims | AC10, AC11, AC12 | Discriminating (AC11's first half; see optional note) |
| R9 adopter documentation | AC13 | Discriminating |
| R10 four dated amendments | AC14 | Discriminating |
| R11 durable removal record | AC15 | Discriminating |
| R12 survivor trace unchanged | AC17 | Discriminating |
| **R13 no compiled behavior change** | **none** | **B5** |
| R14 repo validation passes | AC16 (`shirabe validate`), AC6 (scope-scripts suite) | Covered, but see B5 — no criterion runs the Rust test suite |
| R15 no dangling reference | AC2 | **Unsatisfiable as written — B7** |

No criterion covers nothing. Every AC1-AC17 maps to a requirement.

## Rubric findings

**1. Brief IN-scope coverage.** Complete. Seven IN bullets, all mapped, no
orphans. The author correctly widened R8 beyond the brief's "two prose claims"
to three by adding `README.md:87` — that is a legitimate discovery, not scope
creep, since the brief's phrasing described the count rather than fixing it.

**2. OUT-list crossing.** Clean. No requirement crosses any of the six OUT
items. R12 asserting the survivor trace is unchanged is the right way to handle
an OUT item the work depends on. The Out of Scope section adds two items beyond
the brief (auditing adopting repositories, and splitting migration from
auditing) — both genuine.

**3. Removal inventory.** **Fails.** Eight sites reached by nothing (table
above). The critical one is `skills/scope/evals/evals.json`: a scope eval's
expected_output and one of its rubric criteria both mandate the append,
including its ordering relative to the `git rm`. This is not a passing mention —
it is a durable behavioral specification of the procedure R2 changes, and the
fix is a rewrite of a narrative sentence plus deletion of a rubric line, not a
string scrub. The upstream research the PRD rests on
(`wip/research/explore_fold-record-scaling_r1_lead-blast-radius.md:37`)
asserts "**No eval anywhere asserts on the record.** Grepped all 20 skills:
`folds.md` appears in zero eval files." That claim is false and the requirements
inherit it.

**4. Numbering.** R1-R15 contiguous, no gaps, no duplicates. AC1-AC17
contiguous. Independently testable: yes for all fifteen, with the caveat that
R13's testability is asserted but never exercised (B5).

**5. R -> AC coverage.** R13 has no covering criterion. Nothing asserts that no
compiled behavior changed — no build, no `cargo test`, no assertion that the
Rust delta is comment-only. AC17 covers only the survivor-trace constants'
byte-identity, and R14's "the repository's own validation" is explicitly scoped
to the doc validator and the scope-scripts suite. R13 explicitly *permits*
touching Rust source ("limited to comments"), so a criterion that the crate
still builds and its tests still pass is the one thing that would catch a
mistake there, and it is absent.

**6. Out of Scope deliberateness.** Good. All six bullets carry a reason, and
the fourth (the CI defects) does real work — it names all four defects and
explains why they are deleted rather than repaired, which is the strongest
bullet in the section. None is filler.

**7. Known Limitations honesty.** Honest, and the stated residual is the real
one. The claim that a fold shape loses its only carrier matches the brief
("the case where the last survivor is itself deleted after the chain
finishes") and matches the exploration finding that the survivor-side trace
covers every fold whose survivor stays on disk. Nothing larger is glossed. The
second limitation — that the removal is verified against machinery that has
never executed — is a candid admission most PRDs would omit. No finding.

**8. The brief's deferred Open Question.** Closed. The first Decisions and
Trade-offs entry answers it directly ("It states that the chain folded and stops
there"), names both alternatives (point at the surviving artifact; say nothing),
explains why each loses, and notes the choice is unconstrained because no
roadmap carries the text today. This is exactly the closure surface the format
contract prescribes for a BRIEF's deferred questions.

**9. Content boundaries.** No architecture, no code, no task breakdown, no
security analysis. Two minor altitude wobbles, neither blocking:

- **R5** lands a remove-versus-reduce judgment in a requirement ("the step SHALL
  be removed rather than reduced"). That is a design choice with its rationale
  attached. It is defensible at requirements altitude for a removal PRD, but it
  is the one place the document decides HOW rather than WHAT.
- **R6** enumerates a script's internal constructs ("a flag, a default, a
  path-shape assertion, or a search exclusion"). For a removal, naming what is
  removed is unavoidable; this sits just inside the line.

## Required changes

1. **Add a requirement covering the scope eval.**
   `skills/scope/evals/evals.json:293` (expected_output) and `:304` (rubric
   criterion) both specify the append and its ordering relative to the `git rm`.
   Bind them explicitly — the eval specifies the absorb procedure, so it must be
   rewritten, not scrubbed, or the eval will assert a step that no longer
   exists. Add a matching acceptance criterion. Also correct R13's inventory
   sentence, which lists "prose, workflow configuration, a shell script and its
   test, and repository metadata" and omits eval fixtures entirely.

2. **Add a requirement covering the stale "three readers" comments.** Three
   sites claim the document-path shape has three readers, one of which is the
   record checker R5 deletes:
   `crates/shirabe-validate/src/formats.rs:177-182` (and `:193`'s "a durable
   record column"), `.github/workflows/check-scope-scripts.yml:25-31`, and
   `skills/scope/scripts/check-citations.sh:42-48`. None contains the string
   `docs/folds.md`, so R15/AC2 cannot reach them. AC17 currently mentions the
   `formats.rs` case only as an *exception* to a byte-identity assertion, which
   permits the correction without requiring it.

3. **Extend R10 and AC14 past four documents, or add a requirement for the
   secondary references.** Three sites in two further shipped documents go stale:
   `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:313` and `:719`
   (status Current) justify the clean-cancel carve-out as being "in the shape the
   fold record's carve-out already uses" — R4 deletes that shape; and
   `docs/prds/PRD-scope-chain-mandatory-steps.md:784` (status Done) lists the
   fold record under Out of Scope as staying "as shipped." AC14's fixed count of
   four excludes both.

4. **Cover `docs/briefs/BRIEF-scope-artifact-persistence.md:140`.** That BRIEF
   (status Done) carries "A durable record, on the default branch, of what
   folded into what and on what date" as a Scope Boundary IN item. It is the
   exact BRIEF-altitude decision this PRD's own `motivating_context` says "was
   fixed at BRIEF altitude and never re-examined." A PRD that names that framing
   as the root of the problem and then leaves the framing document unamended has
   a hole a reader will find.

5. **Give R13 an acceptance criterion.** Add a criterion that the crate builds
   and its test suite passes, and that the Rust delta is confined to comments.
   R13 permits touching Rust source; nothing currently verifies the permission
   was not exceeded.

6. **Cover the two description-only sites in `skills/scope/`.**
   `skills/scope/SKILL.md:544` ("and the fold recorded" in the `absorb` verdict
   definition) and
   `skills/scope/references/phases/phase-2-chain-orchestration.md:823-827` (the
   `verdict:`/`stage:` enum re-validation is justified as "both serialized into
   the durable fold record"). The second matters more than its size suggests:
   deleting the clause without replacing it leaves a security control with no
   stated reason. The values still reach the survivor's `## Status` line, so a
   correct replacement justification exists — but a requirement has to ask for it.

7. **Resolve the contradiction between R10 and R15/AC2.** AC2 asserts that a
   search for `docs/folds.md` "returns hits only inside dated amendment sections
   and this chain's own artifacts." `DESIGN-scope-artifact-persistence.md` has
   no Amendment section today and carries the path at lines 19 (frontmatter
   `decision:`), 231, 308, 330, and 412 — all body text that R10's
   amendment-in-place mechanism deliberately preserves, and that the Decisions
   entry explicitly declines to discard. As written, AC2 cannot pass unless the
   amended documents' bodies are rewritten, which R10 forbids. Either carve the
   four amended documents' bodies out of AC2 and R15, or state that the sweep is
   scoped to executable and adopter-facing surfaces. This is the one place the
   document contradicts itself.

## Optional improvements

- **AC2's exclusion list is not the inventory.** It names `skills/`, `.github/`,
  `crates/`, `README.md`, and `.gitattributes`. `docs/guides/doc-validation.md`
  carries the path at line 56 and is covered only by AC13. Adding `docs/guides/`
  would make the list match the tree.

- **AC11's second half does not discriminate.** `run-cascade_test.sh:466-473`
  asserts only that the roadmap's `**Downstream:**` line does not match
  `PLAN-|DESIGN-`. The current string `_none (chain folded; see docs/folds.md)_`
  already satisfies that, so the suite passes whether or not the string changes.
  AC11's first clause ("contains no pointer to the record") is the half that
  does the work; consider dropping the suite reference or asking for the test to
  assert the new text.

- **R2's "renumbered and rewritten" verges on prescribing method.** The
  outcome property AC7 tests — a contiguous step list and one rollback row per
  step — is the thing worth requiring; the renumbering is how you get there.

- The Status section says "Requirements are drafted and awaiting the jury,"
  which will need updating on the transition to Accepted.
