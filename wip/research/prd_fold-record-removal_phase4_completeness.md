# Completeness Verdict: PRD-fold-record-removal (pass 2)

## Verdict

**FAIL** — 3 blocking findings.

The rewrite is a large, genuine improvement. All seven first-pass findings are
resolved (finding 6's second half included — see below; the lead's suspicion was
wrong, `phase-2-chain-orchestration.md:827` contains the literal string `fold
record` and AC3 reaches it). Brief IN-scope coverage is complete, the OUT list is
uncrossed, the numbering is clean, Out of Scope and Known Limitations are honest,
and the BRIEF's deferred open question is closed.

What fails is a structural gap the first pass located but did not name as a
class. The PRD's only two mechanical sweeps, AC2 and AC3, are keyed to exactly
two literal strings: `docs/folds.md` and `fold record`/`fold-record`. Every
reference to the record phrased with neither — "the record checker", "a durable
record column", "the record", "adds three groups", "nine-step" — is invisible to
both. R12 and R18 are written to bind those references, but **neither requirement
has any criterion that would fail if they were left standing**, and I found three
such sites the first pass did not (`skills/scope/SKILL.md:572-575`,
`phase-2-chain-orchestration.md:677`, `phase-3-exit-finalization.md:366`).

---

## Disposition of first-pass findings

### Finding 1 — `skills/scope/evals/evals.json` uncovered — **RESOLVED**

R13 is new and specific about the rewrite-not-scrub obligation:

> **R13.** The scope eval fixture SHALL be rewritten rather than scrubbed. It
> currently specifies the append and its ordering relative to the `git rm`; after
> the change it SHALL specify the absorb procedure as it then exists, so the eval
> asserts a step sequence that is real.

AC21 backs it and names both the `expected_output` (`:293`) and rubric (`:304`)
obligations without hard-coding line numbers:

> **AC21.** `skills/scope/evals/evals.json` describes the absorb procedure as it
> exists after the change: no expected output or rubric criterion mentions
> appending a row or its ordering relative to the deletion, and the scenario
> still asserts the procedure's remaining ordering guarantees.

The Problem Statement inventory sentence (`:79-81`) now reads "a merge attribute,
an append-only assertion, a cleanup carve-out, a citation-search exclusion, **an
eval fixture**, and seven shipped documents of rationale" — the fixture is in the
count. Verified against the fixture: `:293` does say "It appends one row to
docs/folds.md and git adds it before anything is deleted", `:304` does say "Plan
appends the docs/folds.md row and git adds it BEFORE the git rm of the BRIEF".
R13's characterisation is accurate.

(One residue, non-blocking, listed under Optional: `:293` also ends "commits the
deletion, the splice, the survivor's edits **and the record** together". That
clause survives both AC2 and AC3 and is not literally an append mention, so AC21
can pass with it left in.)

### Finding 2 — stale "three readers" comments — **PARTIAL**

R12 is new and its scope is right:

> **R12.** References to the record that do not spell its path SHALL be
> corrected, not left standing. This binds at minimum the "three readers" model
> asserting the record checker as one of them, wherever it appears, and any prose
> describing a durable record column.

"wherever it appears" reaches all three sites, and "any prose describing a
durable record column" reaches `formats.rs:193`. The requirement half is
resolved.

The criterion half is not. The author's note says AC3 backs it. It does not.
I ran the AC3 grep; none of the four sites contains the string `fold record` or
`fold-record`:

- `crates/shirabe-validate/src/formats.rs:177-182` — "three sites read it … the
  **record checker's** fold signature (the *trigger*)"
- `crates/shirabe-validate/src/formats.rs:193` — "it reaches a required-section
  splice and **a durable record column**"
- `.github/workflows/check-scope-scripts.yml:25-31` — "one owner and **three
  readers** … the **record checker's** fold signature (the trigger)"
