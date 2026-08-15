# Phase 4 jury — clarity and altitude review

Target: `docs/prds/PRD-scope-artifact-persistence.md`
Reviewer lane: ambiguity, altitude, citation-vs-restatement, decision closure, writing style.
Round 2 (re-review after revision).

PASS

All seven blocking findings from round 1 are genuinely fixed, and the fixes are
the right ones rather than the minimum ones. R13 states the property instead of
ordering the steps, so the actor stays open and Open Question 2 no longer
contradicts a requirement. R14 says explicitly that the existing itemization
survives and contributions are added to it, naming the ancestor's own alongside
its inherited ones — the replace-or-extend fork is closed. R15 is now the most
precisely specified requirement in the document: strong match, weak class, file
set, and `wip/` named out. The eight non-blocking findings are all taken.

Seven small things remain. None of them produce two different systems, and one
(the decision count) is a numeral. They should be fixed before the PRD goes to
Accepted, not before it goes to DESIGN.

---

## Fix before Accepted

### F1. The Status section says five decisions; there are now six

"whose five settled decisions are recorded under Decisions and Trade-offs"

The section holds six: the two-sided adequacy test, the no-gate decision
`[critical]`, the corpus-out-of-scope decision `[critical]`, the record of the
operation, the frontmatter-plus-Status-line, and the one-change shipping
decision. The count was correct before the revision added the corpus decision.

### F2. R16's scope is stated everywhere except in R16

R16: "`shirabe validate` SHALL fail when an `R<n>` requirement citation in a
document resolves neither within that document nor within its surviving
upstream."

Read alone, that is a repository-wide requirement-citation resolution check. Two
other places say it is not. Out of Scope: "R16 is narrower and distinct: it fires
on requirement numbers orphaned by this work's own absorbs." R28: "the checks
this work adds SHALL emit nothing on a document that declares no absorption."
Both close the question, but neither is in R16, and R28 is twelve requirements
away and phrased as a compatibility constraint rather than a scoping rule. An
implementer reading R16 in isolation builds the repo-wide check that the same
document excludes as a repair campaign.

Second problem in the same requirement: "resolves" is undefined for a citation
that points at another document's requirements, and this PRD contains one. The
sixth decision says "R14/R15 of the execute contract bar `/execute` from reading
diffs" — those are `/execute`'s R14 and R15, not this PRD's, but this PRD has an
R14 and an R15, so the citation resolves locally and wrongly. R16 has no way to
express a cross-document requirement citation, and no way to tell one from a
local one.

Fix: put the scope in R16 (fires on requirement numbers orphaned by an absorb
this run performed), and say how a citation to another document's requirements is
written, or state that R16 does not attempt to check those.

### F3. R8 and R21 each mandate the frontmatter declaration

R8: "A document SHALL declare its absorptions in frontmatter." R21: "A surviving
document SHALL record what it absorbed in both a machine-readable frontmatter
field and one line in its `## Status` section."

One field or two? The acceptance criteria use a single name for it — "a
survivor's absorption declaration" — which implies one, but the requirements read
as two independent obligations, one for the validator and one for the reader. Fix:
have R21 cite R8's declaration rather than re-mandate a field ("The declaration
R8 requires SHALL hold the absorbed path; the survivor SHALL additionally carry
one line in `## Status` naming …").

### F4. R22 requires that a PRD-level contract be stated, without stating it

"The PRD-level contract for what `exit_artifacts:` holds under a fully folded
chain SHALL be stated so the guard has a defined seed."

If it is PRD-level, this is the document that owes it, and it is not here. If the
DESIGN is meant to define the seed, say that — a requirement that a requirement
be written reads as an unfinished sentence either way. This is the one place a
reader cannot tell whether something is deferred on purpose or left out by
accident.

### F5. R15's closing sentence reads as normative but is rationale

"It is justified entirely by the hops this work opens forward; it carries no
retroactive commitment and produces no verdict about any document already on
disk."

The intent is clear against the corpus decision: the check does not judge whether
existing documents should fold. But "produces no verdict about any document
already on disk" can be read as a constraint on what the check may report, which
sits badly next to the criterion requiring the citing file — an existing document
— to be named. Move it to Out of Scope or to the corpus decision, where the same
argument already lives.

### F6. "[mech] … Verified by inspection" contradicts the criteria preamble

"**[mech]** Every path the absorb procedure writes or deletes appears in
`/scope`'s enumerated write-target set. Verified by inspection."

