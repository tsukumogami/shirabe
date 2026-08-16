# Clarity Verdict: PRD-fold-record-removal (pass 2)

## Verdict

FAIL

Three blocking findings. The rewrite is real work and it landed: nine of the ten
first-pass findings are fully resolved, the tenth is resolved as an ambiguity and
leaves only a coverage residue. The prose is better than the first draft — the
skip-guard sentence now resolves on its own, R10 enumerates instead of gesturing,
and the frontmatter reads as a success shape.

What fails is not carried over from pass 1. It is one factual premise the
document repeats four times and which the repository contradicts, one requirement
whose second binding either has no referent or points at text another requirement
exempts, and one requirement that prescribes the outcome of a judgment made at run
time against a document that does not exist yet.

The first of those is the serious one. **`docs/folds.md` holds a row.** It has held
one since commit 39b0981, for a fold that actually ran. The PRD says it never has,
in four places, and one Out of Scope bullet is discharged entirely by that claim.

## Disposition of first-pass findings

**1. "The four shipped documents" named nothing. RESOLVED.** R10 enumerates seven
paths, each with a status and a one-clause reason:

> 1. `docs/briefs/BRIEF-scope-artifact-persistence.md` (Done) — lists a durable
>    default-branch record as an in-scope item.
> ...
> 7. `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md` (Current) —
>    justifies its clean-cancel carve-out by the shape of the record's carve-out,
>    which R4 deletes.

I verified all seven statuses on disk: Done, Done, Current, Done, Current, Done,
Current — every one matches. The Problem Statement's counting sentence now says
"seven shipped documents of rationale," so the one candidate antecedent in the
document points at the right set. The set is also the right set: it includes the
two mandatory-steps documents I flagged in pass 1 as reachable by R10's
description but invisible to AC2, and the Decisions section says so out loud
("Seven documents are amended, not four").

**2. R10 didn't name the objection. RESOLVED.** R10a quotes it verbatim and the
quote checks out against `DESIGN-scope-consolidation-over-skipping.md:841-842`:

> — that absorbing a DESIGN into a PLAN "trades a durable audit trail for a
> shorter run and loses the record of why the work happened."

The two-halves split is faithful to the source. The design at :843-847 answers
with the record of *why* (in the code, a standing `/work-on` instruction) and the
record of *what happened* (`docs/folds.md`). R10a keeps the first, withdraws the
second, and requires the amendment to "name what replaces it and SHALL state
plainly where nothing does." AC16 mechanizes both halves. A verifier who did not
write this PRD can now run that check.

**3. Decisions vs Known Limitations on the roadmap cell. RESOLVED.** The two now
say the same thing. Decisions: the cell "keeps the folded-versus-never-started
distinction, which is the whole reason the cell fires, and drops only the
pointer." Known Limitations narrows the residual to "chains with no roadmap
feature entry — and even there the cascade eventually deletes the roadmap." The
reconciliation I asked for in pass 1 is written down, and the current text at
`run-cascade.sh:465` (`_none (chain folded; see docs/folds.md)_`) confirms that
dropping the pointer leaves the distinction intact.

**4. R15/R18 vs AC2. RESOLVED as an ambiguity; a coverage residue remains.** R18
now has one reading, and the two-criterion split is coherent: AC2 tests the path
with a named exclusion set, AC3 tests non-path references over the same
exclusions. I traced every current hit of both greps and each one is either
handled by a requirement or in the exclusion set — the pair is satisfiable, which
the pass-1 shape was not.

The residue is not an ambiguity, so I am not counting it here: AC3's pattern is
the literal `fold record|fold-record`, and the largest class of non-path
references in the repository does not use those words. See Rubric finding 8.

