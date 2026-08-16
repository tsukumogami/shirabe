# Third-Pass Verdict: PRD-fold-record-removal

## Verdict

**FAIL** — 4 blocking findings.

The thirteen pass-2 findings are all addressed; twelve are fully resolved and
one (the R11 split) is partial. The remaining blocking items are: two surfaces
that still encode the `keep` obligation R11 was revised to disclaim, one AC that
cannot verify the positive half of the requirement it serves, and one stale
step-number cross-reference that no criterion reaches. All four are small,
localized text fixes.

## Disposition of the 13 pass-2 findings

### Completeness

**1. R12 unfalsifiable — no criterion reached its four motivating sites.
RESOLVED.**
AC22 now pins `crates/shirabe-validate/src/formats.rs`,
`.github/workflows/check-scope-scripts.yml`, and
`skills/scope/scripts/check-citations.sh` by path, requires each to describe the
absorbed-path readers without naming a record checker or fold signature, requires
the stated reader count to match, and separately requires `formats.rs`'s
`contribution_heading` doc comment to name no durable record column. R12's
binding list carries `check-scope-scripts.yml`. All four sites verified present
in the tree: `formats.rs:181` (`ABSORBED_ENTRY_PATTERN`, "the record checker's
fold signature"), `formats.rs:190-193` (`contribution_heading`, "a durable record
column"), `check-scope-scripts.yml:25-27` ("one owner and three readers"),
`check-citations.sh:46-47` ("three sites read it"). AC3's widened alternation
independently catches two of them.

**2. Three "the record" references survived every criterion. RESOLVED.**
- `phase-2-chain-orchestration.md:676-677` (step 9, "Commit the deletion, the
  re-point, the survivor's edits and the record together") — R2 now names "its
  final commit step"; AC8 now bars any step mentioning "a record committed
  alongside the deletion."
- `skills/scope/SKILL.md:573-576` ("The full nine-step procedure, its rollback
  table, the firing condition, the record, and the prohibition...") — R2's new
  final sentence binds the cross-reference's step count *and* its enumeration of
  parts; AC8 names the SKILL.md cross-reference explicitly.
- `skills/scope/evals/evals.json:293` tail ("commits the deletion, the splice,
  the survivor's edits and the record together") — AC21 now bars "a record
  committed alongside it" from any expected output or rubric criterion.

One residual wording note, non-blocking: AC8's bar is "a record committed
alongside the deletion", which reads onto step 9 cleanly but only loosely onto
the SKILL.md list-member "the record". R2's "enumerates its parts SHALL be
updated to match" closes it at the requirement level, so a competent implementer
drops it. Listed under Optional.

**3. Stale group count at `phase-3-exit-finalization.md:366`. RESOLVED.**
AC9 now requires "the sentence stating how many groups Phase 2's absorb adds
matches the number of groups listed." Verified: `phase-3:366` reads "Phase 2's
absorb adds three groups" over Deletions / Mutations / Append. `skills/scope/SKILL.md`
carries the same three groups (lines 834, 845, 855) but states no count, so AC9's
singular "the sentence" is exact rather than ambiguous.

### Clarity

**4. "Never held a row" false in four places. RESOLVED.**
Corrected in both documents. The BRIEF's post-acceptance diff (`764c62d..HEAD`)
fixes all three of its occurrences — `motivating_context`, the Problem Statement
closing paragraph, and the OUT bullet — and replaces the last with an affirmative
argument from the real fold. The PRD's Problem Statement now argues *from* `#316`
(lines 81-93) and its Out of Scope bullet reasons from the row's recoverability.
Every factual claim in the new argument checks out (see Empirical checks).

**5. R12's "durable record column" binding unnamed / possible R18 contradiction.
RESOLVED.** R12's first bullet names it as "the `contribution_heading` doc
comment naming a durable record column", and R12 closes with "These sites are
source and workflow rather than amended-document bodies, so R18's exemption does
not reach them." AC22's last sentence tests it. Consistent with R15 (comment
lines only) and AC19, which lists `formats.rs` as comment-only — the required
change *is* a comment change, so there is no conflict.

**6. R11 imposed a SHALL on a consolidation verdict the PRD does not own.
PARTIAL.** R11 itself is fixed: "This requirement states an outcome, not a
verdict. `/scope`'s consolidation judgment is made against two documents and this
PRD does not reach into it... if it instead finds the reasoning fully carried,
R11 is satisfied wherever the reasoning ends up readable." But two dependent
surfaces still assert the obligation R11 now disclaims — see Required changes 1
and 2.

**7. AC3's pattern missed the sites R12 binds. RESOLVED.**
AC3's alternation is now `fold record\|fold-record\|record checker\|fold
signature`. Run verbatim, it reaches `formats.rs:181`,
`check-scope-scripts.yml:27`, `.gitattributes:3,9`, `validate-docs.yml:102,106,149`,
`README.md:86`, `doc-validation.md:54,57`, `SKILL.md:544`,
`phase-2:827`, `check-citations.sh:56,114`, `check-citations_test.sh:126-127`, and
`docs/folds.md:1`.

### Testability

**8. Same as 7. RESOLVED.** See 1 and 7.

**9. AC19 false-failed a correct implementation. RESOLVED.**
AC19 now pins `checks.rs`, `formats.rs`, `absorption_corpus.rs`, and
`check-scope-scripts.yml` by path and states "the prose and eval surfaces that
AC8 and AC21 mandate changing are deliberately excluded." No overlap with a
mandated non-comment change remains: `checks.rs` and `absorption_corpus.rs` carry
no record reference at all (neither appears in any sweep), and the two files that
do carry one need comment-only edits.

**10. AC11 had no failing form. RESOLVED.**
AC11 is now a two-part mechanical test: the rule "does not cite the record" *and*
"names a concrete artifact or signal a reader consults, and states in the same
passage what a reader observes when even that is absent." Both halves are
checkable against `skills/execute/SKILL.md:596-600`.

**11. AC21's ordering guarantees unenumerated. RESOLVED.**
AC21 now names three: `git rm` precedes re-validation, re-validation precedes the
commit, and the deletion, splice and survivor's edits land in one commit. These
are exactly the surviving orderings in `evals.json:293` once the append clause is
removed.

**12. AC20's corpus invocation unpinned. RESOLVED, and empirically exact.**
AC20 states the command and the baseline. Ran it: 177 files, `errors: 5`,
`notices: 127`. The five are `BRIEF-fc06-index-alias.md` (R10),
`BRIEF-lifecycle-draft-ready-discipline.md` (R10),
`BRIEF-single-pr-plan-validation.md` (R6 and R11),
`BRIEF-skill-cascade-lifecycle-check.md` (R10) — none in a file this change
touches, so the baseline is stable under the change.

**13. R8's fourth bullet had no positive obligation. RESOLVED.**
The bullet now reads "which SHALL still state what the verdict ends with rather
than trailing off where the record used to be." The site is
`skills/scope/SKILL.md:543-544` ("the upstream is removed, every link to it
re-pointed, and the fold recorded."), and AC3 catches it because `fold record`
matches inside "fold recorded" — confirmed in the verbatim run.

## Independent inventory sweep

All four mandated sweeps were run at `HEAD` with `':!wip/'`. Every hit maps to a
requirement and a criterion.

### `git grep -n 'docs/folds\.md' HEAD -- ':!wip/'` (23 hits outside this chain's own docs)

| Site | Requirement | Criterion |
|---|---|---|
| `.gitattributes:10` | R7 | AC4 |
| `validate-docs.yml:104,137,138,147,157,158,160` | R5 | AC5 |
| `README.md:87` | R8 b3 | AC13 |
| `docs/guides/doc-validation.md:56` | R9 | AC14 |
| `skills/execute/SKILL.md:597` | R8 b1 | AC11 |
| `skills/execute/scripts/run-cascade.sh:465` | R8 b2 | AC12 (gap — see Required change 3) |
| `skills/scope/SKILL.md:857` | R3 | AC9 |
| `skills/scope/evals/evals.json:293,304` | R13 | AC21 |
| `phase-2-chain-orchestration.md:668` | R2 | AC8 |
| `phase-3-exit-finalization.md:375` | R3 | AC9 |
| `phase-4-cleanup.md:111` | R4 | AC10 |
| `check-citations.sh:56,69` | R6 | AC6 |
| `check-citations_test.sh:122` | R6 | AC7 |
| the seven R10 documents | R10 | AC15 |

### `git grep -in 'fold record\|fold-record\|record checker\|fold signature'`

Adds, beyond the above: `.gitattributes:3,9` (R7's "comment block justifying it",
AC4); `check-scope-scripts.yml:27` (R12, AC22); `formats.rs:181` (R12, AC22);
`docs/folds.md:1` (R1, AC1); `skills/scope/SKILL.md:544` (R8 b4, AC3);
`check-citations.sh:114` (R6, AC6/AC3); `check-citations_test.sh:126-127` (R6, AC7);
and **`phase-2-chain-orchestration.md:827`** — "`verdict:` ... and `stage:` ... —
both serialized into the durable fold record", in the state-file enum
re-validation section. This one is *not* named by R2 (it is outside the absorb
procedure) or by R12's binding list. It is reached by R18 and by R8's "at
minimum" phrasing, and mechanically by AC3, which fails until it is corrected.
Coverage is real but arrives only through the grep; naming it would be an
improvement (see Optional).

### `git grep -n 'merge=union' HEAD`

`.gitattributes:10` (R7/AC4), `docs/folds.md:51` (R1/AC1), and this chain's own
two documents. Fully covered.

### `git grep -n '\-\-record' HEAD -- ':!wip/'`

`check-citations.sh:52` (usage line), `:56` (flag description), `:75` (case arm).
All R6/AC6. The default assignment at `:69` and the record-shape assertion at
`:99-103` are the "default" and "path-shape assertion" R6 names; AC6 tests the
flag's removal and the pathspec's removal but not the assertion's — harmless,
since the assertion is dead code once the variable is gone.

### Stale spelled-out and numeric counts near fold/absorb prose

Swept `skills/scope/SKILL.md`, all `skills/scope/references/phases/*.md`,
`skills/execute/SKILL.md`, `state-schema.md`, `crates/`, `.github/`,
`docs/guides/`, and `README.md` for `one|two|...|ten` and `[0-9]` before
step/group/reader/site/write/target/row/part/member.

Covered: `phase-2:616` "Nine steps." (AC8); `SKILL.md:573` "nine-step procedure"
(R2/AC8); `phase-3:366` "three groups" (AC9); `formats.rs:176` "three sites read
it", `check-scope-scripts.yml:25` "one owner and three readers",
`check-citations.sh:47` "three sites read it" (all R12/AC22).

Not affected (verified by reading context, not assumed): `phase-2:41` "eight steps
in sequence" and `:73` "The eight-step ordering" are the per-child invocation
loop, not the absorb procedure; `state-schema.md:198` "the eight Phase 2 steps" is
the same loop; `phase-2:490` and `:761` "Step 8" refer to that loop's step 8 (the
consolidation judgment), not the absorb list; `SKILL.md:849` "four writes" counts
the survivor's writes, which R14 freezes; `phase-2:634` "three things" is the
carry check; `phase-1:100` "Four things change" is unrelated.

**Not covered:** `phase-2-chain-orchestration.md:700-702` — "If a resume finds a
chain interrupted **between steps 5 and 9**, un-append the row, restore the
survivor, delete nothing, and leave the hop at `keep`." The "un-append the row"
half is caught by AC8's "no ... paragraph ... mentions an ... un-append". The
step-range half is caught by nothing: AC8 asserts contiguity of the list and step
numbers in the rollback table, and this is a third carrier of step numbers. After
step 6 is removed the range becomes 5-8, and an implementer who minimally edits
the sentence to drop "un-append the row" passes every criterion while leaving a
range that no longer exists. Same defect class as pass-2 findings 2 and 3. See
Required change 4.

## Empirical checks

### The `#316` fold claims

Every claim the Problem Statement now rests on is true.

- **The row exists.** `docs/folds.md:64` — `| 2026-08-16 |
  docs/briefs/BRIEF-scope-chain-mandatory-steps.md |
  docs/prds/PRD-scope-chain-mandatory-steps.md | absorb | problem-statement=true
  user-outcome=true user-journeys=true scope-boundary=true |
  6f96746e956c2286409f7d5b71ca23a153a5d564 |`. Exactly one row.
- **The survivor carries `absorbed:`.** `PRD-scope-chain-mandatory-steps.md:4-5`.
- **It carries the pinned `## Status` line.** Line 38: `Absorbed
  [BRIEF-scope-chain-mandatory-steps](docs/briefs/BRIEF-scope-chain-mandatory-steps.md);
  carried in Absorbed Brief.`
- **It carries `## Absorbed Brief`.** Line 40, immediately after `## Status`
  (line 30).
- **The absorbed BRIEF did not exist at `39b0981^`.** `git cat-file -e` fails at
  both `39b0981^` and `39b0981`. `git log --all` shows the path created at
  `abea9e3` and deleted at `fda9a04`, both inside the squashed chain — so it
  appears in neither endpoint of `git diff --diff-filter=D "$BASE...$HEAD"`, and
  the check's `DELETED` list is empty. The PRD's claim that the check "exited
  without asserting anything" is exactly right.

Two supporting checks: `git ls-files` puts nothing else in the record, and the
`.gitattributes:3-9` comment block the PRD describes is present as described
(seven lines, ending "and the record checker flags it").

One soft claim worth noting without objection: Out of Scope says the pre-fold
blob hash "fingerprints bytes no plain clone can reach now that the branch is
gone." In *this* worktree the blob is still reachable (`git cat-file -t` returns
`blob`) because the feature-branch objects survive locally. The claim is about a
plain clone of the default branch, where it holds. No change needed.

### AC2, AC3, AC20 run verbatim

- **AC2** parses and runs. Exit 0, 23 hits. Its exclusion set hides nothing real:
  every excluded path is either an R10 amended document (whose body prose R18
  deliberately exempts), `wip/`, or one of this chain's own three documents. It
  excludes nothing that should be caught — in particular it does not exclude
  `skills/`, `crates/`, `.github/`, or `docs/guides/`.
- **AC3** parses and runs with the same exclusion set. Exit 0, 18 hits across 12
  files. The alternation reaches every R12 site and, via substring matching on
  "fold recorded", the R8 bullet-4 site at `SKILL.md:544`. No over-exclusion.
  Cosmetic only: in the rendered PRD the pattern wraps mid-token (`fold` /
  `signature` on separate lines); a reader reconstructs it, but joining it would
  help a copy-paste.
- **AC20** runs. `errors: 5`, `notices: 127` — the stated baseline is exact.
  `git ls-files 'docs/*.md' 'docs/**/*.md'` yields 177 paths; git's fnmatch makes
  the second pattern redundant and dedupes, so the two-pattern form is harmless.
  The two documents under review validate clean on their own (`outcome: clean`,
  0 errors, 0 notices).

### Validator and writing style

`shirabe validate --format json --visibility=public docs/prds/PRD-fold-record-removal.md
docs/briefs/BRIEF-fold-record-removal.md` → `outcome: clean`, 0 errors, 0
notices, exit 0.

Banned-word sweep (`robust`, `leverage`, `comprehensive`, `holistic`,
`facilitate`, `tier/tiered`, plus the usual AI tells): BRIEF 0 hits. PRD 1 hit —
"search tier" in AC6, which names the script's own `Tier 1` / `Tier 2` constructs
at `check-citations.sh:108,136`. `tier` is exempt in this repo and this is a
proper name besides. No violation.

Prose reads cleanly in both documents: contractions present, sentence length
varies, no preamble hedging, no bullet-heavy substitution for argument.

### BRIEF coherence after the post-acceptance edit

The diff `764c62d..HEAD` touches three places and is internally consistent: the
`motivating_context` premise, the Problem Statement's closing paragraph, and the
OUT bullet on migration. The replacement paragraph makes the same argument the
PRD's Problem Statement makes, in the same order, without duplicating its
wording. Nothing else in the BRIEF depends on the retracted premise — the three
counts in the Problem Statement, the four User Journeys, and the Scope Boundary
all argue from redundancy, contention, and the check's trigger, none of which
turned on the record being empty. The BRIEF validates clean.

Two BRIEF-to-PRD widenings, both legitimate and neither a defect: the BRIEF scopes
"the four shipped documents" and the PRD amends seven, which the PRD's Decisions
section explains at length; and the BRIEF names "the two prose claims" where R8
binds four sites, which the BRIEF's own Status hands to the PRD ("The downstream
PRD owns the requirements — which files change..."). R8's "at minimum" phrasing
makes the PRD's ownership explicit.

## R -> AC coverage map

| Req | Criteria | Adequate? |
|---|---|---|
| R1 remove `docs/folds.md` | AC1, AC2 | Yes |
| R2 absorb procedure carries no record | AC8 | Yes for the list, count, table, commit step, cross-reference; **gap** on the resume paragraph's step range |
| R3 no append group in the write-target set | AC9 | Yes — both enumerating sites named |
| R4 no cleanup carve-out | AC10 | Yes |
| R5 workflow step removed, not reduced | AC5 | Yes — the step name *and* the `git show`/`grep`/`rev-parse` invocations |
| R6 preflight carries no record affordance | AC6, AC7 | Yes |
| R7 `merge=union` and its comment block removed | AC4 | Yes |
| R8 b1 `/execute` distinguishing rule | AC11 | Yes — two-part, both halves |
| R8 b2 roadmap downstream cell | AC12 | **No** — tests deletion only, not the replacement |
| R8 b3 README consolidation description | AC13 | Yes |
| R8 b4 absorb-verdict clause | AC3 | Deletion half yes; positive half untested, but the residual text satisfies it |
| R9 adopter docs describe no check | AC14 | Yes |
| R10 seven amendments, statuses retained | AC15 | Yes — heading shape, date floor, `folds.md` string, status equality |
| R10a consolidation amendment names both halves | AC16 | Yes |
| R11 rationale readable in the working tree | AC17 | **No** — pins a path R11 says may move |
| R12 non-path references corrected | AC22, AC3 | Yes — all four sites, plus reader counts |
| R13 eval fixture rewritten, not scrubbed | AC21 | Yes — negative and positive halves |
| R14 survivor trace unchanged | AC19 | Yes |
| R15 no compiled behavior change | AC18 | Yes |
| R16 no new validator error | AC20 | Yes — command and baseline pinned |
| R17 test suites pass | AC7, AC12 | Yes — both named suites |
| R18 no dangling reference | AC2, AC3 | Yes |

Every requirement has at least one criterion. Every criterion traces to a
requirement. AC1-AC22 are all reachable and all fail today, as they should
pre-change.

## Rubric findings

**Completeness.** The inventory is now closed: every site any of the four sweeps
reaches has a requirement and a criterion, with the two exceptions noted (the
resume paragraph's step range, and `phase-2:827` reached only through AC3). The
seven amended documents are correctly identified — all seven statuses verified,
both existing `## Amendment — 2026-08-15` headings verified, and each document's
stated offending content verified in place. The Known Limitations section
concedes the right residual and does not overclaim.

**Clarity.** The Problem Statement's three-count structure is well built and now
rests on verified facts. The two R11-dependent surfaces are the only remaining
place the document argues against itself. Out of Scope is unusually good — each
bullet gives a reason rather than a boundary. "Growth is not a reason" earns its
place by pre-empting the argument a reader would expect.

**Testability.** AC2, AC3 and AC20 execute as written and produce the stated
results. AC15's date floor discriminates correctly against the two pre-existing
2026-08-15 amendments, since the change lands on or after 2026-08-16. AC19 and
AC22 no longer conflict — the required `formats.rs` and `check-scope-scripts.yml`
edits are comment-only, which is what AC19 permits. The remaining testability
gaps are AC12 and AC17.

One structural check worth recording as clean: removing the fold-record step from
`validate-docs.yml` does not orphan `fetch-depth: 0`, because the changed-file
step at line 88 still runs `git diff --name-only --diff-filter=ACMR`. R5's
"remove rather than reduce" is safe as specified.

## Required changes

1. **Drop the `keep` obligation from Decisions and Trade-offs.** PRD lines
   418-419 read "a PRD reaches Done and stops being consulted, and R11's `keep`
   obligation is what stops this chain from folding the reasoning away." R11
   lines 216-218 say the opposite: "This requirement states an outcome, not a
   verdict. `/scope`'s consolidation judgment is made against two documents and
   this PRD does not reach into it." Rewrite the Decisions sentence to the
   expected-consequence framing R11 now uses — e.g. "...and the expectation is
   that the design-to-plan hop reaches `keep` on its own terms, because the
   carrier reasoning is content the PLAN does not carry."

2. **Make AC17 satisfiable under the branch R11 permits.** AC17 requires
   `docs/designs/current/DESIGN-fold-record-removal.md` to exist, but R11's last
   sentence says "if it instead finds the reasoning fully carried, R11 is
   satisfied wherever the reasoning ends up readable." Under an `absorb` verdict
   at the design-to-plan hop, a correct implementation fails AC17. Restate it
   against the carrier rather than the path: "The document carrying the removal
   rationale — `docs/designs/current/DESIGN-fold-record-removal.md`, or the
   surviving document that absorbed it — exists in the working tree and names,
   each with a reason for rejection: ..."

3. **Give AC12 the positive half of R8.** AC12 currently reads "the roadmap
   downstream cell the script emits contains no pointer to the record," which a
   bare `_none_` satisfies while dropping the folded-versus-never-started
   distinction the Decisions section calls "the whole reason the cell fires."
   Add the replacement test: "...and still distinguishes a chain that folded from
   one that never ran." (This is the mildest of the four, but it is the only
   criterion covering `run-cascade.sh:465` and R8 explicitly forbids deleting
   rather than replacing.)

4. **Reach the resume paragraph's step range.** `phase-2-chain-orchestration.md:700-702`
   carries step numbers ("between steps 5 and 9") in a third place that neither
   R2's enumeration nor AC8's numbering assertions reach; after step 6 is removed
   the range is 5-8. Either add the paragraph to R2's list of parts to rewrite,
   or extend AC8's numbering clause — e.g. "...and every prose reference to a
   step number inside the Consolidation Judgment section, including the
   partial-absorb resume paragraph, matches the renumbered list."

## Optional improvements

- **Name `phase-2-chain-orchestration.md:827` in R8 or R12.** The clause
  "`verdict:` ... and `stage:` ... — both serialized into the durable fold
  record" is a substantive prose claim, not a name-swap: once the record is gone,
  the stated reason for validating those two enums changes. AC3 forces the fix,
  but an implementer working requirement-first will meet it only when they run
  the grep.
- **Tighten AC8's bar for the SKILL.md cross-reference.** "a record committed
  alongside the deletion" reads cleanly onto step 9 but only loosely onto "the
  record" as an enumerated member of the cross-reference list at
  `SKILL.md:573-576`. Adding "or lists the record among the procedure's parts"
  would close the reading.
- **Unwrap AC3's pattern.** It breaks mid-token across the line break (`fold` /
  `signature`), so it cannot be copy-pasted as rendered.
- **AC6 says "unknown-option error"; the script says "unknown argument".** Match
  the wording so the criterion can be checked against literal output.
- **AC6 could also assert the record-shape guard is gone** (`check-citations.sh:99-103`),
  which R6 names as "a path-shape assertion" but no criterion tests.
- **Consider a one-line note in the BRIEF** pointing out that the PRD widened
  four amended documents to seven and two prose claims to four. Both widenings
  are legitimate and the PRD explains the first; a reader arriving at the BRIEF
  first has no signal that the counts moved.
