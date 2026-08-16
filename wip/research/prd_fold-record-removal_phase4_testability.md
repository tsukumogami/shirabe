# Testability Verdict: PRD-fold-record-removal (pass 2)

## Verdict

**FAIL** — 4 blocking.

The rewrite is a large, real improvement. Eight of the ten first-pass findings
are fully resolved, and the two empirical claims I was asked to check hardest —
the merge-base error count of five, and the em-dash in `## Amendment — <date>` —
are both **correct**. AC2 and AC3 parse and run. `cargo test` passes at the
merge base, so AC18 is meetable.

What blocks is narrower and mostly new. The criterion added to close finding 3
(AC3) **catches none of the four sites that motivated it** — its pattern misses
the two that matter and its exclusion set hides the other two by design. AC19,
the rewrite of the old AC17, now false-fails a correct implementation because
its file set is described by property and that property picks up three files
other criteria mandate changing. AC21's discriminating half permits exactly the
scrub R13 forbids. And AC11 is the old AC10 verbatim — a first-pass blocking
finding that did not make the author's fix list.

---

## Disposition of first-pass findings

| # | Finding | Disposition |
|---|---|---|
| 1 | AC2/R10 contradiction | **RESOLVED.** AC2 enumerates ten path exclusions covering all seven amended docs plus this chain's three artifacts; R18 states the body exemption explicitly. Ran AC2 verbatim: it parses, exits 0, and returns 20 hits — none inside an amended document's body. No contradiction remains. |
| 2 | AC2 not a single mechanical test | **RESOLVED.** It is now one literal `git grep … HEAD -- <pathspecs>` with an unambiguous revision. Verified runnable. |
| 3 | No criterion for non-path references | **NOT RESOLVED.** AC3 exists, but of the four sites the first pass named it catches **zero**. See B1. |
| 4 | AC7's "one row per step" false | **RESOLVED.** AC8 now says "one row per writing step with step numbers matching the renumbered list", and reaches both the step-count sentence (line 615, "Nine steps") and the un-append paragraph. Confirmed against the live table: 5 writing steps → 5 rows today, 4 after removal. |
| 5 | AC14 vacuous on two already-amended docs | **RESOLVED.** AC15's date test discriminates: both existing amendments are `2026-08-15` and both *do* contain `folds.md`, so only the "on or after the date this change lands" clause separates them — and it does. |
| 6 | AC14's "affirmative statement" was judgment | **PARTIAL.** AC16 is split into two clauses, but neither is a locatable string. "Including the case where nothing does" is a genuine falsifier; "the phrase naming the surviving half" is not greppable. Better, still judgment. |
| 7 | AC15's artifact unpinned | **RESOLVED.** AC17 pins `docs/designs/current/DESIGN-fold-record-removal.md` (confirmed absent today) and names seven carriers. The PRD can no longer satisfy it by accident. |
| 8 | R14/AC16 unmeetable | **RESOLVED.** R16 is now relative-to-baseline and AC20 states the number. I verified the baseline independently: **five**. The author's claim is correct. |
| 9 | No criterion for R13 | **RESOLVED for R15 (`crates/`).** AC18 exists, and I confirmed both halves are satisfiable: the `crates/` diff is empty and `cargo test` is 805/805. (Note the requirement renumbered: old R13 → new R15.) |
| 10 | AC17's exception escapable | **PARTIAL.** AC19 pins the baseline and bounds by line kind — both fixes applied. But it introduced a worse defect in the file set. See B2. |

Not on the author's list, and still open: the first pass also returned a
**blocking** FAIL on its AC10 (the `skills/execute/SKILL.md` rule). That
finding did not make the numbered required-changes list, and the criterion —
now AC11 — is unchanged. See B3.

---

## Per-criterion analysis

All commands run from
`/home/dgazineu/dev/niwaw/tsuku/tsuku+folds_doesnt_scale-99919916/public/shirabe/.claude/worktrees/fold-record-scaling`
at `HEAD = 9513d9d`, merge base `39b0981`.

### AC1 — `docs/folds.md` absent