**5. R14/AC16 on validation scope. RESOLVED.** R16 is now "no new validator error
relative to the merge base," and I confirmed the number: `shirabe validate
--visibility=public docs/**/*.md` reports exactly 5 errors on this branch (three
BRIEF upstream-legality violations, one missing PLAN, one durable-BRIEF-names-PLAN
violation). AC20 states the bar as "no greater than the merge base's count of
five." R17 names both suites, `run-cascade_test.sh` included, and the Out of Scope
list carries the matching carve-out. This is fully closed.

**6. Frontmatter `goals` was a task list. RESOLVED.** It is a success shape now,
and a compressed one — four outcomes in one sentence, matching the four body
bullets without naming a file or a requirement number.

**7. The skip-guard sentence. RESOLVED.** Current text:

> the guard meant to skip an unrecoverable hash never skips: `git rev-parse` on an
> unresolvable `<rev>:<path>` prints the literal argument to stdout, so the
> emptiness test that guards the comparison always passes and a correct record is
> reported as a mismatch whenever the base branch has advanced.

I read this cold before opening the workflow and it resolved. Then I opened
`validate-docs.yml:145-149` and confirmed it is accurate: `want=$(git rev-parse
"$BASE:$doc" 2>/dev/null || true)` guarded by `[ -n "$want" ]`.

**8. "The column-blind row lookup." RESOLVED as written.** The phrase is gone and
Out of Scope names three defects with Problem Statement antecedents. But the same
*defect shape* recurs in R12 — see blocking finding 2.

**9. Frontmatter `problem` overclaimed. RESOLVED.** It now reads "Wherever the
survivor stays on disk it already carries the same fact under error-level
enforcement," which carries the restriction the body and Known Limitations apply.

**10. Seven carriers vs six. RESOLVED.** AC17 and Out of Scope now name the same
seven: survivor frontmatter alone, commit trailer, git notes, per-chain file,
forge metadata, rotation, per-fold file.

## Validator output

```
$ shirabe validate --format json --visibility=public docs/prds/PRD-fold-record-removal.md
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```

## Cold-read test

I read the Problem Statement with nothing else open, then went to the repository
to check it.

It reads well and it is actionable. The opening does the whole job in two
sentences — a fold deletes a document, and an absorbed document and a
never-written one look identical on disk while meaning opposite things — and the
squash-merge clause forecloses "just read the history." The three-count structure
delivers what it promises, and the abstraction/concreteness mix that worried me in
pass 1 is now coherent rather than mixed: `git rev-parse`, `merge=union`, and
`git diff --diff-filter=D` appear where a reader has to reproduce a mechanism to
believe the claim, and stay abstract where the property matters more than the
invocation ("a two-endpoint tree comparison, which cannot observe a file created
and deleted between those endpoints"). No sentence defeated me the way the
skip-guard sentence did last time.

Then I opened `docs/folds.md` and the cold read broke on a fact rather than a
sentence. The closing line — "a file that has never held a row" — is false. The
file's Record table carries one row, dated 2026-08-16, absorbing
`docs/briefs/BRIEF-scope-chain-mandatory-steps.md` into
`docs/prds/PRD-scope-chain-mandatory-steps.md`. It is committed, not a working-tree
artifact: `git log -- docs/folds.md` shows it landed in 39b0981, and `git show
HEAD:docs/folds.md` has it. The absorbed BRIEF is gone from disk. The survivor
carries the matching `absorbed:` list. A real fold ran.

Everything else in the Problem Statement survives contact with the repository. I
checked the seven document statuses, the five corpus errors, the rev-parse guard,
the `merge=union` line at `.gitattributes:10`, and the eval fixture. Only this one
claim fails, and it fails four times.

## Ambiguity findings

### R8 — "replaced ... rather than deleted"

**One reading, with a soft edge I am not blocking on.**

The four bullets name the *claim* each site makes rather than the site, which
kills the "rewrite in place vs preserve the function" split I hunted for, and AC11
through AC14 state what each replacement must achieve. The edge is the same one I
noted last time and it is still unaddressed: R8 says *every* prose claim citing the
record is replaced rather than deleted, and R7 requires deleting the
`.gitattributes` comment block, which cites the record (`.gitattributes:9` — "the
record checker flags it"). The reconciliation is that R8 covers claims *resting on*
the record as evidence, not prose *describing* a mechanism being removed. R7 is
specific and R8's list does not reach `.gitattributes`, so specific beats general
and no implementer will actually rewrite the comment block. Optional.

### R10a — what the amendment must say

**One reading. Passes.** The objection is quoted, the answer is split into a named
surviving half and a named withdrawn half, and the amendment is told to state
plainly where nothing replaces the withdrawn half. AC16 tests exactly those two
elements. This is the clearest requirement in the document.

### R11 — the `keep` obligation

**BLOCKING. Two readings that produce different behavior at the hop.**

> That design SHALL survive this chain: because it holds reasoning no downstream
> document carries, the consolidation judgment at the design-to-plan hop SHALL
> reach `keep`.

*Can a PRD legitimately require this?* Partly. The outcome — the removal rationale
stays readable in the working tree after the chain completes — is a legitimate
requirement, it is the whole point of the fourth user story, and AC17 verifies it
observably. The *verdict* is a different thing, and it is not the PRD's to set.

`phase-2-chain-orchestration.md:592-612` defines the judgment as reading both
bodies and asking whether the upstream holds anything beyond its contribution that
compression into a contribution section would lose, and closes with: "The verdict
is yours. There is no reviewer, no confirmation prompt, and no mode-conditional
gate on it at any hop, including the terminal one." R11 installs a documentary
gate on precisely that verdict.

The ground R11 offers is admissible — "holds reasoning no downstream document
carries" is the Stage 2 question, not the artifact-set reasoning that
`phase-2:734-745` prohibits, so R11 is not the forbidden keep-only guard. That is
what keeps this a clarity finding rather than a scope violation. But the two
readings are live and they diverge:

- *Override.* Return `keep` at that hop; do not let the content comparison reach
  another answer. The Decisions section endorses this reading explicitly — "R11's
  `keep` obligation is what stops this chain from folding the reasoning away."
- *Prediction.* Run the judgment honestly; it will reach `keep` because the ground
  holds.

An implementer under the first reading skips a judgment the mechanism requires. An
implementer under the second runs it, and if it lands on `absorb`, the PRD gives no
answer about whether R11 has been violated. There is a further problem with the
override reading specifically: the PRD asserts as settled fact a property of a
DESIGN that does not exist yet and that this PRD is upstream of. Whether that
DESIGN's reasoning would survive compression into a PLAN's contribution section is
answerable only once both bodies exist.

The fix is small. Bind the outcome and demote the verdict to the expectation it
is.

### R12 — "wherever it appears"

**BLOCKING on the second binding.**

> References to the record that do not spell its path SHALL be corrected, not left
> standing. This binds at minimum the "three readers" model asserting the record
> checker as one of them, wherever it appears, and any prose describing a durable
> record column.

The first binding resolves, with work. I traced the model to three sites, in two
different wordings:

| Site | Wording |
|---|---|
| `.github/workflows/check-scope-scripts.yml:25-27` | "one owner and three readers ... and the record checker's fold signature (the trigger)" |
| `crates/shirabe-validate/src/formats.rs:177-181` | "three sites read it ... and the record checker's fold signature (the *trigger*)" |
| `skills/scope/scripts/check-citations.sh:47` | "the string has one owner even though three sites read it" |

Only the first uses the literal phrase R12 quotes. The qualifier ("asserting the
record checker as one of them") is doing real disambiguation work, and it earns
its place: it correctly excludes the unrelated three-readers model for `upstream:`
at `DESIGN-chain-cardinality.md:51`, `:246`, `:293` and `upstream.rs:4`, which a
lexical search finds first. An implementer who reads the qualifier gets this right.

The second binding does not resolve. "Any prose describing a durable record
column" has one candidate in the corpus:
`DESIGN-scope-artifact-persistence.md:622` — "from scratch state that cleanup
deletes into columns of a durable file on..." That document is item 3 of R10's
seven, and R18 exempts it by name:

> Body prose inside the seven amended documents is deliberately exempt: R10
> preserves those bodies unedited and records the change in an appended section,
> so the historical text stays as written.

So either R12's second binding points at text R18 forbids touching — a direct
contradiction between two requirements — or it points at something I could not
find, in which case it is the same defect as pass 1's "column-blind row lookup":
a definite description naming a thing the document never describes and the
repository does not obviously contain. I searched `docs/`, `skills/`, `crates/`,
and the workflows for "column" and "durable record"; nothing else is a candidate.

### R18 — the exemption's boundary

**One reading. Passes.** "Body prose inside the seven amended documents" is a
clean line: seven enumerated documents, bodies exempt, appended amendment sections
are not bodies and are where the change gets recorded. AC15 tests the amendment
heading and AC2 excludes exactly those seven plus this chain's own three. The
boundary is drawn where R10 needs it drawn, and the reason is stated rather than
assumed. My only note is that R18's scope words ("any executable or adopter-facing
surface") are narrower than what AC2 and AC3 actually test, which is the whole
tree minus the exclusions — an over-delivering verification, which is the safe
direction. The unsafe direction shows up in Rubric finding 8.

## Rubric findings

**1. Cold-read test. FAIL on one premise, PASS on everything else.** Detailed
above. The Problem Statement stands alone, names who is hurt and what is broken,
and needs neither the BRIEF nor the exploration. Its closing sentence is false.

**2. Abstraction vs vagueness. PASS.** The mix is coherent now, and the rule it
follows is legible: name the mechanism where a reader must reproduce it to believe
the claim, state the property where the property is the point. `git rev-parse`,
`merge=union` and `git diff --diff-filter=D` are all in the first category and all
now appear. Every sentence I tested resolved without leaving the document, which
was not true in pass 1.

**3. Ambiguity hunt. FAIL.** R8 acceptable with a soft edge; R10a clean; R11
blocking; R12 blocking on its second binding; R18 clean. R1-R7, R9, R10, R13-R17
each have one reading. R13's "rewritten rather than scrubbed" is worth a mention as
a near-miss that lands: "scrubbed" could mean either deletion or redaction, but the
second clause ("after the change it SHALL specify the absorb procedure as it then
exists") settles it, and AC21 tests both halves.

**4. Goals are outcomes. PASS, frontmatter and body.** The frontmatter fix took.
All four body bullets name a state of the world rather than a task, and none names
a file or a requirement. The third is still the best sentence in the document.

**5. User Stories. PASS.** Four roles, four situations, four "so that" clauses that
name a consequence rather than restating the want. Stories two and four share the
noun "contributor" and nothing else — one is following a dead citation, one is
auditing the corpus and about to re-propose the mechanism. Each maps to a
requirement (R8/R12 and R11 respectively). No generic "user."

**6. Citation vs Restatement. PASS.** Better than pass 1. The Problem Statement is
the PRD's own — it reorganizes the BRIEF's three counts, drops "it was never argued
for" into `motivating_context` where it belongs, and adds the duplicate-detection
point and the seven-document count the BRIEF does not have. Out of Scope has been
rewritten out of the BRIEF's phrasing: the consolidation-judgment entry now reads
"at which hops" where the BRIEF said "when it folds," and three entries in the PRD
list (the check defects, the pre-existing corpus errors, auditing adopters) have no
BRIEF counterpart at all. The survivor-side-trace boundary disagreement I flagged
last time is still there in substance — the BRIEF puts it OUT, the PRD binds it as
R14 — but the PRD's handling is the better one and R14 states the relationship
("the carrier this removal relies on"), so a reader is not left guessing.

**7. Writing style. PASS.** Validator clean, so the mechanical rules are enforced
and I did not re-scan them. Independently: no workspace-banned word ("robust",
"leverage", "comprehensive/holistic", "facilitate") appears. One "tier" hit, in
AC6's "in either search tier" — exempt under the repo's Prose Vocabulary
declaration. Em dashes are 22 across 3,221 words, 6.8 per thousand against a
threshold of 10. No "It's worth noting", "Moreover", "Furthermore",
"Additionally", "In order to", "serves as", "stands as", "boasts".

Burstiness is genuine: "It fails on three counts." next to a 40-word sentence,
"The record has never held one." closing an Out of Scope bullet on five words —
though that particular short sentence is one of the four false ones. Two
preferences, unchanged from pass 1 and still not violations: the document has zero
true contractions (every apostrophe is possessive), and the Decisions entries hold
a uniform rhythm the rest of the document avoids.

**8. Internal consistency. FAIL.** Two findings beyond the blocking ones.

*R12 and R18 assert a scope the criteria cannot discharge.* AC3's pattern is the
literal `fold record|fold-record`. The three sites R12 names use "the record
checker" and match neither AC2 nor AC3. I verified this directly: `git grep -in
'fold record\|fold-record'` does not return `check-scope-scripts.yml`,
`formats.rs`, or `check-citations.sh:47`. After this change lands as specified, a
live CI workflow at `check-scope-scripts.yml:25-27` still tells a reader the
document-path shape has three readers, one of which is a checker that no longer
exists — a dangling reference in an executable surface, which is exactly what R18
forbids, passing every acceptance criterion. This is coverage rather than
ambiguity, so it belongs to completeness as much as to me, but the shape is the one
pass 1 blocked on and it should not ship a second time.

*AC20 is slightly stricter than R16.* R16 forbids adding errors; AC20's first
clause demands exit 0 over the changed document set. Those diverge only if a
changed document already carries a pre-existing error. None of the seven does — the
five errors are all in unrelated BRIEFs — so this is inert today. Worth one clause
to keep it inert.

On the growth argument: **confirmed absent.** The only size or growth vocabulary in
the document is inside the disclaiming decision itself ("Growth is not a reason",
"Any argument from file size is unsupported and is deliberately absent"). No
requirement, goal, story, criterion, or Problem Statement clause argues from row
count, file size, or context cost. The Problem Statement's cost paragraph rests
entirely on contention, redundancy, and broken verification. The document keeps its
promise.

**9. No emojis. PASS.** Codepoint scan across the emoji, dingbat, and
variation-selector ranges returns zero hits.

## A premise worth re-checking (not blocking)

The Problem Statement says a surviving document "declares what it absorbed in
frontmatter, names it in a pinned status line, and carries its content in a
contribution section — all three enforced at error level," and R14 restates it.

On the corpus's only real absorbed survivor, two of the three hold and the third
does not. `docs/prds/PRD-scope-chain-mandatory-steps.md` carries the `absorbed:`
list and the `## Absorbed Brief` contribution section, but its `## Status` section
has no pinned absorption line — it says "Requirements written from the brief this
document absorbed" in ordinary prose. The pinned shape lives at
`checks.rs:352-360` and clause 5 at `checks.rs:469-490` is an unconditional error,
yet `shirabe validate --visibility=public` on that file reports clean. I did not
chase down why.

