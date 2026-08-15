# Phase 4 jury — clarity and altitude review

Target: `docs/prds/PRD-scope-artifact-persistence.md`
Reviewer lane: ambiguity, altitude, citation-vs-restatement, decision closure, writing style.

FAIL

This is a revision-pass fail, not a rewrite. The document is well argued, the
Problem Statement stands on its own, the Decisions section mostly does close
things, and the prose is clean. But five requirements admit two readings that
would produce materially different systems, one requirement contradicts an Open
Question outright, and the Decisions section opens with a pointer to marks that
were never made. Fixes below are mostly one-sentence rewrites.

---

## Blocking

### B1. R8 contradicts Open Question 2

R8: "The absorb procedure SHALL author the contribution section before building
the carry table."

Open Question 2: "Is the contribution section authored by the child at drafting
time or by the parent at fold time? R8 fixes the ordering within the absorb, but
not which actor writes the prose."

R8 assigns the authoring to the absorb procedure, which *is* the parent at fold
time. Either the actor is settled (and OQ2 should go) or it is open (and R8 must
not name the actor). An implementer reading R8 will build fold-time authoring and
never reach the question.

Fix: restate R8 as a property of the carry check rather than an ordering of
steps — "The carry check SHALL be evaluated against contribution text that
already exists, never against a prediction that it will be written" — which
leaves the actor genuinely open and keeps the reason R8 gives.

### B2. R8 is also the clearest altitude break in the document

"Author X before building the carry table" is a sequence of internal procedure
steps, and "carry table" is not a thing that exists — the current procedure has a
`carry_check` YAML block in
`skills/scope/references/phases/phase-2-chain-orchestration.md:466`. So the
requirement both prescribes the shape of a new internal artifact and orders the
steps that touch it. The line: naming the existing `carry_check` as something the
requirement constrains would be fine; inventing "the carry table" and sequencing
the procedure around it is the DESIGN's call. The B1 rewrite fixes this too.

The Decisions section then leans on the same drift — "bought for free by R8's
reorder." Reorder is an implementation word; say what the property buys instead.

### B3. R4 has an absurd literal reading

"A contribution section SHALL carry an adequacy expectation with both a too-long
and a too-thin failure."

Reading 1: the format contract for contribution sections states a two-sided
adequacy criterion. Reading 2: each individual contribution section must itself
contain text stating its own adequacy expectation. Reading 2 is silly, but it is
what the sentence says — the section is the subject of "carry."