| | |
|---|---|
| Command | `test ! -e docs/folds.md` |
| Ran | Yes. File exists. **Fails today** — correct. |
| Binary | Yes. |
| Catches violation | Yes, with AC2 closing the uncommitted-`rm` gap. |
| Verdict | **PASS** |

### AC2 — no `docs/folds.md` outside the exclusion set

| | |
|---|---|
| Command | Verbatim from the PRD, ten `':!…'` pathspecs. |
| Ran | Yes. **Parses.** Exit 0, 20 hits: `.gitattributes:10`, `validate-docs.yml:104,137,138,147,157,158,160`, `README.md:87`, `doc-validation.md:56`, `execute/SKILL.md:597`, `run-cascade.sh:465`, `scope/SKILL.md:857`, `evals.json:293,304`, `phase-2:668`, `phase-3:375`, `phase-4:111`, `check-citations.sh:56,69`, `check-citations_test.sh:122`. **Fails today** — correct. |
| Binary | Yes. |
| Catches violation | Yes for path-spelled references. |
| Verdict | **PASS** |

Exclusion audit: the ten exclusions hide only the seven R10 documents, this
chain's three artifacts, and `wip/`. Nothing else is hidden. `crates/`,
`.github/`, `skills/`, `README.md`, `docs/guides/` and `docs/designs/archive/`
all stay inside the search. `docs/folds.md` itself is not excluded, which is
right — AC1 owns its deletion. No accidental hiding at the path level.

### AC3 — no `fold record` / `fold-record` outside the same set

| | |
|---|---|
| Command | `git grep -in 'fold record\|fold-record' HEAD` + AC2's ten pathspecs. |
| Ran | Yes, both forms. **Parses** (BRE `\|` alternation works). Literal form: 143 hits. With exclusions: 12 hits — `.gitattributes:3`, `validate-docs.yml:102,149`, `README.md:86`, `docs/folds.md:1`, `doc-validation.md:54`, `scope/SKILL.md:544`, `phase-2:827`, `check-citations.sh:56,114`, `check-citations_test.sh:126,127`. **Fails today.** |
| Binary | Yes. |
| Catches violation | **Only for references that use the two-word form.** See B1. |
| Verdict | **FAIL — blocking (B1)** |

### AC4 — `.gitattributes`

| | |
|---|---|
| Command | `grep -n 'merge=union\|folds' .gitattributes` |
| Ran | Yes. 7-line comment block + `docs/folds.md merge=union` at line 10. **Fails today** — correct. |
| Binary | Yes. |
| Catches violation | Yes. Correct outcome is a one-line file. |
| Verdict | **PASS** — still the cleanest criterion in the set. |

### AC5 — `validate-docs.yml` has no fold step

| | |
|---|---|
| Command | `grep -n 'folds.md\|Verify the fold record\|git show\|rev-parse' .github/workflows/validate-docs.yml` |
| Ran | Yes. Step `Verify the fold record` at 102; `git show "$HEAD:docs/folds.md"` at 137, 147; `git rev-parse "$BASE:$doc"` at 146. **Fails today** — correct. |
| Binary | Yes. |
| Catches violation | Yes. |
| Verdict | **PASS.** The first pass's false-trap objection to listing `grep` is **fixed** by the qualifier "against the record path" — the surviving `grep`s at lines 90 and 120 are not against the record path. |

### AC6 — `check-citations.sh --record x`

| | |
|---|---|
| Command | `bash skills/scope/scripts/check-citations.sh --record x; echo $?` |
| Ran | Yes. Exit **3**, message `check-citations: --target is required`. |
| Binary | Yes, if the verifier reads the message. |
| Catches violation | Yes — **the message is the discriminator.** Baseline confirmed: `--bogus x` today gives `check-citations: unknown argument: --bogus`, exit 3. So "exits non-zero" is vacuous but "with an unknown-option error" is not. |
| Verdict | **PASS.** The first pass's tightening was effectively adopted by naming the error class. |

### AC7 — `check-citations_test.sh`

| | |
|---|---|
| Command | `bash skills/scope/scripts/check-citations_test.sh` |
| Ran | Yes. **10 passed, 0 failed** — the pass half is a regression guard, vacuous today by design. The record case at lines 122–127 makes the "no case" half **fail today**. |
| Binary | Yes. |
| Catches violation | Yes. |
| Verdict | **PASS** |

