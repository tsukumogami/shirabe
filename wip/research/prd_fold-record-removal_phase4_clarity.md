# Clarity Verdict: PRD-fold-record-removal

## Verdict

FAIL

Six blocking findings. The prose is unusually good — no banned words, no AI
tells, real burstiness, and the deliberate abstraction ("the hosting forge",
"a two-endpoint tree comparison") mostly resolves inside the document via the
acceptance criteria. What fails is precision at the points where the document
tells an implementer what to build: a definite reference to "the four shipped
documents" that names no documents and matches at least six candidates, a
Decisions entry that contradicts a Known Limitation about the same sentence of
output, an amendment requirement written against an objection the PRD never
states, and two requirement/criterion pairs that disagree on scope.

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

I read the Problem Statement first, with only the repo in front of me.

What landed cleanly. The opening two sentences do the whole job: a fold deletes
a document, and an absorbed document and a never-written document look
identical on disk while meaning opposite things. The squash-merge clause
explains why history is not the fallback. That is a problem I can hold in my
head without any backstory. The three-count structure is honest signposting and
each count delivers what it promises. "One append-only row per fold, in one
file, in every repository that runs `/scope`" is a complete description of the
mechanism in seventeen words, and I did not need to open `docs/folds.md` to
follow the argument against it.

The abstraction policy mostly works. "The hosting forge" is unambiguous in
context — there is exactly one thing that resolves merges without consulting a
repository's merge drivers, and AC3 names `.gitattributes` and `merge=union` so
the mechanism is pinned before the document ends. "A two-endpoint tree
comparison, which cannot observe a file created and deleted between those
endpoints" is a better sentence than `git diff BASE...HEAD` would have been: it
states the property that matters rather than the invocation. AC4 pins it. Same
for the citation preflight and AC5. I went in expecting to fail this document
on vagueness and it largely survived.

Where the cold read broke. One sentence defeated me: "a guard meant to skip an
unrecoverable hash never skips, because the underlying command emits its
unresolved argument on success-shaped output, so a correct record is reported as
a mismatch whenever the base branch has advanced." I had to open
`.github/workflows/validate-docs.yml:145-151` to learn that "the underlying
command" is `git rev-parse`, that "its unresolved argument" is `$BASE:$doc`,
and that "success-shaped output" means rev-parse echoes the unresolved revision
on stdout so the `[ -n "$want" ]` guard sees a non-empty value. Every noun in
that sentence is a definite reference to something the document never
introduced. Unlike the forge and the tree comparison, no acceptance criterion
pins it later, so there is nowhere for a reader to recover.

Second break, in Out of Scope: "the column-blind row lookup." The other three
defects in that list each have an antecedent in the Problem Statement — the
trigger that cannot fire, the dead skip-guard, the absent duplicate detection.
This one appears exactly once in the document, with a definite article, naming
a defect never described. It is `git show "$HEAD:docs/folds.md" | grep -F "$doc"
| head -1` greping the whole file instead of a column, which I confirmed at
`validate-docs.yml:147` — but only because I went looking.

Third, and this is the one that changed my verdict: the Problem Statement ends
with "four documents of rationale." Sixty lines later AC14 says "each of the
four shipped documents." I read the second as referring to the first. They are
not the same set. The rationale documents include `README.md` and
`docs/guides/doc-validation.md`, which R8 and R9 handle by replacement and
deletion rather than amendment. So the one place the document supplies a
plausible antecedent for AC14 supplies a wrong one.

## Ambiguity findings

### R8 — "replaced ... rather than deleted"

> **R8.** Every prose claim that cites the record as evidence SHALL be replaced
> with a claim that holds without it, rather than deleted. This binds at
> minimum: [three bullets]

**Verdict: acceptable, with one tension worth a sentence.**

The two readings I hunted for — "rewrite the sentence in place" versus
"preserve the claim's function somewhere" — collapse under the three bullets,
which name the claim each site makes rather than the site, and under AC10 and
AC12, which state what the replacement must achieve. "At minimum" leaves the set
open, but AC2's exclusion list (`skills/`, `.github/`, `crates/`, `README.md`,
`.gitattributes`) makes the full set mechanically discoverable by grep. An
implementer cannot miss a site.