- `skills/scope/scripts/check-citations.sh:44-47` — "the string has one owner
  even though **three sites read it**"

AC18 (`git diff -- crates/` touches comment lines only, `cargo test` passes)
passes if `crates/` is not touched at all. There is no AC anywhere for
`check-scope-scripts.yml`, which is not named in the PRD at all — not in a
requirement, not in a criterion. See Blocking 1.

### Finding 3 — R10 covered only four documents — **RESOLVED**

R10 now enumerates seven by path, each with the reason it goes stale, and I
verified every claim against the file:

| # | Path | R10's claim | Verified |
|---|---|---|---|
| 1 | `docs/briefs/BRIEF-scope-artifact-persistence.md` | "lists a durable default-branch record as an in-scope item" | `:140` — "A durable record, on the default branch, of what folded into what and on what date" ✓ |
| 2 | `docs/prds/PRD-scope-artifact-persistence.md` | "carries R20, the requirement the record discharges" | ✓ (`:628` also asks "What surface carries R20's record?") |
| 3 | `docs/designs/current/DESIGN-scope-artifact-persistence.md` | "chose the record's surface" | `:164` — "**What surface carries the fold record.**" ✓ |
| 4 | `docs/prds/PRD-scope-consolidation-over-skipping.md` | "its existing amendment names the record as the successor's mechanism" | `:414`, inside `## Amendment — 2026-08-15` ✓ |
| 5 | `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | "cites the record in its Option D answer" | `:846`, inside `## Amendment — 2026-08-15` ✓ |
| 6 | `docs/prds/PRD-scope-chain-mandatory-steps.md` | "lists the fold record among what stays as shipped" | `:784` — "the citation preflight, the carry check, and the fold record stay as shipped" ✓ |
| 7 | `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md` | "justifies its clean-cancel carve-out by the shape of the record's carve-out, which R4 deletes" | `:313` and `:719` — "in the shape the fold record's carve-out already uses" ✓ |

AC15 covers all seven ("Each of the seven documents named in R10 …"). Statuses
are correct as stated (1, 2, 4, 6 Done; 3, 5, 7 Current).

### Finding 4 — `BRIEF-scope-artifact-persistence.md:140` unamended — **RESOLVED**

It is #1 in R10's list, with the correct characterisation. The Decisions section
explains the expansion from four to seven and singles this one out: "the BRIEF
that put a durable record in scope at the altitude where the decision was
actually made".

### Finding 5 — old R13 (crates comment-only) had no AC — **RESOLVED**

Now R15, backed by AC18:

> **AC18.** `git diff <merge-base>..HEAD -- crates/` touches comment lines only,
> and `cargo test` passes.

That criterion fails if compiled behaviour changes. Note it does *not* also serve
as R12's criterion — it passes vacuously when `crates/` is untouched.

### Finding 6a — `skills/scope/SKILL.md:544` — **RESOLVED**

Now the fourth bullet under R8:

> - the clause in `skills/scope/SKILL.md` defining the `absorb` verdict as ending
>   with the fold being recorded.

The site reads "…every link to it re-pointed, and the fold recorded." — `fold
record` is a substring of `fold recorded`, so AC3 fails if it is left standing.
Covered.

### Finding 6b — `phase-2-chain-orchestration.md:823-827` — **RESOLVED**

The lead flagged this as the one most likely still uncovered. **It is covered,
and plainly so.** The site reads:

> `verdict:` against `{absorb, keep}` and `stage:` against `{preflight,
> judgment, carry}` — both serialized into the durable **fold record**.

It contains the literal string `fold record`, so AC3's grep fails on it. It is
additionally reached by R12's first sentence ("References to the record that do
not spell its path SHALL be corrected"). No change needed here.

### Finding 7 — AC2 contradicted R10's amendment-in-place mechanism — **RESOLVED**