### AC8 — absorb procedure renumbered, count sentence, rollback table, no append/un-append

| | |
|---|---|
| Command | Read `skills/scope/references/phases/phase-2-chain-orchestration.md` lines 614–706. |
| Ran | Yes. "Nine steps." at 615; step 6 is "**Append the record and stage it**"; rollback rows `5 write / 6 append / 7 delete / 8 re-validate / 9 commit` (5 rows, 5 writing steps — consistent with "one row per writing step"); un-append paragraph at 696–698. **Fails today.** |
| Binary | Close to it. "Writing step" is defined in the prose above the table ("Every step from 5 onward writes"), so the row count is derivable, not guessed. |
| Catches violation | Yes, on all four halves. A renumber that leaves "Nine steps" fails. |
| Verdict | **PASS.** Finding 4 fully addressed. One gap it happens to close by accident: the resume paragraph at line 700 ("interrupted between steps 5 and 9, un-append the row") is a paragraph mentioning an un-append, so the criterion reaches it. Minor: the criterion never names the file. |

### AC9 — closed write-target set

| | |
|---|---|
| Command | `grep -n 'Append' skills/scope/SKILL.md skills/scope/references/phases/phase-3-exit-finalization.md` |
| Ran | Yes. `scope/SKILL.md:856-860` "**Append**, by Phase 2's absorb: `docs/folds.md`…"; `phase-3:375` "- **Append:** `docs/folds.md`, a fixed constant." **Fails today.** |
| Binary | Yes for the append-group half; "do not contradict each other" is judgment, but the two sites are short parallel enumerations. |
| Catches violation | Yes. |
| Verdict | **PASS** |

### AC10 — cleanup carve-out

| | |
|---|---|
| Command | `grep -n 'folds' skills/scope/references/phases/phase-4-cleanup.md` |
| Ran | Yes. Line 111 opens a 9-line carve-out. **Fails today.** |
| Binary | Yes. |
| Catches violation | Yes. |
| Verdict | **PASS** |

### AC11 — `/execute` fully-folded-vs-unfinalized rule

| | |
|---|---|
| Command | No mechanical form for the positive half. `grep -n 'folds' skills/execute/SKILL.md` for the negative half. |
| Ran | Yes. Line 597: "Distinguishing it from a genuinely unfinalized chain is what `docs/folds.md` is for… The record is the evidence." **Fails today on the grep half only.** |
| Binary | **No.** |
| Catches violation | **No** for "names the surface a reader consults instead." |
| Verdict | **FAIL — blocking (B3)** |

### AC12 — cascade cell + `run-cascade_test.sh`

| | |
|---|---|
| Command | `grep -n 'folds' skills/execute/scripts/run-cascade.sh` and `bash skills/execute/scripts/run-cascade_test.sh` |
| Ran | Yes. Line 465 emits `**Downstream:** _none (chain folded; see docs/folds.md)_` — **fails today.** Suite: **19 passed, 0 failed**, including a "PLAN→ROADMAP, no DESIGN (folded chain)" scenario that asserts on that exact cell. |
| Binary | Yes. |
| Catches violation | Yes, and the test is a real coupling: changing the string forces a deliberate assertion update. |
| Verdict | **PASS** — best-designed criterion in the set. |

### AC13 — README

| | |
|---|---|
| Command | `grep -n 'folds' README.md` |
| Ran | Yes. Lines 86–87. **Fails today.** |
| Binary | Yes. |
| Catches violation | **Mostly.** Deleting the whole consolidation paragraph also passes, and R8 forbids deletion. The first pass's suggested clause was not added. |
| Verdict | **PASS (one clause short)** |

### AC14 — `doc-validation.md`

| | |
|---|---|
| Command | `grep -n 'Fold-record\|folds.md' docs/guides/doc-validation.md` |
| Ran | Yes. `### Fold-record verification` heading at line 54 with a description through 68. **Fails today.** |
| Binary | Yes. |
| Catches violation | Yes. |
| Verdict | **PASS** |

### AC15 — seven dated amendments, statuses unchanged