Second problem in the same sentence: the criterion given ("judged against whether
the survivor's own argument stands without the absorbed document") only diagnoses
the too-thin failure. The too-long failure has no stated test in R4. The Decisions
section supplies it ("if the section reads like a rewrite of the upstream, fold it
back"), but a requirement should not need the Decisions section to be complete.

Fix: "The contribution section's format contract SHALL state a two-sided adequacy
criterion: a section that reads as a rewrite of the absorbed document is too long,
and a section without which the survivor's own argument does not stand is too
thin. Presence alone SHALL NOT satisfy it."

### B4. R9 does not say whether it replaces or extends the existing carry check

"The carry check SHALL run per contribution at every hop."

Today the carry check walks the *upstream's required sections* one at a time
(phase-2, Stage 3). R9 says it runs per contribution. Two readings:

- Replace: the itemization is now per contribution section only, so an ancestor's
  required sections that are not contributions stop being itemized.
- Extend: sections are still itemized, and contributions are itemized in addition.

These build different verification surfaces, and the first one silently narrows an
existing guarantee. A third reading hides inside "per contribution": does it mean
each contribution section the ancestor carries (transitively inherited ones only),
or the ancestor's own contribution plus its inherited ones?

Fix: state which itemization survives and say explicitly that the ancestor's own
contribution is included alongside those it inherited.

### B5. R10 asks the implementer to invent a match taxonomy and a repository scope

"A citation by path SHALL downgrade the verdict ... A weaker citation match SHALL
be surfaced to the judging agent rather than acted on mechanically."

Nothing defines "weaker." One implementer greps the filename stem, another the
document title, another the slug, another all three with different confidence.
The requirement's whole point is that the strong case is mechanical and the weak
case is judged, so the boundary between them is load-bearing and has to be
stated, or explicitly handed to the DESIGN as a named choice.

"Any other file in the repository" is the second fork. Tracked files only, or the
whole working tree? `wip/` is non-durable staging by workspace rule and a `/scope`
run writes into it constantly — if `wip/` counts, a chain will block its own folds
on its own scratch state every time. That is a behavioral difference an
implementer will decide by accident.

Fix: define the strong match (a citation containing the artifact's repo-relative
path) and characterize the weak class in one clause, then say which file set is
searched and name `wip/` in or out.

### B6. R16 does not cover the case acceptance criterion 1 requires

R16: "`/execute` SHALL NOT assume a surviving DESIGN."

Two readings: (a) fall back to the next durable anchor — the PRD, then the BRIEF;
(b) handle the absence of any anchor. The first acceptance criterion demands a run
that ends "with no durable artifact in `docs/`", and `/execute`'s guard seeds on
"the durable surviving anchor" (`skills/execute/SKILL.md:541-546`) while the
cascade's roadmap Downstream rewrite reads `CASCADE_DESIGN_PATH`
(`skills/execute/scripts/run-cascade.sh:69`). In the fold-everything case there is
no anchor at all, not merely no DESIGN. Reading (a) satisfies R16 as written and
still breaks that run.

Fix: say "SHALL NOT assume any surviving durable artifact" and name the
zero-artifact chain as the case both surfaces must handle.

### B7. The Decisions section points at marks that do not exist

Preamble: "the two marked critical ran the full adversarial path with persistent
validators." No entry in the section is marked critical. A reader cannot tell
which two, and the sentence is the only signal about how much weight each decision
carries.

Fix: mark them, or drop the clause.

---

## Non-blocking, but fix in the same pass

### N1. "Contribution" is used in three senses and defined in none

R2 introduces it as a type-level property ("Each artifact type SHALL declare one
contribution"), then immediately as a section in a document ("SHALL carry that
ancestor's contribution as a single section"). R6 uses it as content in the
absorbed document ("holds nothing beyond its contribution"). R9 uses it as a unit
of verification. One sentence defining the type-level declaration and the
per-document section that realizes it, before R2 uses both, removes the whole
class of confusion.

### N2. R2's "ahead of its own content" is ambiguous against Status

Every artifact type here opens with `## Status`, and R15 puts the absorption line
inside it. So "placed ahead of its own content" reads either as first section in
the document (which fights the canonical section-order check) or as first after
Status. Say which. Also, "in chain order" is vacuous for a single section — it
belongs in R3, where there is more than one.

### N3. R5's "declared absorptions" is undefined until R15

R5 requires the sections "a document's declared absorptions imply," but the
frontmatter field that constitutes the declaration is not introduced until R15.
A cross-reference in R5 fixes it.

### N4. R17's subject is ambiguous, and its enforcement path is unnamed

"Implementation SHALL carry a standing instruction to record in code comments why
the code is shaped as it is."

Reading 1: this feature's own code must carry why-comments. Reading 2: shirabe's
implementation workflow must instruct every future implementation to write them.
The BRIEF makes reading 2 the intent, but R17 does not name where the instruction
lives or who receives it, and "Implementation" as a bare subject supports both.

"Enforced through an existing blocking review path" then names no path. There are
several candidates (the jury, a reviewer agent, a CI lifecycle check). Naming the
existing surface is allowed and would settle it; leaving it unnamed leaves an
implementer guessing at a mechanism the requirement already constrained.

### N5. R18's "the skill's" has the wrong antecedent

The nearest skill named is `/execute` in R16. R18 means `/scope`'s eval suite. Say
`/scope`.

### N6. R12 is arguably empty under R10

R12 requires post-absorb re-validation to cover "every document that referenced
the absorbed artifact." R10 downgrades to `keep` whenever another file cites the
artifact by path. So by the time R12 runs, that set is empty except for whatever
weak matches the judging agent waved through — which R10 does not say it can do.
Either state that the agent may accept a weak match and proceed (making R12's set
non-empty and meaningful), or R12 should say what it covers that R10 has not
already excluded.

### N7. R14's "its absence SHALL prevent the fold" is loosely tensed

The record is described as something a *completed* fold leaves, yet its absence
prevents that same fold. Precondition or rollback is the DESIGN's call, so the
requirement should be stated in a way that survives both: "A fold SHALL NOT land
unless the record was written."

### N8. R3's second sentence is an observation, not a requirement

"The number of contribution sections a document carries SHALL be bounded by the
number of ancestor types" is a consequence of R3's first sentence, not an
independent obligation, and "bounded by" does not say whether the bound is
inclusive. Either drop it or restate it as the invariant you want tested.

---

## Where the PRD is fine, and why

**Altitude, generally.** Most of what looks like mechanism is a named existing
thing the requirement is constraining, which is the right side of the line:
`shirabe validate` (R5), the closed write-target set (R13, exists in
`phase-3-exit-finalization.md`), the existing abort path (R10, the failed carry
check in phase-2), path resolution (R15), the finalization guard and the roadmap
Downstream rewrite (R16, both real). None of these prescribe the shape of the new
thing.

Two borderline calls I am letting stand. R14's "content-addressed pointer"
constrains a property rather than a mechanism, the reason is stated in Known
Limitations (squash-merge means a path pointer resolves to nothing), and the
Open Questions explicitly leaves the surface to the DESIGN — that is the right
split. R15's frontmatter-field-plus-one-Status-line is prescriptive about shape,
but the Decisions section grounds it in an existing house pattern
(`shirabe transition`'s `superseded_by:`), and matching an existing pattern is a
requirements-level choice, not a design one.

**Citation vs restatement.** The Problem Statement restates the BRIEF's problem in
full, which is exactly what the format contract asks for, and a cold reader gets
the three stages, the schema comparison, and the consequence without opening
anything. Everything downstream of it is carried into the PRD's own sections
rather than summarized alongside them: the BRIEF's User Outcome lands in Goals,
its Journeys become User Stories, its Out list becomes Out of Scope. That is
carry-forward, not duplication. The Out of Scope entries reproduce the BRIEF's
reasoning at close to full length, which is defensible for a section whose job is
to be self-contained, and the fifth entry (CI deletion blindness) is new and earns
its place. No finding here.

**Decision closure.** Four of the five entries do the job — decision, named losing
alternatives, and why each lost. The adequacy-test entry is the strongest
(presence-only, scored rubric, and word-count floor each rejected with a reason).
The no-gate entry closes both rivals structurally. The tombstone-stub rejection is
honest enough to say the loser was stronger on the merits and why it still lost.

The record-of-the-operation entry is the weakest of the four: its losing
alternative is a class ("any destination preserving the absorbed content") rather
than a named option. That mostly works, because the argument against the class is
what closes it, but a DESIGN author looking for "why not an archive directory" has
to derive it.

The fifth entry does not close. "Everything ships in one change" is settled fine,
but "the rationale-in-code instruction is bounded to two diff-checkable edits"
names no two edits, and it is plan-altitude besides — how many edits a change
takes is the PLAN's to decide. Either name them or state the bound as a property
("bounded to instruction text in existing files, with no new gate"), which is
what R17 already says.

**Writing style.** Clean. No banned vocabulary (checked the full list: no
tier/robust/leverage/comprehensive/holistic/facilitate, no adverb openers, no
hollow gerunds). Ten em dashes across 360 lines is restrained. Contractions
present, sentence length genuinely varies ("Stage 1 short-circuits it." next to
the forty-word sentence after it). No preamble anywhere. The Known Limitations
section takes real positions instead of hedging, and the last entry — that this
chain cannot dogfood its own change — is the kind of admission an AI draft
usually omits. No findings.

---

## Outside my lane, flagged anyway

Acceptance criteria 1 and 2 turn on "holds only sequencing value" and "records
live rejected alternatives," which are agent judgments rather than binary checks.
Whoever owns testability should look at whether those are verifiable by someone
who did not write the PRD, or whether they need fixture chains that make the
condition concrete.