The preamble defines `[mech]` as "a criterion a machine decides." Inspection is
not that. Either the write-target set comparison is machine-checkable (say how)
or the criterion is `[judg]`.

### F7. "within a stated band" states no band

The fixture-parity criterion requires the two fixtures to "hold their line count
within a stated band of each other." Nothing states the band. If the DESIGN sets
it, say so; as written the criterion cannot be decided by anything until a number
appears somewhere.

---

## Verified fixed

- **B1/B2.** No ordering-of-steps requirement and no invented internal artifact
  remain. "Carry table" appears nowhere; R14 refers to the carry check "as it does
  today." The no-gate decision now credits R13's property rather than a reorder.
- **B3.** R7 states both failure modes and puts the criterion in the format
  contract, not in the section.
- **B4.** R14 closes the replace-or-extend fork and the own-vs-inherited fork in
  one sentence.
- **B5.** R15 defines the strong match by repo-relative path, characterizes the
  weak class, scopes the search to git-tracked files, and names `wip/` out.
- **B6.** R22 says "any surviving durable artifact" and names the fully folded
  chain as the case both surfaces must handle. (The seed contract itself is F4.)
- **B7.** Two decisions carry `[critical]` inline and the preamble says what the
  mark means.
- **N1–N8.** Terms paragraph defines both senses before R3 uses either, and its
  "R4 through R9" pointer is accurate. R4 pins placement against `## Status`,
  chain order moved to R6. R8 is self-contained. R23 names `/work-on`'s
  implementation phase and the maintainer reviewer's brief — both exist
  (`skills/work-on/references/review-panel-orchestration.md`). R24 says `/scope`.
  R15's weak-match clause makes R18's set non-empty. R20 is the property form.
  R6's vacuous bound is gone.

## Altitude on the new material

The revision added ten requirements and I checked each against the line. Nothing
crossed it.

Every newly named surface exists and is being constrained rather than designed:
re-entry protection (`skills/scope/references/state-schema.md:57-61`),
`docs/guides/doc-validation.md`, `skills/scope/evals/evals.json`,
`skills/execute/scripts/run-cascade_test.sh`, the canonical-section-order check,
the cross-repo parity baseline. R5 requires a fixed type-derived heading and
gives the reason (machine-recognisable without reading the body) while leaving
the derivation rule open — property, not mechanism. R21's "pinned shape rather
than free prose" does the same for the `## Status` line. R9 assigns the placement
check to the existing order check, which is prescriptive about *which* check, but
its point is that no new check appears, and that is a requirements-level call of
the same kind as R23 and R26.

One dip below altitude, and I am letting it stand: the cascade criterion's
parenthetical "(This fails against current code: `run-cascade.sh` leaves the
pre-existing line untouched when `CASCADE_DESIGN_PATH` is unset.)" names a script
variable and its behaviour. It earns its place by proving the criterion is a real
regression test rather than a tautology, and it describes existing code rather
than prescribing new code. The DESIGN should stay free to fix that some other
way.

## Citation vs restatement

Unchanged from round 1, and improved. The Problem Statement still stands alone.
The material added to Out of Scope is exploration measurement, not BRIEF
restatement — 55 retroactive candidates, 374 pre-existing unresolvable names, 201
surviving files, a 1.03 redundancy ratio among DESIGNs actually in a PRD chain.
Those numbers are what makes the boundaries decidable rather than assertions, and
none of them are in the BRIEF.

## Decision closure

Six entries, all four elements present in each. The record-of-the-operation entry
took the round-1 note and now closes the class by name ("including an archive
directory and a per-run decision record"), so a DESIGN author is not deriving it.
The shipping entry states the bound as a property instead of counting edits, and
adds the reason the work sits with `/work-on` rather than `/execute`. The new
corpus decision is the strongest in the section: it names the alternative, the
population it would touch, the structural reason it fails, and the fact that the
advocate assigned to argue for it changed their vote.

## Writing style

Clean. No banned vocabulary on a full-list check. Twenty-one em dashes across 509
lines, roughly one per twenty-four — restrained for a document this dense. No
preamble, no adverb openers, contractions present, real burstiness ("Stage 1
short-circuits it." against the sentence that follows it). Known Limitation 2 —
that the feature's central behaviour is graded on a weekly cron rather than gated
on merge, "weaker than it reads" — is the kind of thing a draft usually buries.
No findings.