| | |
|---|---|
| Command | `grep -n '^## Amendment' <doc>` per doc; `git show 39b0981:<doc> \| grep '^status:'` vs HEAD. |
| Ran | Yes. All seven files exist. Statuses: BRIEF-artifact-persistence `Done`, PRD-artifact-persistence `Done`, DESIGN-artifact-persistence `Current`, PRD-consolidation `Done`, DESIGN-consolidation `Current`, PRD-mandatory-steps `Done`, DESIGN-mandatory-steps `Current`. Existing amendments: only `PRD-scope-consolidation-over-skipping.md:394` and `DESIGN-scope-consolidation-over-skipping.md:822`, both `2026-08-15`. **Fails today on all seven.** |
| Binary | Yes. |
| Catches violation | Yes — and the vacuity the first pass found is gone. See the heading check below. |
| Verdict | **PASS** |

### AC16 — the consolidation design's amendment

| | |
|---|---|
| Command | No single command; two substring searches plus a read. |
| Ran | Partially — the target amendment does not exist yet. |
| Binary | **No.** |
| Catches violation | Partially. "Including the case where nothing does" is a real falsifier a reviewer can apply; "the phrase naming the surviving half of the answer (the record of *why*, in the code)" is not a literal string and admits many paraphrases. |
| Verdict | **PASS (weak, judgment-bounded)** — improved over pass 1, not mechanical. |

### AC17 — `DESIGN-fold-record-removal.md` and seven carriers

| | |
|---|---|
| Command | `test -e docs/designs/current/DESIGN-fold-record-removal.md` then grep for each carrier. |
| Ran | Yes. **File does not exist.** Fails today — correct. |
| Binary | Yes for existence and for the seven names; "with a reason for rejection" needs a read but is bounded per carrier. |
| Catches violation | Yes. The PRD can no longer satisfy it — the path is pinned to a file that is not the PRD. |
| Verdict | **PASS** |

### AC18 — `crates/` comment-only, `cargo test` passes

| | |
|---|---|
| Command | `git diff 39b0981..HEAD -- crates/` and `cargo test` |
| Ran | Yes. Diff is **empty** (0 lines). `cargo test`: **805 passed, 0 failed**, plus 0 doc-tests. Both halves vacuous today — correct for a regression guard, and critically it is **meetable**, unlike the old R14. |
| Binary | Yes. |
| Catches violation | Yes. |
| Verdict | **PASS** |

### AC19 — survivor-trace surfaces, comment lines only

| | |
|---|---|
| Command | Not runnable as written — the file set is a property, not a path list. |
| Ran | Partially; I resolved the property myself (below). |
| Binary | **No.** |
| Catches violation | **It false-fails the correct outcome on the natural reading.** |
| Verdict | **FAIL — blocking (B2)** |

### AC20 — validator clean on the changed set, corpus errors ≤ 5

