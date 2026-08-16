# Testability Verdict: PRD-fold-record-removal

## Verdict

**FAIL**

Most of AC1–AC17 are genuinely mechanical and most fail today, which is the
right shape for a removal PRD. But three defects are disqualifying: AC2 as
written is **unsatisfiable** because it contradicts the amendment-in-place
mechanism R10 mandates; **no criterion catches a reference to the record that
does not spell the path**, and four such references exist in the tree right
now, three of which become false the moment the work lands; and AC7's
"one row per step" describes a rollback table shape the correct outcome will
not have. AC14 additionally passes vacuously on half its subjects today.

---

## Per-criterion analysis

Every command below was run from the worktree root
`/home/dgazineu/dev/niwaw/tsuku/tsuku+folds_doesnt_scale-99919916/public/shirabe/.claude/worktrees/fold-record-scaling`.

### AC1 — `docs/folds.md` does not exist in the working tree

| | |
|---|---|
| **Command** | `test ! -e docs/folds.md` |
| **Ran** | Yes. `-rw-rw-r-- 3186 bytes docs/folds.md` — **fails today.** Correct. |
| **Binary** | Yes. |
| **Catches violation** | Partially. "Working tree" is weaker than R1's "removed from the repository": an uncommitted `rm` passes AC1 while the file is still at `HEAD`. AC2 covers the gap, so this is acceptable but the two should be read together. |
| **Verdict** | **PASS (weak wording)** |

### AC2 — search of the committed tree returns hits only in dated amendment sections and this chain's own artifacts

| | |
|---|---|
| **Command** | `git grep -n 'docs/folds\.md'` (working tree) or `git grep -n 'docs/folds\.md' HEAD` (committed tree) |
| **Ran** | Yes. 60+ hits. Non-chain, non-amendment hits: `.gitattributes:10`, `.github/workflows/validate-docs.yml:104,137,138,147,157,158,160`, `README.md:87`, `docs/guides/doc-validation.md:56`, `docs/designs/current/DESIGN-scope-artifact-persistence.md:19,231,308,330,412`, `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:846`, `docs/prds/PRD-scope-consolidation-over-skipping.md:414`, `skills/execute/SKILL.md:597`, `skills/execute/scripts/run-cascade.sh:465`, `skills/scope/SKILL.md:857`, `skills/scope/evals/evals.json:293,304`, `skills/scope/references/phases/phase-2-chain-orchestration.md:668`, `phase-3-exit-finalization.md:375`, `phase-4-cleanup.md:111`, `skills/scope/scripts/check-citations.sh:56,69`, `check-citations_test.sh:122`. Plus ~20 hits under `wip/`. **Fails today.** |
| **Binary** | **No — and self-contradictory.** |
| **Catches violation** | Not reliably. See below. |
| **Verdict** | **FAIL — blocking** |

Four separate problems:

1. **It is unsatisfiable given R10.** `DESIGN-scope-artifact-persistence.md`
   carries five hits at lines 19, 231, 308, 330 and 412 — in its Summary, its
   preflight-exclusion prose, its Phase-2 append description, its
   shared-append-file argument, and its write-target enumeration. None is in an
   amendment section. R10 and the "Amendment in place, not supersession"
   decision explicitly choose to **append** an amendment rather than rewrite
   the body. So the general clause "hits only inside dated amendment sections"
   cannot be satisfied without doing exactly the body rewrite the PRD rejects.
   Same for `DESIGN-scope-consolidation-over-skipping.md:846` and
   `PRD-scope-consolidation-over-skipping.md:414` — those two happen to sit
   inside existing `## Amendment — 2026-08-15` sections, which is luck, not
   design.