AC2 now enumerates ten path exclusions explicitly: the seven R10 documents plus
the three documents of this removal chain. AC3 inherits the same set. R18 states
the exemption in the requirement layer:

> **R18.** … Body prose inside the seven amended documents is deliberately
> exempt: R10 preserves those bodies unedited and records the change in an
> appended section, so the historical text stays as written.

AC15 requires the amendment text to contain `folds.md`, which is consistent with
AC2 excluding those files. No contradiction remains.

---

## Independent inventory re-check

I ran all four greps at `HEAD` (9513d9d) and mapped every hit. `wip/` excluded
throughout.

### `git grep -n 'docs/folds\.md' HEAD -- ':!wip/'`

| Site | Covered by | Status |
|---|---|---|
| `.gitattributes:10` | R7 / AC4 | OK |
| `.github/workflows/validate-docs.yml:104,137,138,147,157,158,160` | R5 / AC5 | OK |
| `README.md:87` | R8 bullet 3 / AC13 | OK |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md:19,231,308,330,412` | R10 #3 / AC15; AC2 excludes | OK |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:846` | R10 #5, R10a / AC15, AC16 | OK |
| `docs/guides/doc-validation.md:56` | R9 / AC14 | OK |
| `docs/prds/PRD-scope-consolidation-over-skipping.md:414` | R10 #4 / AC15 | OK |
| `skills/execute/SKILL.md:597` | R8 bullet 1 / AC11 | OK |
| `skills/execute/scripts/run-cascade.sh:465` | R8 bullet 2 / AC12 | OK |
| `skills/scope/SKILL.md:857` | R3 / AC9 | OK |
| `skills/scope/evals/evals.json:293,304` | R13 / AC21 | OK |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:668` | R2 / AC8 | OK |
| `skills/scope/references/phases/phase-3-exit-finalization.md:375` | R3 / AC9 | OK |
| `skills/scope/references/phases/phase-4-cleanup.md:111` | R4 / AC10 | OK |
| `skills/scope/scripts/check-citations.sh:56,69` | R6 / AC6 | OK |
| `skills/scope/scripts/check-citations_test.sh:122` | R6 / AC7 | OK |
| the removal chain's own BRIEF/PRD | n/a — AC2 excludes | OK |

### `git grep -in 'fold record\|fold-record' HEAD -- ':!wip/'` (new hits only)

| Site | Covered by | Status |
|---|---|---|
| `.gitattributes:3` (comment block) | R7 / AC4 | OK |
| `.github/workflows/validate-docs.yml:102,149` | R5 / AC5 | OK |
| `README.md:86` | R8 bullet 3 / AC13 | OK |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md:164` | R10 #3 / AC15 | OK |
| `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:313,719` | R10 #7 / AC15 | OK |
| `docs/folds.md:1` | R1 / AC1 | OK |
| `docs/guides/doc-validation.md:54` | R9 / AC14 | OK |
| `docs/prds/PRD-scope-chain-mandatory-steps.md:784` | R10 #6 / AC15 | OK |
| `skills/scope/SKILL.md:544` | R8 bullet 4; AC3 | OK |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:827` | R12; AC3 | OK |
| `skills/scope/scripts/check-citations.sh:56,114` | R6 / AC6 | OK |
| `skills/scope/scripts/check-citations_test.sh:126,127` | R6 / AC7 | OK |

### `git grep -n 'merge=union' HEAD`

`.gitattributes:10` → R7/AC4. `docs/folds.md:51` → dies with AC1. Everything else
is `wip/` or this chain's own documents. **No uncovered hit.**

### `git grep -n '\-\-record' HEAD -- ':!wip/'`

`skills/scope/scripts/check-citations.sh:52,56,75` → R6/AC6 (AC6 asserts
`--record x` exits non-zero with an unknown-option error). **No uncovered hit.**

### Additional sweeps I ran (`folds`, `append-only`, bare `record`/`the row`)

These are the sites the four prescribed greps structurally cannot reach. Five are
covered; **four are not**.

| Site | Text | Reached by |
|---|---|---|
| `crates/shirabe-validate/src/formats.rs:177-182` | "three sites read it … the record checker's fold signature (the *trigger*)" | R12 — **no AC** ❌ |
| `crates/shirabe-validate/src/formats.rs:193` | "it reaches a required-section splice and a durable record column" | R12 — **no AC** ❌ |
| `.github/workflows/check-scope-scripts.yml:25-31` | "one owner and three readers … the record checker's fold signature (the trigger)" | R12 — **no AC**, file unnamed in PRD ❌ |
| `skills/scope/scripts/check-citations.sh:44-47` | "the string has one owner even though three sites read it" | R12 — **no AC** ❌ |
| `skills/scope/SKILL.md:572-575` | "The full **nine-step** procedure, its rollback table, the firing condition, **the record**, and the prohibition on reintroducing a durable-artifact floor live in the Consolidation Judgment section of `phase-2-chain-orchestration.md`." | R18 — **no AC**; R2/AC8's step-count clause is scoped to the procedure, not this cross-reference ❌ |
| `skills/scope/references/phases/phase-3-exit-finalization.md:366` | "Phase 2's absorb adds **three groups**, recorded here because the enumeration is closed across the skill" | R3 — **AC9 passes with it stale** ❌ |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:677` (step 9) | "**Commit** the deletion, the re-point, the survivor's edits and **the record** together." | R18/R2 — AC8 forbids mentions of "an append or an un-append"; "the record" is neither ❌ |
| `skills/scope/evals/evals.json:293` (tail) | "commits the deletion, the splice, the survivor's edits and **the record** together" | R13 — AC21 forbids append/ordering mentions only ❌ |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:616` | "Nine steps. Steps 1 and 2 are Stages 1 and 2 above" | R2 / AC8 ✓ |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:679-701` (rollback table rows 7/8, un-append paragraph, resume clause) | R2 / AC8 ✓ |
| `skills/scope/references/phases/phase-4-cleanup.md:112-113` | "as Phase 2's append target … it is a durable record on the …" | R4 / AC10 ✓ |
| `skills/scope/scripts/check-citations_test.sh:117-118` (comment header) | R6 / AC7 ✓ |
| `docs/prds/PRD-scope-artifact-persistence.md:628` | "What surface carries R20's record?" | R10 #2 / AC15 ✓ |
| `references/parent-skill-security.md` | no fold-record content — confirmed clean | n/a ✓ |