| | |
|---|---|
| Command | `shirabe validate --visibility=public <changed docs>`; corpus count (invocation not specified — I used `git ls-files 'docs/**/*.md' 'docs/*.md'`, 177 files). |
| Ran | Yes, both halves. Corpus at HEAD: **exactly 5 `::error`**, 127 `::notice`, 0 `::warning`. Merge-base-equivalent corpus (same 175 files; the only docs/ files added since `39b0981` are this chain's BRIEF and PRD): **also 5**. |
| Binary | Yes once the corpus command is fixed; the criterion does not fix it. |
| Catches violation | Yes — a new error from a bad amendment or the new DESIGN raises the count above 5. |
| Verdict | **PASS (one tightening needed: pin the corpus invocation)** |

### AC21 — `evals.json` rewritten, not scrubbed

| | |
|---|---|
| Command | Search `skills/scope/evals/evals.json` for `folds.md` / append prose; read scenario `consolidation-absorb-brief-into-prd` (eval index 18). |
| Ran | Yes. Two sites: `expected_output` (one long narration, contains "It appends one row to docs/folds.md and git adds it before anything is deleted") and `expectations[8]` ("Plan appends the docs/folds.md row and git adds it BEFORE the git rm of the BRIEF, then re-runs shirabe validate on the surviving PRD and commits the deletion, the splice, the edits and the record together"). **Fails today** on the first half. |
| Binary | First half yes. Second half **no**. |
| Catches violation | **No** for the half that matters. |
| Verdict | **FAIL — blocking (B4)** |

---

## Empirical claim checks

**AC2 and AC3 parse.** Both run clean. `git grep <pat> HEAD -- ':!…'` is valid,
the exclusion pathspecs take effect, and AC3's `\|` alternation works under
git's default BRE. Neither has a syntax defect.

**AC3 does not catch the four sites the previous pass named.** Verified one by
one:

| Site | Text | Caught by AC3? |
|---|---|---|
| `.github/workflows/check-scope-scripts.yml:27` | "the validator's FC18 (the backstop), and **the record checker's fold signature** (the trigger)" | **No** — contains neither `fold record` nor `fold-record`. Also contains no `docs/folds.md`, so AC2 misses it too. |
| `DESIGN-scope-chain-mandatory-steps.md:313` | "in the shape the fold record's carve-out already uses" | **No** — pattern matches, but the file is in AC3's exclusion set. |
| `DESIGN-scope-chain-mandatory-steps.md:719` | "the shape the fold record's already uses" | **No** — same exclusion. |
| `PRD-scope-chain-mandatory-steps.md:784` | "the fold record stay as shipped" | **No** — same exclusion. |

The last three are exempt **by design** under R18 (amended-document bodies), so
those are defensible. The first is not: `check-scope-scripts.yml` is an
executable surface, which R18 explicitly says must carry no dangling reference.
And a fourth site the first pass did not find is in the same shape:

- `crates/shirabe-validate/src/formats.rs:177-182` — doc comment on
  `ABSORBED_ENTRY_PATTERN`: "three sites read it … this crate's
  absorbed-declaration check (the *backstop*) … and **the record checker's fold
  signature** (the *trigger*). None substitutes for another."

Both become false the moment R5 deletes the checker. AC18 and AC19 *permit*
comment edits in `crates/` but never *require* them, and no criterion names
`check-scope-scripts.yml` at all.

**AC2's exclusion list hides nothing it shouldn't.** Audited above under AC2.

**AC20's true merge-base error count is five.** Confirmed independently without
`git stash`: `git diff --stat 39b0981..HEAD` shows the only non-`wip/` additions
are `docs/briefs/BRIEF-fold-record-removal.md` and
`docs/prds/PRD-fold-record-removal.md`, so the other 175 corpus files are
byte-identical to the merge base. Validating those 175 gives 5 `::error`;
validating all 177 also gives 5. The five:

```
BRIEF-fc06-index-alias.md:20            [R10] BRIEF may not name DESIGN as upstream
BRIEF-lifecycle-draft-ready-discipline.md:18  [R10] BRIEF may not name BRIEF as upstream
BRIEF-single-pr-plan-validation.md:4    [R6]  upstream PLAN does not exist on disk
BRIEF-single-pr-plan-validation.md:4    [R11] BRIEF names a PLAN as upstream
BRIEF-skill-cascade-lifecycle-check.md:24     [R10] BRIEF may not name BRIEF as upstream
```

The author's claim is **correct**. Note also that `docs/folds.md` is itself in
the corpus and emits one FC10 style *notice* (exit 0), not an error, so deleting
it does not move the count. The one gap: AC20 says "the full docs corpus" without
naming an invocation, and CI validates only *changed* files, so no precedent
exists. I had to choose the file set. Two verifiers can pick different sets.

**AC15's heading format matches the corpus exactly.** Hexdumped both. The corpus
headings are `## Amendment` + `20 e2 80 94 20` + date — U+2014 EM DASH with
single spaces. AC15's pattern in the PRD is byte-identical: `## Amendment` +
`20 e2 80 94 20` + `<date>`. **No mismatch.** Two caveats, both minor: the
corpus also uses a suffixed form (`## Amendment — 2026-07-06: default-on hooks…`
in three other documents), so "matching" should be read as prefix-match, not
exact-match; and the date test relies on the verifier knowing the landing date.
The vacuity the first pass found is genuinely gone — the two existing
`2026-08-15` amendments *do* contain `folds.md`, so the date clause is doing all
the discriminating work, and it does it.

**AC18's `cargo test` baseline passes.** 805 passed, 0 failed. The criterion is
meetable. `git grep -in 'folds\|fold record' -- crates/` returns only two
unrelated uses of "folds" as a verb (`lifecycle.rs:998`, `populate.rs:2032`), so
the required `crates/` diff really is comment-only or empty.

**AC21's remaining assertion set is not checkable as stated.** The scenario's
ten expectations include four ordering assertions: #2 (preflight before anything
composed/written/deleted), #5 (carry check before anything written), #7 (splice
ordering within the single pass), and #8 (append → `git rm` → re-validate →
atomic commit). Only #8 mentions the append. R13 demands a rewrite, which means
#8 must survive as "`git rm` the BRIEF, then re-run `shirabe validate` on the
surviving PRD, then commit the deletion, the splice and the edits together" —
preserving three guarantees. But AC21 says only "the scenario still asserts the
procedure's remaining ordering guarantees" without enumerating them, and #2 and
#5 are themselves ordering assertions. **Deleting #8 outright passes AC21** —
which is precisely the scrub R13 exists to forbid.