2. **The two halves disagree.** The general clause ("only inside dated
   amendment sections and this chain's own artifacts") is strictly stricter
   than the trailing enumeration ("no hit in `skills/`, `.github/`, `crates/`,
   `README.md`, or `.gitattributes`"). `docs/guides/doc-validation.md:56` is a
   hit that the enumeration permits and the general clause forbids. Two
   verifiers reading the same criterion reach opposite verdicts.

3. **`wip/` is unaddressed.** ~20 hits live under `wip/`. Whether those are
   "this chain's own artifacts" is undefined. They are committed today
   (`git status` shows them tracked), and workspace CLAUDE.md requires wip
   cleanup before merge — so the answer depends on *when* the verifier runs.
   The criterion must say `:!wip/` explicitly.

4. **"Committed tree" is not operationalized.** `git grep <pat>` searches the
   index/worktree; `git grep <pat> HEAD` searches the commit. A verifier
   running the first form and an author who deleted-but-did-not-commit get
   different answers.

### AC3 — `.gitattributes` has no `merge=union` and no fold-record comment block

| | |
|---|---|
| **Command** | `grep -c 'merge=union\|folds' .gitattributes` → expect 0 |
| **Ran** | Yes. `.gitattributes` is 10 lines: a 7-line comment block about append-only union merge plus `docs/folds.md merge=union`. **Fails today.** Correct. |
| **Binary** | Yes. |
| **Catches violation** | Yes. The correct outcome leaves the file as a single line (`*.mermaid.md text eol=lf`). |
| **Verdict** | **PASS** — the strongest criterion in the set. |

### AC4 — shared validation workflow has no fold-record step

| | |
|---|---|
| **Command** | `grep -n 'folds.md\|Verify the fold record\|git show\|rev-parse' .github/workflows/validate-docs.yml` → expect 0 |
| **Ran** | Yes. Step `Verify the fold record` at line 102, `git show "$HEAD:docs/folds.md"` at 137 and 147, `git rev-parse "$BASE:$doc"` at 146. **Fails today.** Correct. |
| **Binary** | Almost. |
| **Catches violation** | Yes. Confirmed that `git show` and `rev-parse` appear **only** inside the fold step, so grepping for them is a clean signal. |
| **Verdict** | **PASS (one wording fix)** — "no `grep` … invocation" is a false trap: line 90 and line 120 use `grep` for unrelated purposes and must stay. Drop `grep` from the list, or restate as "no occurrence of the string `folds.md` and no `git show` or `rev-parse` invocation." |

### AC5 — `check-citations.sh` accepts no `--record`

| | |
|---|---|
| **Command** | `bash skills/scope/scripts/check-citations.sh --record x; echo $?` and `grep -c 'record' skills/scope/scripts/check-citations.sh` |
| **Ran** | Yes. `--record` present at lines 52, 56, 69, 75; the `^docs/[a-z0-9-]+\.md$` shape assertion at 99–100; `:!$record` exclusions in both tiers at 121 and 143. **Fails today.** Correct. |
| **Binary** | Yes for the flag and the pathspec halves. |
| **Catches violation** | **Partially vacuous.** Ran `check-citations.sh --record` with no value today: exits **3** with `check-citations: --record needs a value`. So the "exits non-zero" half already passes before any work is done — the flag is *accepted* and still exits non-zero. Only the "unknown-option error" qualifier discriminates, and that requires asserting on stderr text. |
| **Verdict** | **PASS with a required tightening** — state the assertion as: stderr matches `unknown argument: --record`. |

### AC6 — `check-citations_test.sh` passes and has no record case

| | |
|---|---|
| **Command** | `bash skills/scope/scripts/check-citations_test.sh` and `grep -n 'folds\|record' skills/scope/scripts/check-citations_test.sh` |
| **Ran** | Yes. Suite: **10 passed, 0 failed** — the "passes" half is **vacuous today**. The record case exists at lines 117–127 (`the fold record does not refuse a later hop`, writing `$dir/docs/folds.md`), so the "no case" half **fails today.** |
| **Binary** | Yes. |
| **Catches violation** | Yes for the absence half; the pass half is a regression guard, which is a legitimate role but should be labelled so nobody mistakes it for evidence of the change. |
| **Verdict** | **PASS (one half vacuous by design)** |

### AC7 — absorb procedure contiguous, rollback table one row per step, no append/un-append

| | |
|---|---|
| **Command** | Read `skills/scope/references/phases/phase-2-chain-orchestration.md` steps 3–9 (lines 619–678) and the rollback table (679–695). |
| **Ran** | Yes. Steps 3–9 present; step 6 is "**Append the record and stage it**"; rollback table rows: `5 write`, `6 append`, `7 delete`, `8 re-validate`, `9 commit`; the un-append paragraph follows. **Fails today.** |
| **Binary** | **No.** |
| **Catches violation** | **It would produce a false failure on the correct outcome.** |
| **Verdict** | **FAIL — blocking** |

"One row per step" is wrong. The table deliberately covers **only the writing
steps** — the prose above it says "Steps 1 through 4 mutate nothing … Every step
from 5 onward writes." After the removal the procedure has 8 steps and 4
writing steps, so a correct rollback table has 4 rows, not 8. A verifier
applying AC7 literally rejects a correct implementation.

Two further gaps: "contiguous and correctly numbered" does not reach the count
sentence "Nine steps. Steps 1 and 2 are Stages 1 and 2 above" at line 617,
which must become "Eight steps" — an author could renumber correctly and leave
that stale. And "neither mentions an append or an un-append" does not reach the
standalone paragraph after the table ("The un-append is explicit because the row
is forced to exist before the deletion"), which is neither the step list nor the
table.

### AC8 — closed write-target set and read-back both have no append group

| | |
|---|---|
| **Command** | `grep -n 'Append' skills/scope/SKILL.md skills/scope/references/phases/phase-3-exit-finalization.md` → expect 0 in the write-target-set regions |
| **Ran** | Yes. `skills/scope/SKILL.md:856-860` — "**Append**, by Phase 2's absorb: `docs/folds.md` — a fixed constant…". `phase-3-exit-finalization.md:375` — "- **Append:** `docs/folds.md`, a fixed constant." **Fails today.** Correct. |
| **Binary** | Yes for the append-group half. |
| **Catches violation** | Yes. |
| **Verdict** | **PASS with a caveat** — "and do not contradict each other" is judgment-shaped, but the two sites are short parallel enumerations, so a diff-style comparison is feasible. Consider restating as: "both list exactly the deletion and mutation groups, and no third group." |

### AC9 — cleanup phase has no carve-out naming the record

| | |
|---|---|
| **Command** | `grep -n 'folds' skills/scope/references/phases/phase-4-cleanup.md` → expect 0 |
| **Ran** | Yes. Line 111 opens "**`docs/folds.md` is enumerated and never swept.**" plus a 9-line justification. **Fails today.** Correct. |
| **Binary** | Yes. |
| **Catches violation** | Yes. |
| **Verdict** | **PASS** |

### AC10 — the fully-folded-vs-unfinalized rule states a criterion evaluable without the record

| | |
|---|---|
| **Command** | Human read of `skills/execute/SKILL.md:596–600`. No mechanical form exists. |
| **Ran** | Yes. Current text: "Distinguishing it from a genuinely unfinalized chain is what `docs/folds.md` is for: a chain that folded away leaves a row … The record is the evidence." **Fails today** on the grep half only. |
| **Binary** | **No.** |
| **Catches violation** | **No.** |
| **Verdict** | **FAIL — blocking** |

This is the weakest criterion in the set, as suspected. "States a criterion that
can be evaluated without the record" has no failing form: any replacement
sentence that avoids the word `folds.md` satisfies it. "Names what a reader
consults instead" is satisfied by naming *any* document, whether or not that
document actually distinguishes the two cases.

Worse, the PRD's own Known Limitations concedes that for the terminal-fold
shape "nothing on the default branch records that the chain ran" — so a
*genuine* distinguishing criterion may not exist. AC10 therefore reads as
demanding something the PRD elsewhere says is impossible, while being written
loosely enough that a hollow sentence passes it. Either state the mechanical
form (for example: the rule must name a concrete artifact or signal, and must
state what a reader observes when even that is absent), or restate AC10 as an
absence criterion — "the rule does not cite the record" — and move the positive
obligation into R8 where it can be judged in review rather than pretending to
be an acceptance test.

### AC11 — cascade downstream cell has no record pointer; `run-cascade_test.sh` passes

| | |
|---|---|
| **Command** | `grep -n 'folds' skills/execute/scripts/run-cascade.sh` and `bash skills/execute/scripts/run-cascade_test.sh` |
| **Ran** | Yes. `run-cascade.sh:465` emits `**Downstream:** _none (chain folded; see docs/folds.md)_` — **fails today.** Test suite: **19 passed, 0 failed** — the pass half is **vacuous today**. |
| **Binary** | Yes. |
| **Catches violation** | Yes, and well. The "PLAN→ROADMAP, no DESIGN (folded chain)" scenario exercises exactly this line, so the test is a real coupling: change the string and the scenario's assertion must be updated deliberately. |
| **Verdict** | **PASS** — the best-designed criterion after AC3. |

### AC12 — README describes the judgment without naming the record

| | |
|---|---|
| **Command** | `grep -n 'folds' README.md` → expect 0, plus confirm the consolidation paragraph still exists |
| **Ran** | Yes. `README.md:86-87` — "…the upstream is removed, with the fold recorded in `docs/folds.md`." **Fails today.** Correct. |
| **Binary** | Yes. |
| **Catches violation** | Mostly. It would also pass if the whole consolidation paragraph were deleted, which R8 forbids ("replaced … rather than deleted"). Add "and the paragraph describing the consolidation judgment remains." |
| **Verdict** | **PASS (one clause to add)** |

### AC13 — adopter-facing docs describe no fold-record check

| | |
|---|---|
| **Command** | `grep -n 'Fold-record\|folds.md' docs/guides/doc-validation.md` → expect 0 |
| **Ran** | Yes. `docs/guides/doc-validation.md:54` is a `### Fold-record verification` heading with a 15-line description. **Fails today.** Correct. |
| **Binary** | Yes. |
| **Catches violation** | Yes. |
| **Verdict** | **PASS** |

### AC14 — four shipped documents carry dated amendments, retain status, and the consolidation design affirms what now answers the objection

| | |
|---|---|
| **Command** | `grep -n '^## Amendment' <doc>` and `grep -n '^status:' <doc>` for each of the four; human read for the affirmative clause. |
| **Ran** | Yes, on the four most plausible subjects. `PRD-scope-consolidation-over-skipping.md` — status `Done`, **already has `## Amendment — 2026-08-15`**. `DESIGN-scope-consolidation-over-skipping.md` — status `Current`, **already has `## Amendment — 2026-08-15`**. `PRD-scope-artifact-persistence.md` — status `Done`, no amendment. `DESIGN-scope-artifact-persistence.md` — status `Current`, no amendment. |
| **Binary** | **No** for the affirmative-statement clause. |
| **Catches violation** | **No — half of it passes vacuously.** |
| **Verdict** | **FAIL — blocking** |

Three defects:

1. **The set is never enumerated.** "The four shipped documents" has a definite
   article and no list, anywhere in the PRD. R10 describes them by property
   ("whose requirements and decisions the record discharges"), which requires
   the verifier to redo the blast-radius analysis. It should be a list of four
   paths.

2. **Vacuous on two of four today.** A verifier checking "carries a dated
   amendment section" plus "retains its prior status" passes
   `PRD-scope-consolidation-over-skipping.md` and
   `DESIGN-scope-consolidation-over-skipping.md` **before any work is done**,
   because both already carry a 2026-08-15 amendment about a different subject.
   The criterion must require an amendment dated at or after this change *and*
   naming the fold record.

3. **"Affirmative statement of what now answers the objection" is judgment.**
   It can pass while the requirement is violated: writing "the survivor-side
   trace answers it" satisfies the letter, but the objection the design decision
   was rescued from concerns the terminal fold — precisely the case where there
   *is* no survivor, per the PRD's own Known Limitations. A verifier has no
   mechanical basis to reject that.

**AC14/AC16 interaction — tested, and it is fine.** I appended a
`## Amendment — 2026-08-16` section to both
`docs/prds/PRD-scope-artifact-persistence.md` (status `Done`) and
`docs/designs/current/DESIGN-scope-artifact-persistence.md` (status `Current`),
ran `shirabe validate` on both, and got **exit 0** with only the two
pre-existing FC10 style notices. Trailing amendment sections do not trip FC15
canonical ordering or FC04 required sections at terminal status. Both files
were restored byte-for-byte (`git status` clean afterwards). So amending a
terminal document is mechanically safe — the AC14 problems above are about
wording, not about validator conflict.

### AC15 — a durable artifact records the rationale and names the carriers evaluated

| | |
|---|---|
| **Command** | No command — the artifact is not named, so there is nothing to point at. |
| **Ran** | Partially. `docs/decisions/` holds seven `DECISION-*.md` files, `docs/spikes/` holds two — either would qualify as "a durable artifact". |
| **Binary** | Half. The carrier list is pinned (seven named), which is good. Everything else is not. |
| **Catches violation** | **Weakly — it is close to vacuous already.** |
| **Verdict** | **FAIL — blocking (near-vacuous)** |

The PRD's own Out of Scope section already reads: "Per-fold files, commit
trailers, git notes, forge metadata, per-chain files, and rotation schemes were
each measured during exploration and none is adopted." That is six of the seven
carriers AC15 lists, in a durable artifact under `docs/`. Add "survivor
frontmatter alone" and a reason per carrier and **this PRD satisfies AC15 with
no new artifact written at all** — which cannot be the intent, since R11 exists
because the PRD is not the durable home for that reasoning (a PRD reaches Done
and stops being read).

Fix by pinning the artifact: name the type and the path shape (for example
`docs/decisions/DECISION-fold-record-removal-<date>.md`), so the criterion reads
"file X exists and names all seven carriers with a reason each."

### AC16 — `shirabe validate` reports a clean outcome over the changed document set

| | |
|---|---|
| **Command** | `shirabe validate <changed docs>; echo $?` |
| **Ran** | Yes, several ways. On the two already-amended docs: exit 0, no output. On the two docs after appending test amendments: exit 0, two `::notice` lines. On the whole corpus (`docs/prds/*.md docs/designs/current/*.md docs/briefs/*.md`): **exit 2, 6 `::error` lines**, all pre-existing R6/R10/R11 upstream violations in `docs/briefs/`, none related to this change. |
| **Binary** | **No** — "clean outcome" is undefined against `::notice`. |
| **Catches violation** | **No — it does not verify R14, and R14 as written is unmeetable.** |
| **Verdict** | **FAIL — blocking** |

R14 says "the document validator over the corpus" must pass. The corpus **does
not pass today**, for reasons this PRD does not own
(`BRIEF-fc06-index-alias.md`, `BRIEF-lifecycle-draft-ready-discipline.md`,
`BRIEF-single-pr-plan-validation.md`, `BRIEF-skill-cascade-lifecycle-check.md`).
AC16 quietly narrows to "the changed document set", so it neither verifies R14
nor flags that R14 is unsatisfiable. One of the two must move: narrow R14 to the
changed set, or scope it to "no *new* validator error relative to the pre-change
baseline."

Separately, "clean outcome" needs a definition. Several documents in the changed
set emit FC10 style notices today. If "clean" means empty output, AC16 fails for
reasons unrelated to this change; if it means exit 0, say exit 0.

Also: R14 names two suites ("the document validator over the corpus, and the
scope-scripts test suite"). AC6 covers `check-citations_test.sh`, AC11 covers
`run-cascade_test.sh` — but `run-cascade_test.sh` is gated by
`check-execute-scripts.yml`, not `check-scope-scripts.yml`, so R14's enumeration
and the AC coverage do not line up cleanly.

### AC17 — the survivor-side trace is byte-identical except where a comment names the removed checker

| | |
|---|---|
| **Command** | `git diff <base>..<head> -- crates/shirabe-validate/src/checks.rs crates/shirabe-validate/src/formats.rs .github/workflows/check-scope-scripts.yml` and inspect that every changed line is a comment. |
| **Ran** | Partially. Confirmed `git grep 'folds\|fold record' -- crates/` returns **nothing** — the validator source has no fold-record coupling, so the FC18 machinery needs no change at all. The one site the exception clause is for is `.github/workflows/check-scope-scripts.yml:27`, whose comment calls the path shape's three readers "this script … the validator's FC18 … and **the record checker's fold signature** (the trigger). None substitutes for another." |
| **Binary** | Half. |
| **Catches violation** | **No — the exception clause is escapable.** |
| **Verdict** | **FAIL — blocking (fixable with two words)** |

Two problems. First, no baseline is pinned: "byte-identical to their pre-change
state" needs a ref (the merge base) for the diff to be reproducible by someone
who did not write the PRD. Second, "except where a comment names the removed
checker" scopes the exception by *subject matter*, not by *line kind* — so any
substantive change smuggled in next to a comment mentioning the record is
technically permitted. Restate as: "the diff over these files touches comment
lines only."

---

## Vacuous criteria

Criteria or clauses that already pass, today, before any work:

| Criterion | Vacuous part | Evidence |
|---|---|---|
| **AC5** | "invoking it with `--record` exits non-zero" | `check-citations.sh --record` → exit **3** today (`--record needs a value`). Only the stderr-text qualifier discriminates. |
| **AC6** | "`check-citations_test.sh` passes" | **10 passed, 0 failed** today. |
| **AC11** | "`run-cascade_test.sh` passes" | **19 passed, 0 failed** today. |
| **AC14** | "carries a dated amendment section" + "retains its prior status", for 2 of 4 docs | Both consolidation-over-skipping docs already carry `## Amendment — 2026-08-15` at their current statuses. |
| **AC15** | most of it | The PRD's own Out of Scope already names six of the seven carriers in a durable `docs/` artifact. |
| **AC16** | all of it | `shirabe validate` on the amended docs → exit 0 today; "the changed document set" is empty pre-change, so trivially clean. |
| **AC17** | all of it, trivially | "byte-identical to pre-change state" is true when nothing has changed. Legitimate as a regression guard, but needs a pinned baseline to mean anything. |

AC6, AC11 and AC17's vacuity is defensible — they are regression guards, and a
regression guard passing before the change is exactly what it should do. AC5's,
AC14's, AC15's and AC16's is not: those clauses are doing verification work the
PRD is relying on, and they do not do it.

---

## Requirement coverage gaps

| Req | Catching AC | Assessment |
|---|---|---|
| R1 | AC1, AC2 | Covered. |
| R2 | AC7 | Covered but AC7 is defective — see above. |
| R3 | AC8 | Covered. |
| R4 | AC9 | Covered. |
| R5 | AC4 | Covered. |
| R6 | AC5, AC6 | Covered. |
| R7 | AC3 | Covered — cleanly. |
| R8 (bullet 1) | AC10 | Covered in name only; AC10 cannot fail. |
| R8 (bullet 2) | AC11 | Covered. |
| R8 (bullet 3) | AC12 | Covered; add the "paragraph remains" clause so deletion does not pass. |
| R9 | AC13 | Covered. |
| R10 | AC14 | Covered but AC14 is half-vacuous and the set is unnamed. |
| R11 | AC15 | Covered but near-vacuous and the artifact is unpinned. |
| R12 | AC17 | Covered but the exception is escapable. |
| **R13** | **none** | **Gap.** "No compiled behavior SHALL change … any source change SHALL be limited to comments" has no criterion. AC17's byte-identical clause covers only the four named trace artifacts and their checks, not `crates/` at large. A one-line criterion fixes it: `git diff <base>..<head> -- crates/` is empty, or touches comment lines only. Cheap to satisfy — I confirmed `git grep 'folds\|fold record' -- crates/` is empty, so the correct diff is empty. |
| R14 | AC16 (partially) | **Gap.** AC16 tests a narrower set than R14 demands, and R14 as written cannot be met — the corpus exits 2 today with 6 unrelated errors. |
| **R15** | AC2 (path only) | **Gap.** See the next section — R15 says "no dangling reference"; AC2 tests only "no occurrence of the path string." |

---

## Rubric findings

### Does any criterion merely restate a requirement?

Mostly no — this is a strength of the set. AC3, AC4, AC5, AC9, AC12 and AC13 all
name a concrete file and a concrete string, which is more than their
requirements do. The exceptions are **AC10**, which restates R8's first bullet
almost word for word and adds no verification method, and **AC15**, which
restates R11 and adds a carrier list but no artifact location.

### Happy path and edge cases — the partial-removal case is NOT covered

This is the second blocking finding, and it is the one the change is most
exposed to. A removal's characteristic failure is a *dangling reference*: the
mechanism goes, the prose that depends on it stays. R15 names that risk
correctly, but AC2 operationalizes it as a **path-string grep only**. Every
reference that talks about the record without spelling `docs/folds.md` survives
the entire acceptance set. Four exist right now:

| Site | Text | Fate after the change |
|---|---|---|
| `.github/workflows/check-scope-scripts.yml:27` | "…the validator's FC18 (the backstop), and **the record checker's fold signature** (the trigger). None substitutes for another" | **Becomes false.** R5 deletes that checker. Three readers become two. Not in AC2's grep (no path string), and this file is not named by any AC. |
| `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:313` | "the handoff is carved out explicitly, **in the shape the fold record's carve-out already uses**" | **Becomes a dangling pattern reference.** R4 deletes that carve-out. Status `Current`. |
| `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:719` | "The carve-out is stated in the shape **the fold record's already uses**" | Same. |
| `docs/prds/PRD-scope-chain-mandatory-steps.md:784` | Out of Scope: "The absorbability judgment, the citation preflight, the carry check, and **the fold record stay as shipped**" | **Becomes false.** Status `Done`. |

The last three are also a **fifth and sixth shipped document** whose content the
removal falsifies — and AC14 caps the amendment obligation at "the four". Either
the set is five/six, or R10 needs a stated reason why a prose pattern-reference
does not need amending while a requirement does.

The fix is one additional criterion: a case-insensitive search for `fold record`
and `fold-record` across the committed tree, with the same exclusion set as AC2.

### Criteria that could pass while the requirement is violated

- **AC10** — any sentence naming any document passes.
- **AC12** — deleting the consolidation paragraph outright passes, though R8
  forbids deletion.
- **AC14** — a boilerplate "the prior answer is withdrawn; the survivor-side
  trace answers it" passes, even where no survivor exists.
- **AC17** — a substantive change adjacent to a comment mentioning the removed
  checker passes.
- **AC1** — an uncommitted deletion passes (mitigated by AC2).

---

## Required changes

1. **Resolve the AC2/R10 contradiction.** AC2's general clause ("hits only
   inside dated amendment sections") is unsatisfiable while R10 mandates
   amendment-in-place: `DESIGN-scope-artifact-persistence.md` carries five
   body-level hits at lines 19, 231, 308, 330, 412 that the amendment mechanism
   does not touch. Either widen AC2 to permit body hits in the amended
   documents, or state that those five sites are rewritten too (and reconcile
   with the "Amendment in place, not supersession" decision).

2. **Make AC2 a single mechanical test.** Drop the conflicting two-half phrasing
   and pin it: `git grep -n 'docs/folds\.md' HEAD -- ':!wip/' ':!docs/prds/PRD-fold-record-removal.md' ':!docs/briefs/BRIEF-fold-record-removal.md' ':!<the four amended docs>'`
   returns nothing. Name the exclusions as paths, not as categories, and say
   `HEAD` so "committed tree" is unambiguous.

3. **Add a criterion for non-path references** (covers R15's real intent and the
   partial-removal edge case): a case-insensitive committed-tree search for
   `fold record` and `fold-record`, with the same exclusions, returns nothing.
   Four live sites will fail it today —
   `.github/workflows/check-scope-scripts.yml:27`,
   `DESIGN-scope-chain-mandatory-steps.md:313` and `:719`,
   `PRD-scope-chain-mandatory-steps.md:784`.

4. **Fix AC7's rollback clause.** "One row per step" is false for the correct
   outcome: the table covers writing steps only (5 onward today, 4 rows after
   renumbering an 8-step procedure). Restate as "the rollback table has one row
   per writing step and its rows' step numbers match the renumbered list."
   Extend the append-mention clause to reach the Stage 3 count sentence ("Nine
   steps") at line 617 and the standalone un-append paragraph after the table.

5. **Enumerate AC14's four documents by path**, and require the amendment to be
   **dated on or after the change and to name the fold record** — otherwise the
   criterion passes vacuously on `PRD-scope-consolidation-over-skipping.md` and
   `DESIGN-scope-consolidation-over-skipping.md`, which already carry
   2026-08-15 amendments. Reconcile the count with finding 3: at least two more
   shipped documents are falsified by this change.

6. **Give AC14's "affirmative statement" clause a mechanical form**, or move it
   out of the acceptance set into R10 as a review obligation. As written it is
   judgment and can pass while the requirement is violated.

7. **Pin AC15's artifact.** Name the type and path shape (e.g.
   `docs/decisions/DECISION-fold-record-removal-<date>.md`). Without it the
   PRD's own Out of Scope section nearly satisfies the criterion, which defeats
   R11's purpose — a PRD reaches Done and stops being consulted.

8. **Reconcile R14 and AC16.** The corpus exits 2 today with 6 pre-existing
   errors in `docs/briefs/`, so R14 as written cannot be met. Narrow R14 to the
   changed set, or restate it as "introduces no new validator error relative to
   the merge base." Define "clean outcome" as `exit 0` — several documents in
   the changed set emit `::notice` lines that are not errors.

9. **Add a criterion for R13.** `git diff <merge-base>..HEAD -- crates/` is empty
   or touches comment lines only. Confirmed satisfiable: `crates/` has no
   fold-record coupling at all.

10. **Bound AC17's exception by line kind, not subject.** "Except where a
    comment names the removed checker" permits smuggling; "the diff over these
    files touches comment lines only" does not. Also pin the baseline ref so the
    byte-comparison is reproducible.

---

## Optional improvements

- **AC4**: drop `grep` from the forbidden-invocation list. `grep` is used at
  lines 90 and 120 for unrelated purposes and must stay; `git show` and
  `rev-parse` appear only in the fold step, so those two alone are a clean
  signal.

- **AC5**: state the stderr assertion explicitly (`unknown argument: --record`),
  since exit-non-zero already holds today.

- **AC12**: add "and the paragraph describing the consolidation judgment
  remains", so wholesale deletion cannot pass a criterion whose requirement
  forbids deletion.

- **AC6, AC11, AC17**: mark these as regression guards in the text. They pass
  today by design and that is correct; saying so stops a reviewer from reading
  their vacuity as a defect.

- **AC8**: "do not contradict each other" would be sharper as "both list exactly
  the deletion and mutation groups and no third group" — the two sites are short
  parallel enumerations, so this is mechanically checkable.

- Consider one criterion for `skills/scope/evals/evals.json`, whose lines 293
  and 304 narrate the append step in expected-output prose. AC2 catches it via
  the `skills/` clause today, but if AC2 is rewritten as a pathspec-exclusion
  command (change 2), make sure `evals.json` stays inside the search.