---

## R -> AC coverage map

| Req | Criteria | Would the AC fail if the R were unmet? |
|---|---|---|
| R1 remove `docs/folds.md` | AC1 | Yes |
| R2 absorb procedure rewrite | AC8 | Yes for the step list, count sentence, rollback table, un-append paragraph. **No** for step 9's "and the record together" |
| R3 no append in write-target set | AC9 | Yes for the Append bullet. **No** for the "adds three groups" count at `phase-3:366` |
| R4 no cleanup carve-out | AC10 | Yes |
| R5 remove workflow step | AC5 | Yes |
| R6 citation preflight | AC6, AC7 | Yes |
| R7 remove `merge=union` | AC4 | Yes |
| R8 replace prose claims | AC11 (b1), AC12 (b2), AC13 (b3), AC3 (b4) | Yes for b1-b3 (positive replacement asserted). For b4 only absence is asserted, not replacement — minor |
| R9 adopter docs | AC14 | Yes |
| R10 seven amendments | AC15 | Yes |
| R10a Option D amendment content | AC16 | Yes |
| R11 rationale DESIGN survives | AC17 | Yes — the file cannot exist if the chain folded it |
| R12 non-path references | **none** | **No — blocking** |
| R13 eval fixture rewrite | AC21 | Yes for the append/ordering. **No** for the trailing "and the record together" |
| R14 survivor trace unchanged | AC19 | Yes |
| R15 crates comment-only | AC18 | Yes |
| R16 no new validator error | AC20 | Yes |
| R17 test suites pass | AC7, AC12 | Yes |
| R18 no dangling reference in executable/adopter surfaces | AC2, AC3 | **Partially — both are literal-string greps that cannot reach any reference phrased without the path or the words "fold record"** |