---

## Vacuous criteria

| Criterion | Vacuous part | Evidence |
|---|---|---|
| AC7 | "exits 0" | 10 passed, 0 failed today. |
| AC12 | "exits 0" | 19 passed, 0 failed today. |
| AC18 | both halves | `crates/` diff empty; `cargo test` 805/805. |
| AC20 | "no greater than five" | corpus is at exactly 5 today. |
| AC6 | "exits non-zero" only | exit 3 today, but with a *different* message; the message clause discriminates. |

All five are legitimate regression guards — a guard that passes before the change
is behaving correctly. **None of the disqualifying vacuity from pass 1 survives.**
AC15, AC17 and AC20 all now fail or bind today where their predecessors did not.

---

## Requirement coverage gaps

| Req | Catching AC | Assessment |
|---|---|---|
| R1 | AC1, AC2 | Covered. |
| R2 | AC8 | Covered, well. |
| R3 | AC9 | Covered. |
| R4 | AC10 | Covered. |
| R5 | AC5 | Covered. |
| R6 | AC6, AC7 | Covered. |
| R7 | AC4 | Covered. |
| R8 bullet 1 | AC11 | Absence half covered; positive half cannot fail. **B3.** |
| R8 bullet 2 | AC12 | Covered. |
| R8 bullet 3 | AC13 | Covered; wholesale deletion still passes. |
| **R8 bullet 4** | AC3 only | **Gap.** `skills/scope/SKILL.md:544` ("and the fold recorded") is caught by AC3 as an *absence* obligation, but R8 says "replaced … rather than deleted". No criterion requires the absorb verdict definition to still state what the verdict ends with. |
| R9 | AC14 | Covered. |
| R10 | AC15 | Covered. |
| R10a | AC16 | Covered, judgment-bounded. |
| R11 (rationale) | AC17 | Covered. |
| **R11 (`keep` obligation)** | **none** | **Gap.** "That design SHALL survive this chain … the consolidation judgment at the design-to-plan hop SHALL reach `keep`" has no criterion. AC17 only asserts the file exists at this change's HEAD. |
| **R12** | AC3 (misses both named sites) | **Gap — B1.** |
| R13 | AC21 | Covered; the discriminating half is escapable. **B4.** |
| R14 | AC19 | Covered by a criterion that false-fails. **B2.** |
| R15 | AC18 | Covered. |
| R16 | AC20 | Covered; corpus invocation unpinned. |
| R17 | AC7, AC12 | Covered. |
| R18 | AC2, AC3 | Covered for path-spelled and two-word references; the `check-scope-scripts.yml` executable surface escapes both. |

**Does any criterion merely restate its requirement?** Only AC11, which restates
R8's first bullet and adds no verification method. Everything else names a
concrete file, string, or command — a genuine strength of this draft.

**Partial-removal edge case.** Better covered than pass 1: AC3 now sweeps
two-word references across `skills/`, `.github/`, `README.md` and `crates/`. The
residual is exactly B1 — the two "three readers"/"three sites" comments that name
the record checker without using either pattern.

---

## Required changes