This cuts both ways and is worth the author's attention rather than mine: the fold
is strong evidence for the PRD's redundancy argument, since the frontmatter and the
contribution section did carry the fact forward on their own. But one third of the
carrier the removal relies on was not present or not enforced on the one occasion
it mattered, and R14 says that carrier "SHALL NOT be weakened."

## Required changes

1. **[BLOCKING]** Correct the "never held a row" premise everywhere it appears.
   `docs/folds.md` carries one committed row (`git show HEAD:docs/folds.md`,
   landed in 39b0981) recording
   `docs/briefs/BRIEF-scope-chain-mandatory-steps.md` absorbed into
   `docs/prds/PRD-scope-chain-mandatory-steps.md`. Four statements are false as
   written:
   - frontmatter `motivating_context`: "has never held a row"
   - Problem Statement: "all maintaining a file that has never held a row"
   - Out of Scope: "**Migrating existing rows.** The record has never held one."
   - Known Limitations: "The removal is specified against a mechanism that has
     never executed. No fold has ever run..."

   The Out of Scope bullet is the one that changes work rather than wording: it
   dismisses migration on a premise that does not hold, and AC1 deletes the file
   with the row in it. Give the row a disposition. The good news is that the
   correction strengthens the document — the survivor carries the fact in
   frontmatter and in `## Absorbed Brief`, on disk, in an amended document, which
   is the PRD's central argument demonstrated once in the corpus rather than
   asserted. Say that instead.