Every AC1-AC21 maps back to at least one requirement. No orphan criteria.

---

## Rubric findings

**1. BRIEF Scope-Boundary IN → requirement.** Complete.

| BRIEF IN item | Requirement |
|---|---|
| Removing `docs/folds.md` and the append step | R1, R2 |
| Removing the verification step + adopter-facing documentation | R5, R9 |
| Removing the merge attribute | R7 |
| Removing the citation-search exclusion | R6 |
| Replacing the two prose claims (execute rule, cascade roadmap line) | R8 bullets 1, 2 |
| Amending the four shipped documents | R10 (seven — superset, justified in Decisions) |
| Recording why, and which carriers were rejected | R11 |

**2. No requirement crosses the BRIEF's OUT list.** Confirmed. R14 restates the
survivor-side trace as untouchable, matching the BRIEF's second OUT item. R11
records rejected carriers without building one, matching "Building a replacement
carrier". Out of Scope repeats all six OUT items and adds one (the five
pre-existing corpus errors).

**3. Independent inventory.** Above. Four uncovered sites, one stale-count site,
two "the record" residues.

**4. Numbering.** R1-R18 plus R10a, no gaps, no duplicates. AC1-AC21, no gaps.
**R10a is acceptable** — it is a sub-requirement that elaborates R10's item 5 and
sits adjacent to it, which reads better than renumbering eight requirements. Each
requirement is independently testable in principle.

**5. Every requirement has a failing criterion.** R12 does not. R18's criteria
are structurally too narrow. R2, R3 and R13 each have one uncovered edge. See
Blocking 1-3.

**6. Out of Scope deliberate and explained.** Yes — seven items, each with a
reason rather than a bare exclusion. "Fixing the defects in the fold-record check
as standalone work" carries the strongest reasoning (the defects are evidence,
not debt).

**7. Known Limitations honest.** Yes, and unusually so. The first bullet concedes
the central residual — the fold shape where the last survivor is later deleted
and nothing records the chain ran — and admits R8's roadmap cell only narrows it
rather than closing it. The second concedes the whole specification is written
against a mechanism that has never executed. The third notes two documents will
carry two amendments.

**8. BRIEF's deferred Open Question closed.** Yes. The BRIEF deferred "what a
roadmap's downstream cell says when a chain folds to nothing". Decisions and
Trade-offs opens with it: the cell keeps the folded-versus-never-started
distinction and drops only the pointer, and it cannot point at a surviving
artifact because the case where it fires is the case where there is none. The
residual is carried into Known Limitations rather than hidden.

**9. HOW-not-WHAT drift.** Acceptable. R2's enumeration of the step sequence,
count sentence, rollback table and un-append paragraph, and AC8's contiguity and
row-per-writing-step assertions, are prescriptive — but for a removal PRD the
sites to change *are* the what, and the DESIGN still owns what each replacement
claim says (the Status section says so explicitly). R10a comes closest to drift
by scripting the amendment's content, but it is scripting the *claim*, not the
prose. No blocking finding here.

---

## Required changes