1. **Close R12 (B1).** AC3's pattern catches neither site R12 names as its
   minimum binding. Add a criterion pinned to the two sites by path:
   `.github/workflows/check-scope-scripts.yml` and
   `crates/shirabe-validate/src/formats.rs` each describe the document-path
   shape's readers without naming a record checker, and the reader count in each
   comment matches the number that remains. A general search will not do this —
   the phrase is "the record checker's fold signature", which matches neither
   `docs/folds\.md` nor `fold[ -]record`. Alternatively broaden AC3's pattern to
   `fold record\|fold-record\|record checker\|fold signature`; I verified
   `record checker` has no false positives outside the exclusion set beyond
   `.gitattributes:9`, which AC4 already deletes.

2. **Pin AC19's file set by path, and reconcile it with AC8 and AC21 (B2).**
   "The survivor-trace surfaces … and their checks" resolves, on the natural
   reading, to a set that includes
   `skills/scope/references/phases/phase-2-chain-orchestration.md` (step 5
   specifies the `absorbed:` write, the `## Status` line, and the
   contribution-section splice) and `skills/scope/evals/evals.json` (its
   `expected_output` narrates all three) — both of which AC8 and AC21 *mandate*
   changing with non-comment edits. `.github/workflows/validate-docs.yml` also
   carries `absorbed:` handling at lines 111 and 138 that R5 deletes wholesale.
   A verifier applying AC19 literally rejects a correct implementation. Two
   further problems: "comment lines" is undefined for Markdown and JSON; and once
   the set is narrowed to files where the phrase means something, AC19 collapses
   into AC18 plus `check-scope-scripts.yml`. Restate as: the diff over
   `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/formats.rs`,
   `crates/shirabe/tests/absorption_corpus.rs` and
   `.github/workflows/check-scope-scripts.yml` touches comment lines only.

3. **Give AC11 a failing form (B3).** This is the first pass's blocking AC10,
   unchanged. "Names the surface a reader consults instead" is satisfied by
   naming any document. Either state the mechanical form — the rule names a
   concrete artifact or signal *and* states what a reader observes when even that
   is absent, which is the case the Known Limitations concede — or restate AC11
   as pure absence ("the rule does not cite the record") and move the positive
   obligation into R8 as a review obligation rather than an acceptance test.

4. **Enumerate AC21's surviving ordering guarantees (B4).** As written, deleting
   expectation 8 passes, because expectations 2 and 5 are also ordering
   assertions. Name them: the scenario asserts that the `git rm` precedes the
   re-validation, that the re-validation precedes the commit, and that the
   deletion, the splice and the survivor's edits land in one commit.

5. **Pin AC20's corpus invocation.** "The full docs corpus" has no precedent —
   CI validates only changed files. State the command, e.g.
   `shirabe validate --visibility=public $(git ls-files 'docs/**/*.md' 'docs/*.md')`,
   and that the count is of `::error` lines. With that invocation the baseline is
   five, confirmed.

6. **Add a positive obligation for R8's fourth bullet.** AC3 forces the phrase
   out of `skills/scope/SKILL.md:544` but nothing requires the `absorb` verdict
   definition to still say what the verdict ends with. R8 says "replaced …
   rather than deleted"; give the bullet the same treatment AC11–AC13 give the
   other three.

---

## Optional improvements

- **AC13**: add "and the paragraph describing the consolidation judgment
  remains", so wholesale deletion cannot pass a criterion whose requirement
  forbids deletion. (Carried over from pass 1, not applied.)
- **AC8**: name the file
  (`skills/scope/references/phases/phase-2-chain-orchestration.md`). The
  criterion is otherwise the strongest rewrite in the set.
- **AC15**: say "a heading beginning `## Amendment — <date>`" — three documents
  in this corpus use a suffixed form (`## Amendment — 2026-07-06: …`), so exact
  match would be the wrong reading.
- **AC16**: quote the surviving half as a literal to search for, the way AC15
  pins `folds.md`.
- **AC7, AC12, AC18, AC20**: label these regression guards in the text. They pass
  today by design; saying so stops a reviewer reading their vacuity as a defect.
- **R11's `keep` obligation** has no criterion. It may be genuinely unverifiable
  at this change's HEAD — if so, say that in the requirement rather than leaving
  a silent gap.