2. **[BLOCKING]** Fix R12's second binding. Either name the site that carries the
   "durable record column" prose, or drop the clause. If the site meant is
   `DESIGN-scope-artifact-persistence.md:622`, R12 and R18 contradict each other —
   R18 exempts that document's body from correction — and one of them has to give.

3. **[BLOCKING]** Split R11 into the outcome and the expectation. Require what the
   PRD owns (the removal rationale remains readable in the working tree after this
   chain completes, which AC17 already verifies) and state the design-to-plan
   verdict as the expected consequence of the ground rather than as a SHALL. As
   written, R11 installs a gate on a verdict `phase-2-chain-orchestration.md:610`
   says has none, and pre-decides a content question about a document that does not
   exist yet. Reword rather than delete; the substance is right and the ground R11
   gives is the one Stage 2 admits.

4. Widen AC3 to reach the wording R12 actually binds. `fold record|fold-record`
   does not match "the record checker" at `check-scope-scripts.yml:25-27`,
   `formats.rs:177-181`, or `check-citations.sh:47`. Adding `record checker` to the
   alternation closes the gap and makes R18's claim discharged rather than
   asserted. Without it, a CI workflow keeps naming a checker this change deletes,
   and every criterion passes.

## Optional improvements

- Add one clause to R8 distinguishing a claim that rests on the record's existence
  from prose describing a mechanism being removed, so "every ... rather than
  deleted" cannot be read against R7's deletion of the `.gitattributes` comment
  block.
- Reconcile AC20's exit-0 clause with R16's "adds none," so the two cannot diverge
  if a changed document ever carries a pre-existing error.
- Re-check the "all three enforced at error level" premise against
  `PRD-scope-chain-mandatory-steps.md`, which lacks the pinned status line and
  validates clean. See the section above.
- Note in R14 or Known Limitations that the one executed fold is itself the
  evidence for the survivor-side carrier, now that the document can no longer say
  no fold has run.
- Let a few real contractions into the Problem Statement and Decisions prose, and
  break the uniform sentence rhythm in Decisions and Trade-offs.