The tension is with the merge-attribute decision, which says: "Removing it makes
the prose correction a deletion instead of a rewrite." R8 says *every* prose
claim citing the record gets replaced, never deleted; the decision endorses
deleting prose that cites the attribute. These are reconcilable — the attribute
is not the record, and prose describing a removed mechanism is not a claim
resting on the record's existence — but the PRD never draws that line, and the
word "every" invites an implementer to rewrite `.gitattributes:4-9` instead of
deleting it, which R7 requires deleted. One clause naming the discriminator
closes this. Non-blocking.

### R10 — what the amendment must affirmatively say

> **R10.** The shipped documents whose requirements and decisions the record
> discharges SHALL each carry a dated amendment recording what no longer holds.
> The amendment to the consolidation design SHALL state what now answers the
> objection that its design decision was rescued from...

**Verdict: BLOCKING, on two independent counts.**

*Count one — the set is not determined.* R10 identifies its targets by
description. AC14 counts them ("each of the four shipped documents") without
naming them. Nothing in the PRD enumerates the set. I applied R10's description
to the corpus and got at least six matches:

| Document | Why it matches R10's description |
|---|---|
| `docs/prds/PRD-scope-artifact-persistence.md` | R20 is the requirement the record discharges |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md` | chose the surface; four citations |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | cites the record at :846 |
| `docs/prds/PRD-scope-consolidation-over-skipping.md` | cites `docs/folds.md` at :414 |
| `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md` | :313 and :719 build on the record's carve-out |
| `docs/prds/PRD-scope-chain-mandatory-steps.md` | :784 requires "the fold record stay as shipped" |

The upstream BRIEF does not disambiguate: its References section lists three
documents plus a skill phase file, which is a fourth item but not a shipped
document. Two competent implementers will amend different sets, and the last two
rows are exactly the ones a reasonable person drops, because they carry no
literal `docs/folds.md` string and therefore pass AC2 either way. The count
must become an enumeration.

*Count two — the objection is never named.* R10's second sentence and AC14's
second half both turn on "the objection that its design decision was rescued
from." The PRD never states what that objection was. Out of Scope gets closest —
"Re-deciding whether a design may be absorbed into a plan" — which tells me the
*decision* but not the *objection*. AC14 requires a verifier to confirm "an
affirmative statement of what now answers the objection, not only that the prior
answer is withdrawn." A developer who did not write this PRD cannot run that
check; they have to reconstruct the objection from
`DESIGN-scope-consolidation-over-skipping.md:846` first. Naming the objection in
one clause makes both R10 and AC14 self-contained.

### R13 — "no compiled behavior SHALL change"

> **R13.** No compiled behavior SHALL change. The removal touches prose,
> workflow configuration, a shell script and its test, and repository metadata;
> any source change SHALL be limited to comments that describe the removed
> mechanism.

**Verdict: unambiguous. Passes.**

The two readings I tested — "the binary's behavior does not change" and "no
compiled source is touched at all" — are separated by the second sentence, which
explicitly permits comment-only source edits. "Compiled" cleanly excludes the
shell script, whose behavior does change under R6 and AC5, and the enumeration
of touched surfaces makes that exclusion deliberate rather than accidental. I
checked the premise: `crates/` contains no `docs/folds.md` string, and the one
comment in scope is `crates/shirabe-validate/src/formats.rs:180-181`, which
names "the record checker's fold signature" as one of three readers of
`ABSORBED_ENTRY_PATTERN`. AC17's exception clause covers exactly that edit. The
requirement is well-formed.

One consequence worth noting rather than fixing: R13 has no acceptance criterion
of its own. AC17 reaches the comment but not the general claim, so nothing
verifies that `crates/` changed only in comments. That is a coverage question
for the completeness reviewer, not an ambiguity.

### R15 — "no dangling reference"

> **R15.** No dangling reference to the record SHALL remain. A search of the
> committed tree for the record's path SHALL return no hit outside the amendment
> sections that describe its removal.

**Verdict: BLOCKING. The two sentences state different requirements.**

Sentence one forbids dangling *references to the record*. Sentence two narrows
the test to *the record's path*. AC2 mechanizes sentence two only ("A search of
the committed tree for `docs/folds.md`"). The gap is not theoretical — these
references satisfy AC2 while violating sentence one:

- `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:313` — "is carved
  out explicitly, in the shape the fold record's carve-out already uses"
- `docs/designs/current/DESIGN-scope-chain-mandatory-steps.md:719` — "the fold
  record's already uses, because the enumerated set and the Phase 4 sweep"
- `docs/prds/PRD-scope-chain-mandatory-steps.md:784` — "the preflight, the carry
  check, and the fold record stay as shipped"

All three point at a carve-out R4 deletes and a mechanism R1 removes. None
contains the string `docs/folds.md`. One implementer reads R15's first sentence
and fixes them; another reads the second sentence, runs AC2, gets a clean
result, and ships three dangling references. Either narrow sentence one to the
path, or widen the search AC2 specifies and extend R10's amendment set to cover
these documents — which is the same fix as R10 count one.

### R14 vs AC16 — corpus or changed set

> **R14.** The repository's own validation SHALL pass after the change: the
> document validator over the corpus, and the scope-scripts test suite.
>
> - [ ] **AC16.** `shirabe validate` reports a clean outcome over the changed
>       document set.

**Verdict: BLOCKING.**

R14 says "over the corpus." AC16 says "over the changed document set." These are
different commands with different failure surfaces: amendments to six shipped
documents can break cross-document checks in documents this change does not
touch, and only the corpus run catches that. An implementer following AC16 does
less work than R14 requires and still ticks the box. Pick one.

A smaller mismatch rides along: R14 names "the scope-scripts test suite," but
AC11 requires `run-cascade_test.sh`, which lives under `skills/execute/scripts/`,
not `skills/scope/`. R14's enumeration does not reach the test AC11 depends on.

### Decisions vs Known Limitations — the roadmap downstream cell

**Verdict: BLOCKING. A decision and a limitation describe the same sentence of
output and disagree about what it says.**

Decisions and Trade-offs:

> **The roadmap's downstream cell says nothing about a record.** ... It states
> that the chain folded and stops there. The alternatives were to point at the
> surviving artifact — but in this case there is none, which is what makes the
> cell fire — or to say nothing at all, which loses the distinction between a
> chain that folded and a feature never started.

Known Limitations:

> R8's replacement claim narrows this but does not eliminate it: a reader gets
> "no downstream artifact" rather than "a chain ran and folded to nothing."

The decision picks a cell text that preserves the folded-versus-never-started
distinction, and explicitly rejects the alternative that loses it. The
limitation then asserts the reader gets the losing outcome. Both are about the
terminal-fold case — the decision says so ("in this case there is none, which is
what makes the cell fire") and the limitation says so ("a chain folds down to a
single surviving artifact and that artifact is later deleted"). For reference,
the current text is `**Downstream:** _none (chain folded; see docs/folds.md)_`
at `skills/execute/scripts/run-cascade.sh:465`, so the decision's replacement is
`_none (chain folded)_`, which does say a chain ran and folded.

There may be a reconciliation the PRD does not state — the ROADMAP carrying the
cell is itself deleted by the cascade once every feature on it is Done, so the
cell may not survive on the default branch. If that is the argument, it has to
be written down; as it stands, a reader cannot tell whether AC11 should produce
a cell that says "chain folded" or one that says only "none."

### Frontmatter `goals` vs the Goals section

**Verdict: BLOCKING under rubric 4 and rubric 8.**

Frontmatter:

> Remove the record and every mechanism that exists only to serve it, replace
> the prose claims that cite it as evidence with claims that hold without it,
> and amend the shipped documents whose requirements and decisions it
> discharges...

That is R1, R7, R8 and R10 in a sentence — the work, not the success shape. The
format reference asks for "what success looks like at a high level." The body
Goals section gets this exactly right: four bullets, every one an outcome a
reader could evaluate the change against ("parallel chains do not contend,
rebase, or fail validation because a sibling folded first"; "a repository
adopting the shared validation workflow is only asked to satisfy checks it has
the means to satisfy"). The frontmatter and the section are not in conflict on
substance, but they are in different registers, and the frontmatter is the half
that gets read by anyone triaging relevance. The final clause about the
survivor-side trace is a scope boundary (R12) rather than a goal at all.

### Frontmatter `problem` vs the Problem Statement

**Verdict: non-blocking, but it over-claims.**

Frontmatter states flatly: "The surviving document already carries the same
fact under error-level enforcement." The body qualifies it: "For every fold
whose survivor stays on disk, that is false" — that is, the redundancy holds for
every fold *except* the terminal-fold case. Known Limitations then makes the
exception explicit: "One fold shape loses its only carrier." A reader who reads
only the frontmatter concludes the record is fully redundant, which the document
twice denies. Six words fix it.

## Rubric findings

**1. Problem Statement stands alone. PASS.** I verified this by reading it cold,
without the BRIEF open. It names who is affected (a reader who cannot tell an
absorbed artifact from one never produced), what is broken (the record's
guarantee is redundant, its cost is contention, its verification does not fire),
and why now is implicit in the mechanism being live and unproven. Nothing in it
requires the exploration or the BRIEF. The one paragraph a cold reader cannot
fully resolve is the third count's middle clause, covered under rubric 2.

**2. Unexplained jargon and unresolved deixis. FAIL — three sentences.** The
abstraction policy is sound and mostly self-resolving through the acceptance
criteria. Three places cross into unresolvable:

- Problem Statement, third count: "because the underlying command emits its
  unresolved argument on success-shaped output." No antecedent for "the
  underlying command"; "success-shaped output" is coined here and used nowhere
  else; no AC pins it. Resolvable only by opening
  `.github/workflows/validate-docs.yml:145`.
- Out of Scope: "the column-blind row lookup." Definite article, single
  occurrence, never described. The three defects listed beside it all have
  Problem Statement antecedents; this one does not.
- AC14: "each of the four shipped documents." Covered as a blocking finding
  above. The only candidate antecedent in the document — "four documents of
  rationale" in the Problem Statement — points at a different set.

A fourth, milder case: R6's "a path-shape assertion" appears once and is not
described. It resolves to `check-citations.sh:99-102`, and R6's other three
clauses (flag, default, search exclusion) give enough context that an
implementer will find it. AC5 does not mention it, though, so nothing verifies
its removal.

**3. Ambiguous requirements. FAIL.** Detailed above. R8 acceptable with a noted
tension; R10 blocking on two counts; R13 unambiguous and correct; R15 blocking;
R14/AC16 blocking. R1 through R7, R9, R11 and R12 each have one reading, with
two caveats: R9's "the published contract" in the second sentence may or may not
be the same thing as "adopter-facing documentation" in the first — AC13 implies
it is, which makes the sentence circular; and R11 requires the removal be
"recorded durably" without saying what class of artifact carries it, so an ADR,
a Decisions section on the downstream DESIGN, and a note under `docs/guides/`
all satisfy AC15 equally. Whether that is legitimate deferral is arguable, but
the Status section delegates only "which replacement claim each prose site gets
and what each amendment says" to the DESIGN — not this.

**4. Goals are outcomes. Body PASS, frontmatter FAIL.** Detailed above. All four
body bullets are outcomes; none names a file or a mechanism. The third one is
the best sentence in the document.

**5. User Stories. PASS.** Four stories, four distinct situations, four genuine
"so that" clauses that name a consequence rather than restating the want:

| Role | So that | Distinct? |
|---|---|---|
| chain author running `/scope` alongside other agents | branch merges regardless of sibling folds | yes |
| contributor following a citation to a missing path | can distinguish absorbed from never-written without history | yes |
| maintainer pinning shirabe's validation workflow | not handed an obligation they lack the means to meet | yes |
| future contributor noticing no central ledger | evaluates the decision instead of re-proposing the mechanism | yes |

Stories two and four share the noun "contributor," but the situations and
outcomes do not overlap, and each maps to a requirement (R8/R12, R11). No
generic "user" anywhere.

**6. Citation vs Restatement. Marginal PASS, with real duplication to note.**
The Problem Statement is correctly restated in full and is genuinely the PRD's
own — it reorganizes the BRIEF's three counts, drops "it was never argued for,"
and adds the duplicate-detection point the BRIEF does not make. Requirements and
acceptance criteria are original. Two places duplicate rather than cite:

- *Out of Scope.* Three of six entries are near-verbatim from the BRIEF's OUT
  list. Compare BRIEF — "Whether `/scope` folds, when it folds, and what carries
  into the survivor are settled and untouched. This work changes what a fold
  *records*, never what it *does*." — with PRD — "Whether `/scope` folds, at
  which hops, and what carries into the survivor are settled. This work changes
  what a fold records, never what it does." Out of Scope is a required section,
  so covering the same boundary is legal; copying the sentences creates the
  second copy that drifts. Worth rewriting in the PRD's own terms. One
  substantive divergence: the BRIEF puts the survivor-side trace OUT, while the
  PRD binds it as R12. The PRD's handling is better, but the two documents now
  disagree about which side of the boundary it sits on.
- *`motivating_context`.* It reproduces the substance of the BRIEF's "It was
  never argued for" paragraph in different words. Placing the never-argued
  history in `motivating_context` rather than the Problem Statement is the right
  call, but the wording should cite the BRIEF's finding rather than re-derive
  it.

The four User Stories map one-to-one onto the BRIEF's four User Journeys. That
is carry-forward into the PRD's own required section, not restatement alongside
it, and the compression is real. This passes.

**7. Writing style. PASS.** The validator is clean, so the mechanical rules are
already enforced and I did not re-scan them; I confirmed independently that no
term from `rules.yaml` appears and no workspace-banned word ("tier/tiered",
"robust", "leverage", "comprehensive/holistic", "facilitate") is present. No
"It's worth noting", "Moreover", "Furthermore", "Additionally". No preamble —
the Problem Statement opens on the mechanism. Em dashes are 15 across 2,551
words, roughly 5.9 per thousand against a threshold of 10.

Burstiness is genuine and better than most documents I review: "It fails on
three counts." sits next to a 41-word sentence, and "The record has never held
one." closes an Out of Scope bullet on five words. Two observations that are
preferences rather than violations: the document contains zero contractions,
which is defensible for SHALL-bearing sections but flattens the Problem
Statement and Decisions prose; and the Decisions entries settle into a uniform
25-to-35-word rhythm that the rest of the document avoids.

**8. Internal consistency. FAIL.** Three findings, detailed above: frontmatter
`goals` diverges in kind from the Goals section; frontmatter `problem`
over-claims the redundancy that the body and Known Limitations both qualify; and
the roadmap-cell decision contradicts the first Known Limitation. Two smaller
enumeration mismatches: R14's "over the corpus" against AC16's "over the changed
document set," and AC15's seven carriers ("survivor frontmatter alone, commit
trailer, git notes, per-chain file, forge metadata, rotation, and per-fold
file") against Out of Scope's six, which omits "survivor frontmatter alone" —
two lists of the same set that differ by one item.

On the growth question specifically: **confirmed absent.** The only occurrences
of growth or size vocabulary in the entire document are in the disclaiming
decision itself (line 282 "Growth is not a reason", line 285 "Any argument from
file size is unsupported") and the unrelated "byte-identical" at line 229. No
requirement, goal, user story, acceptance criterion, or Problem Statement clause
argues from file size, row count, unbounded growth, or context cost. The
Problem Statement's cost paragraph rests entirely on contention, and its closing
line — "a file that has never held a row" — is the opposite of a growth
argument. The document keeps its promise.

**9. No emojis. PASS.** Verified by codepoint scan across the emoji, dingbat,
and variation-selector ranges. Zero hits.

## Required changes

1. **[BLOCKING]** Enumerate the amendment targets. Replace R10's "The shipped
   documents whose requirements and decisions the record discharges" and AC14's
   "the four shipped documents" with an explicit list of paths. Decide
   deliberately whether `DESIGN-scope-chain-mandatory-steps.md` (:313, :719) and
   `PRD-scope-chain-mandatory-steps.md` (:784) are in or out — both match R10's
   description today and neither is reachable by AC2.
2. **[BLOCKING]** Name the objection in R10. State, in one clause, what
   objection `DESIGN-scope-consolidation-over-skipping.md`'s decision was
   rescued from, so R10's second sentence and AC14's affirmative-statement test
   can be applied by someone who did not write this PRD.
3. **[BLOCKING]** Resolve the roadmap-cell contradiction. Either the cell
   preserves the folded-versus-never-started distinction, as the Decisions entry
   says, or the reader gets only "no downstream artifact," as the first Known
   Limitation says. If the reconciliation is that the ROADMAP itself is later
   deleted by the cascade, write that down.
4. **[BLOCKING]** Align R15 with AC2. Either narrow R15's first sentence to the
   record's path, or widen AC2 beyond the literal `docs/folds.md` string and
   bring the three non-path references in `DESIGN-scope-chain-mandatory-steps.md`
   and `PRD-scope-chain-mandatory-steps.md` into scope.
5. **[BLOCKING]** Align R14 with AC16 on validation scope — corpus or changed
   set, not both. While there, extend R14's "scope-scripts test suite" to reach
   `run-cascade_test.sh`, which AC11 requires and which lives under
   `skills/execute/scripts/`.
6. **[BLOCKING]** Rewrite frontmatter `goals` as a success shape rather than a
   task list. The body Goals section already has the right four outcomes;
   compress those instead of restating R1, R7, R8 and R10.
7. Rewrite the skip-guard sentence in the Problem Statement's third count so it
   resolves without opening the workflow. Name the command, or state the
   property in terms the document has already introduced.
8. Give "the column-blind row lookup" an antecedent, or drop the phrase — the
   Out of Scope bullet works with three defects.
9. Qualify frontmatter `problem`. "The surviving document already carries the
   same fact" should carry the same "wherever the survivor stays on disk"
   restriction the body and Known Limitations both apply.
10. Reconcile the two carrier lists: AC15 names seven, Out of Scope names six.
    Add "survivor frontmatter alone" to Out of Scope, or cut it from AC15.

## Optional improvements

- Add a clause to R8 distinguishing a claim that rests on the record's existence
  from prose that merely describes a removed mechanism, so "every ... rather
  than deleted" cannot be read as forbidding the `.gitattributes` comment
  deletion that R7 requires.
- Say which artifact class carries R11's durable record. "A durable artifact" is
  satisfied equally by an ADR, a Decisions section on the downstream DESIGN, and
  a note under `docs/guides/` — and R11's whole purpose is that a future
  contributor can find it. Note also that the exploration research lives under
  `wip/` and will be swept, so the durable artifact cannot cite it.
- R9's second sentence: if "the published contract" is the same
  `docs/guides/doc-validation.md` the first sentence covers, say so; if it is
  something else, name it, because AC13 only reaches the guide.
- Add a mention of the `path-shape assertion` to AC5, so every clause of R6 has
  a verification.
- Rewrite the three Out of Scope entries that are near-verbatim from the BRIEF
  in the PRD's own words, and reconcile the survivor-side-trace boundary: the
  BRIEF puts it OUT, the PRD binds it as R12.
- Consider whether AC2's `crates/` clause earns its place. No file under
  `crates/` contains the literal `docs/folds.md` string today, so that clause
  passes without any work; the crates-side edit that actually matters is the
  comment at `crates/shirabe-validate/src/formats.rs:180-181`, which AC17
  already covers.
- Let a few contractions into the Problem Statement and Decisions prose, and
  break up the uniform sentence length in Decisions and Trade-offs.
