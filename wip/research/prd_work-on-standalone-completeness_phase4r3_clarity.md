# Clarity Review (round 3): PRD-work-on-standalone-completeness

## Verdict

FAIL

## Prior findings — closed or not

**1. R16a/R17 boundary — closed.** R16a now carries an explicit "Boundary
against R17" clause: an occurrence inside an eval suite is governed by R17
and SHALL NOT be resolved under R16a, but the inventory still lists it,
marked as delegated to R17. This directly removes the fork round 2 found —
a reviewer no longer has to guess whether the three eval scenarios belong in
R16a's inventory or R17's territory; the text says both ("listed... marked
delegated") and R16b's re-run check ("every hit is either in the inventory or
is non-routing") now holds without contradiction, since delegated hits are
*in* the inventory. Genuinely fixed.

**2. R5a vs. Decisions — closed.** R5a now reads: "This PRD settles the
constraint on that decision and not the location: the chosen location SHALL
NOT leave the single-issue skill depending on the plan entry point." The
paired Decisions entry ("Decided: the constraint, not yet the location...
Which directory it lands in is a design-hop choice") says the identical
thing in the identical shape. No daylight between them anymore.

**3. "The classification table" — closed.** R8 itself now requires "the
classifications SHALL be recorded together in a classification table
committed with the change, one row per obligation naming the obligation, its
class, and where it is enforced or carried." The acceptance criterion's
reference to "a classification table" now cites a table R8 actually mandates,
with a stated row shape. No implementer can satisfy R8 with scattered inline
annotations anymore.

**4. Label drift — closed.** Grepped every occurrence of
gate-enforced/evidence-carried/gateable/judgment-carried in the document.
R8, its acceptance criterion, the R7a-adjacent acceptance criterion, and
Known Limitations all now say "gate-enforced" and "evidence-carried"
uniformly. No stray "R6-gateable" or "judgment-carried" survives anywhere,
Known Limitations included.

**Unaddressed from round 2 (not one of the four, but still open).** Round
2's required-change #2 — bounding "the surface" R16a's inventory must cover
— was never touched. R16a still says "listing every routing claim in the
surface" with no definition of what the surface is. The actual `multi-pr`
corpus spans dozens of historical Done/Accepted BRIEFs, PRDs, DESIGNs and
DECISION records beyond the two R18 already names, and R16a's own
routing-claim definition ("a statement that directs a reader or an agent to
one entry point rather than the other") does not exempt a closed document
that asserted the old routing when it was accepted. One implementer reads
"the surface" as live/operational documentation only (skills/,
koto-templates/, README, references/, plus the two R18 supersedes);
another reads it literally and starts editing or annotating a stack of
historical Done PRDs no other rule in this repo touches once a document is
Done. R16b's re-run check inherits the same gap: "every hit is either in the
inventory or is non-routing by the definition above" only resolves cleanly
once the candidate-producing command's scope is itself fixed, and the PRD
never fixes it. This is the same class of ambiguity the four claimed fixes
closed elsewhere in R16 — it just wasn't on the author's list this round.

## New text — R19/R19a/R19b

R19's core two SHALLs are clear and testable: a root session's new terminal
ticks retain the workflow context record; no child session ever requests
that retention. "Terminal tick" is an established term of art in this
corpus (`skills/scope/koto-templates/scope.md`: "the tick that reaches the
terminal"; `skills/execute/SKILL.md`: "Autonomy binds at every tick") rather
than a coined ambiguity, and root/child map onto the child-run/plan-entry
distinction R11 and R12 already establish — a reader carries that mapping
across without difficulty.

The specific trap named in the brief — "root-only at runtime, not textual"
— holds up. It isn't free-floating: the same sentence glosses it in the
clause immediately before ("an unconditional edit there would hand the flag
to every child"), and R19a's own regression test targets exactly that
failure mode ("a later tidy-up cannot reintroduce it by making the behaviour
unconditional"). Read together, "textual" unambiguously means "baked
unconditionally into the shared template text" and "runtime" means
"conditioned on the session's root/child status when it executes" — an
implementer reaching for a runtime-evaluated conditional *inside* the
template (rather than an outer, template-independent check) is not the
textual reading this rules out, since R19b hands the actual mechanism to a
separately-filed, already-landing fix rather than leaving it for this PRD to
invent. The trap is closed.

One loose thread, not fail-grade on its own: R19 switches vocabulary from
"run" (used everywhere in R1–R18, User Stories, Problem Statement) to
"session" ("root session," "child session") with no bridging sentence.
Nothing in the document states these are the same entity viewed at a
different layer (a run materializes as a koto session), so a careful reader
has to infer the equivalence rather than read it. It doesn't appear to
create a compliance fork — "root" and "child" resolve the same way under
either reading — but it's worth tightening for a reader who hasn't already
built the run=session mental model from the rest of the corpus.

## Per-requirement ambiguity scan

- **Definitions (Anchor).** Unambiguous, unchanged from round 2's clean pass.
- **R1–R4.** Unchanged text; clear, as in round 2.
- **R5.** Unchanged; clear.
- **R5a.** Now clear and consistent with its Decisions entry — see above.
- **R6, R7, R7a.** Unchanged; clear.
- **R8.** Now clear; the table requirement and its acceptance criterion agree.
- **R9, R10.** Unchanged; clear.
- **R11–R15.** Unchanged; clear.
- **R16.** Clear as a two-part split.
- **R16a.** The eval/R17 fork is closed. The unbounded "surface" is not — see
  above. Two implementers can still disagree about which files the inventory
  must cover.
- **R16b.** Inherits R16a's unresolved scope: "every hit" depends on a
  candidate-producing command whose intended scope the PRD never states.
- **R17.** Clear; matches the three named scenarios.
- **R18.** Clear in intent; the contradicted PRD/design are still not named
  in the PRD's own text (only inferable via the upstream BRIEF). Same as
  round 2 — not newly broken, not fixed, not blocking on its own.
- **R19.** Clear on its two SHALLs; "session" vs. "run" is an unglossed
  vocabulary switch, not a compliance fork.
- **R19a.** Clear; the regression test's target (unconditional behavior) is
  named explicitly.
- **R19b.** Clear; correctly defers the mechanism and correctly flags the
  R12 overlap as an open design question rather than silently deciding it.
- **R20–R22.** Unchanged; clear.

## Required changes

1. Bound "the surface" in R16a. State whether the inventory must cover the
   full repository text corpus (including historical Done/Accepted BRIEFs,
   PRDs, DESIGNs, and DECISION records that assert the old routing) or only
   live/operational documentation plus the two documents R18 names as
   superseded. Either answer resolves this; leaving it to inference is the
   same failure mode this round closed everywhere else in R16.
2. Optional but recommended: add one clause bridging "run" (R1–R18's term)
   and "session" (R19's term) so a reader doesn't have to infer they're the
   same materialized thing viewed at the koto layer.

## Observations

No banned words from `rules.yaml` fired (tier/journey/underscore do not
appear at all, so the repo's carve-out is moot rather than tested). Em dash
density is 35 dashes over ~4,300 words, roughly 8.1 per thousand — still
under the 10-per-thousand threshold but higher than round 2's 33; worth a
glance if another pass adds more. Problem Statement still stands alone
without the BRIEF. No private-repo references or non-public issue numbers;
`source_issue: 361` is this repo's own and permitted, and no other issue
numbers appear in the body. Section order matches the format spec's
canonical order with Decisions and Trade-offs and Known Limitations
correctly placed after Out of Scope.