1. **Give R12 a criterion.** As written, R12 is unfalsifiable: the four sites
   that motivated it contain neither `docs/folds.md` nor `fold record`, so AC2
   and AC3 both pass with all four left standing, and AC18 passes vacuously when
   `crates/` is untouched. Add a criterion that names the four sites and asserts
   the positive replacement, e.g.:

   > **AC22.** Neither `crates/shirabe-validate/src/formats.rs`,
   > `.github/workflows/check-scope-scripts.yml`, nor
   > `skills/scope/scripts/check-citations.sh` describes the absorbed-path
   > pattern as having three readers or names a record checker among them, and
   > `formats.rs`'s `contribution_heading` doc comment names no durable record
   > column. Each states the readers that remain.

   Also add `.github/workflows/check-scope-scripts.yml` to R12's binding list by
   path — it is currently named nowhere in the PRD, and it is a CI workflow, so
   an implementer sweeping only `crates/` and `skills/` will miss it.

2. **Extend R2/AC8 (or R18/AC2) to reach the references phrased as "the
   record".** Three executable sites survive every criterion in the document:

   - `skills/scope/references/phases/phase-2-chain-orchestration.md:677` — step 9
     "Commit the deletion, the re-point, the survivor's edits and **the record**
     together."
   - `skills/scope/SKILL.md:572-575` — "The full **nine-step** procedure, its
     rollback table, the firing condition, **the record**, and the prohibition
     …". Two things go stale here: the step count and the enumeration member.
     AC8's step-count clause reads as scoped to the procedure in phase-2, not to
     this cross-reference.
   - `skills/scope/evals/evals.json:293` (tail) — "commits the deletion, the
     splice, the survivor's edits and **the record** together."

   The cheapest fix is to widen AC8 from "no step, row, or paragraph mentions an
   append or an un-append" to "…mentions an append, an un-append, or a record
   committed alongside the deletion", and to add a clause naming
   `skills/scope/SKILL.md`'s cross-reference sentence (step count and member
   list) to R2 alongside phase-2's.

3. **Cover the stale group count at
   `skills/scope/references/phases/phase-3-exit-finalization.md:366`.** The
   read-back opens "Phase 2's absorb adds **three groups**, recorded here because
   the enumeration is closed across the skill rather than per phase". AC9 as
   written passes when the Append bullet is deleted and that sentence is left
   saying three. This is the same defect class R2/AC8 already handles for the
   step count, so the fix should be symmetric — add to AC9: "and the sentence
   stating how many groups Phase 2's absorb adds matches the number of groups
   listed."

---

## Optional improvements

- **AC2/AC3's exclusion set omits the chain's own PLAN.** It excludes
  `docs/briefs/BRIEF-fold-record-removal.md`, `docs/prds/PRD-fold-record-removal.md`
  and `docs/designs/current/DESIGN-fold-record-removal.md`, but not
  `docs/plans/PLAN-fold-record-removal.md`. If the chain produces a PLAN — and
  R11's `keep` obligation implies the design-to-plan hop runs — both criteria
  fail on the PLAN's own title. Add the plan path to the exclusion list.

- **AC15's date test can pass vacuously on two documents.** It requires a heading
  matching `## Amendment — <date>` where the date is "on or after the date this
  change lands". `PRD-scope-consolidation-over-skipping.md:394` and
  `DESIGN-scope-consolidation-over-skipping.md:822` already carry `## Amendment —
  2026-08-15`. If the change lands on 2026-08-15 those two satisfy AC15 without a
  new section being written. Pinning to "strictly after the merge base's newest
  amendment date", or requiring a second heading in those two files, closes it.

- **R8 bullet 4 gets only an absence test.** AC11 and AC13 assert a positive
  replacement for the `/execute` rule and the README description; the
  `skills/scope/SKILL.md:544` `absorb` verdict definition gets only AC3's absence
  grep, so deleting "and the fold recorded" satisfies it. That may be the right
  outcome for a verdict definition, but R8's own framing is "replaced … rather
  than deleted", so the criterion and the requirement disagree in scope.

- **R12's second clause is narrower than its first.** "any prose describing a
  durable record column" is written to catch `formats.rs:193`, but a reader
  encountering it without that site in hand will not know what a "durable record
  column" is — the record's row schema is being deleted. Naming the file makes
  the clause self-explanatory.
