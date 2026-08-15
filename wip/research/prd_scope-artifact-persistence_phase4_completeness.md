# PRD Jury -- Completeness Review: scope-artifact-persistence

FAIL

Target: `docs/prds/PRD-scope-artifact-persistence.md`
Reviewer scope: completeness only (decision coverage, requirement-to-criterion
coverage, BRIEF scope-boundary coverage, the four absorb defects, eval accuracy).
Clarity and testability are other reviewers' calls and are not judged here.

The document is close. Twenty-two requirements carry the bulk of five settled
decisions faithfully, and the two hardest ones (D2's no-gate ruling, D4's
retirement guard as a point query with no override) are rendered exactly. It
fails on eleven specific holes, four of which are the failure mode this review
exists to catch: a settled decision that landed in prose and never became a
requirement, so the DESIGN and PLAN will not see it.

---

## 1. Settled decisions that never reached a requirement

### 1.1 The content-boundary carve-out (BLOCKING)

The BRIEF's Scope Boundary IN list, item 3, is two halves:

> The artifact format contracts, to the extent contribution sections need a home
> **and the content-boundary rules need a carve-out for the absorbed case**.

Only the first half reached a requirement (R5, the validator's presence check).
The second half has no requirement and no criterion.

This is not cosmetic. The exploration's own finding names it as the real
obstacle:

> **The real fence is prose, not schema.** `design-format.md` tells a DESIGN to
> cite requirements by their numbers rather than restate them; `plan-format.md`
> tells a PLAN that drifts into architecture to replace the content with a
> citation. ... That is an editorial contract with no machine enforcement, and
> it is the thing an absorbed case has to carve out.

Under R2 a DESIGN that absorbed a PRD carries a What section that restates
requirements, and a PLAN that absorbed a DESIGN carries a How section that is
architecture. Both are prohibited today by the prose contract of the very format
references this work edits. The validator will pass them; the format reference
will contradict them. Nothing in the PRD requires that contradiction to be
resolved.

**Missing requirement (suggested R23):** Each format reference's
citation-not-duplication rule SHALL carve out the absorbed case, so that a
contribution section carried under R2 does not violate the content-boundary
contract of the document carrying it.

**Missing criterion:** A DESIGN carrying a What contribution section and a PLAN
carrying a How contribution section each conform to their own format reference's
content-boundary rules as written.

### 1.2 D1's adopted `R<n>` citation-resolution rule vanished (BLOCKING)

D1's chosen option adopts one mechanical backstop explicitly:

> One mechanical backstop rides along: a citation-resolution rule in `shirabe
> validate` that fails when an `R<n>` cited in a document does not resolve
> inside that document or its surviving upstream. ... It is worth having because
> it is the only depth expectation in this problem with a machine check
> available.

The decisions file carries it as a settled rider ("A citation-resolution rule
belongs in `shirabe validate`"), and the findings file records only its
*rollout* as open for the DESIGN, not the rule itself. The PRD has no
requirement for it, no criterion, and no mention in Decisions and Trade-offs --
the D1 entry there records the two-sided test and the three rejections and
silently drops the rider.

Worse, the Out of Scope bullet "a validator rule for unresolvable citations
generally" reads as though it fences this out. It does not: D4 fenced a
notice-severity rule for unresolvable document *names* (~374 pre-existing hits,
a repair campaign). D1's rule is about requirement numbers resolving against a
surviving upstream, and it fires only on the operation this work adds.

This is the guard on the single silent failure the exploration identified:

> **Absorbing a PRD orphans the chain's most-used cross-reference,
> undetectably.** ... no rule anywhere validates a requirement citation. So the
> failure is silent by construction.

**Missing requirement (suggested R24):** `shirabe validate` SHALL fail when an
`R<n>` citation in a document resolves neither within that document nor within
its surviving upstream. The rollout posture against documents already on disk is
the DESIGN's to settle.

**Missing criterion:** A DESIGN citing `R7` whose PRD was absorbed without
carrying the requirement numbering fails `shirabe validate`.

If the author has decided to drop this rider, the PRD must say so under
Decisions and Trade-offs with the reason -- not leave it to be inferred from an
Out of Scope line about a different rule.

### 1.3 The eval-suite requirement under-counts the family (BLOCKING -- answers item 5)

The decisions file records the consolidation family as four evals plus two
peripheral, with distinct obligations per eval:

- **18** `durable-artifact-floor-is-structural` -- rewrite required.
- **20** `consolidation-keep-at-unmapped-hop` -- rewrite required; its fourth
  expectation "explicitly requires absorbability to be derived from the per-type
  required-section contracts."
- **19** `consolidation-absorb-brief-into-prd` and **21**
  `consolidation-carry-check-failure-aborts-absorb` -- "each needs re-reading
  against the contribution model rather than assumed compatible."
- **7** and **17** -- "need a read, not necessarily an edit."

R18 covers only the first two: "no eval asserts the type-level absorbability
rule or the durable-artifact floor as invariants." Evals 19 and 21 assert
neither, so R18 leaves them untouched -- yet 19 asserts the *shape* of a
BRIEF-to-PRD absorb, which this work changes substantially (a contribution
section, an `absorbed:` key, a `## Status` line, the retirement guard, the R14
record). Evals 7 and 17 are not covered at all.

AC 16 mirrors the same negative shape and is trivially satisfiable by **deleting
evals 18 and 20** rather than rewriting them, which would silently drop the
suite's only coverage of the consolidation judgment. Nothing in the PRD requires
the suite to gain coverage of the behavior this work adds, though D2's
Consequences names the fixture eval that "should be built before this ships."

**R18 should read:** The skill's eval suite SHALL be updated so that no eval
asserts the type-level absorbability rule or the durable-artifact floor as
invariants; the absorb-path and carry-check-abort evals SHALL be re-evaluated
against the contribution model rather than assumed compatible; and the suite
SHALL gain at least one eval exercising a hop above BRIEF-to-PRD reaching
`absorb` and one reaching `keep`.

**Missing criterion (paired with AC 16):** The suite contains an eval in which a
hop above BRIEF-to-PRD reaches `absorb` and one in which it reaches `keep`, and
the consolidation family's eval count does not decrease.

### 1.4 D4's firewall sentence and first named follow-on (MODERATE)

D4 makes two things deliverables in their own right, and both were dropped when
the wip scope file's content moved into the durable chain.

**The firewall.** D4: "**And a firewall, stated in the scope file in these
words:** the guard is justified entirely by the DESIGN-to-PLAN hop this work
opens *forward*. It carries no retroactive commitment and produces no verdict
about any existing document. Without that sentence, corpus work rides in on the
guard's back and this decision gets re-litigated as an implementation detail."
The scope file is wip and dies; the PRD is now the durable home. R10 states the
guard with no forward-only scoping, and the Out of Scope retroactive bullet does
not tie the guard to it.

**Add to Out of Scope or as a note on R10:** R10's guard is justified entirely
by the DESIGN-to-PLAN hop this work opens forward. It carries no retroactive
commitment and produces no verdict about any document already on disk.

**The first follow-on.** D4 specifies two named follow-ons "both now fully
specified." The PRD's Out of Scope names only the second (the lifecycle
criterion, "deferred as named follow-on work"). The BRIEF-to-PRD retroactive
fold -- the one coherent retroactive operation, with a measured population of
~55 candidates, written exclusion filters, and four named gates -- is absent
entirely. The prd-format contract asks Out of Scope entries to reference future
work when applicable; this one is fully characterized and costs one sentence.

### 1.5 The re-entry case is unaddressed (MODERATE)

The decisions file and D4 disagree, and D4 wins by being the later correction.

Decisions file: "The existing `chain_skipped:` concept fires on re-entry
protection, when a settled artifact already exists, so the document is present
and can still fold or survive."

D4, alternative (e): "**That is false**: re-entry records held-back children in
`chain_skipped:` and keeps them out of `planned_chain:`, and Step 8 fires 'only
when this chain produced a durable artifact above the one that just landed.' A
pre-existing settled artifact is never judged."

This is a live runtime path, not the retroactive corpus, so the Out of Scope
retroactive bullet does not cover it. R1 says the decision is made "against the
two documents present at the hop" without scoping when the judgment fires at
all. A DESIGN or PLAN reading only the PRD could reasonably implement either
answer.

**Missing requirement (suggested R25):** The judgment SHALL fire only at a hop
where this run produced both documents. An artifact held back by re-entry
protection SHALL NOT be judged.

### 1.6 The `/work-on` naming correction and the prior-artifact contradictions (MINOR)

Two smaller items, neither blocking on its own:

- D5's Consequences: "One naming correction propagates into the design: the
  'rationale-in-code half of the `/execute` work' is `/work-on` work. ... any
  design or plan should say `/work-on` where it currently says `/execute`."
  R17's "Implementation SHALL carry a standing instruction" is altitude-correct
  and does not misdirect, but the correction is load-bearing (R14/R15 bars
  `/execute` from reading diffs, so the `/execute` placement is unimplementable)
  and survives nowhere in the durable chain. One clause in the R17 Decisions
  entry would carry it.
- The PRD names `PRD-scope-consolidation-over-skipping.md`'s R14 in References
  as requiring "the floor R1 removes," and Open Questions asks whether the
  DESIGN's Decision 9 gets amended -- but asks nothing about the PRD's R14, and
  D1's recorded correction to that same PRD ("the commit history is the recovery
  path" is false after squash-merge) reaches only Known Limitations. Either both
  contradictions get a requirement to amend, or both get an explicit
  out-of-scope line. Right now one is an open question and the other is invisible.

---

## 2. Requirements with no criterion, or with one that passes trivially

Six requirements have no acceptance criterion that would fail if the requirement
were unimplemented.

| Req | What it demands | Criterion status |
|-----|-----------------|------------------|
| R4 | Two-sided adequacy expectation; presence alone insufficient | **None.** AC 8 tests R9's abort path; AC 6 tests R5's presence check. A build that implements only presence passes every criterion -- Known Limitations concedes exactly this. |
| R7 | No gate on the verdict at any hop | **None.** AC 3 constrains the fixtures for ACs 1-2; it does not fail if a confirmation prompt or reviewer spawn is added. |
| R8 | Contribution authored *before* the carry table is built | **None.** A build that predicts the table and authors afterward passes all seventeen criteria. R8 is load-bearing: D2 declined the independent reviewer *because* R8's reorder buys its one real contribution for free. |
| R12 | Post-absorb re-validation covers survivor + referrers | **None.** (One of the four named absorb defects -- see section 3.) |
| R13 | Write-target set names every path an absorb writes or deletes | **None.** (One of the four named absorb defects -- see section 3.) |
| R17 | Standing rationale-in-code instruction on a blocking review path | **None.** This is a BRIEF Scope Boundary IN item shipping with zero criteria. D5 deliberately bounded it to "two edits, both verifiable by a reviewer reading the diff" precisely so it could be called done. |

Suggested criteria:

- R4: The two-sided criterion (too-long and too-thin) appears in the format
  reference, the drafting instruction, and the authoring artifact's jury, with a
  discriminating good/bad example pair.
- R7: No hop's verdict path introduces a human confirmation, a reviewer spawn,
  or a mode-conditional branch.
- R8: The absorb procedure cannot produce a carry table for a contribution
  section that has not been authored.
- R12: An absorb whose survivor validates but whose referrer does not is
  reverted, and both documents remain on disk.
- R13: Every path an absorb at any hop writes or deletes -- including the
  upper-hop cases -- appears in `/scope`'s enumerated write-target set, and an
  upper-hop absorb completes without a write-target violation.
- R17: The implementation phase file carries the rationale instruction, and the
  maintainer reviewer's brief names it as a blocking finding.

Criteria that pass too easily:

- **AC 16** -- satisfiable by deleting evals 18 and 20 (see 1.3).
- **AC 17** -- "`cargo test` passes and the existing golden fixtures are updated
  in the same change as any format-contract edit" is vacuous if no
  format-contract edit is made; the fixture half is conditional on a condition
  the criterion does not force.
- **AC 3** -- not a criterion about the system. It is a setup constraint on ACs
  1 and 2 and cannot independently fail.

Non-functional R19, R20, R21, R22: R21 has AC 7; R22 is partially covered by ACs
8 and 9. R19 and R20 have none, which is defensible for standing negative
constraints and is not counted against the document here.

---

## 3. The four known absorb defects (review item 4)

| Defect | Requirement | Criterion |
|--------|-------------|-----------|
| `upstream:` re-point replaces rather than splices | R11 | AC 10 -- **covered** |
| Missing retirement guard before deletion | R10 | AC 9 -- **covered** (path tier only; the weaker-match tier routing to the judging agent has no criterion) |
| Post-absorb re-validation checks only the survivor | R12 | **MISSING** |
| Write-target set does not name upper-hop absorb paths | R13 | **MISSING** |

Two of four. R12's absence matters most: D2 calls that repair an obligation
independent of everything else in the decision -- "The step-4 referrer
re-validation must ship regardless of anything else here, because nothing else
in the system can catch the failure it fixes" -- since `validate-docs.yml` is
diff-scoped and a stranded document is not a changed file. It ships here with a
requirement nobody can verify was met.

---

## 4. BRIEF Scope Boundary coverage (review item 3)

**IN list, eight items:**

| BRIEF IN item | Requirement | Verdict |
|---|---|---|
| Absorbability judgment onto the two documents | R1, R6 | covered, ACs 1-3 |
| What a survivor owes its ancestors + adequacy expectation | R2, R3, R4 | covered; R4 has no criterion |
| Format contracts: home for contribution sections **and content-boundary carve-out** | R5 only | **half missing** (1.1) |
| The four absorb defects | R10-R13 | covered; two have no criterion |
| Durable record on the default branch | R14 | covered, AC 11 |
| Trace on the surviving document | R15 | covered, ACs 12-13 |
| The two `/execute` DESIGN-survives assumptions | R16 | covered, ACs 14-15 |
| Standing rationale-in-code instruction | R17 | covered; **no criterion** |

**OUT list:** nothing is silently pulled back in. All five BRIEF exclusions
survive into the PRD's Out of Scope (retroactive corpus, strategic chain, manual
child invocation, citation index and general unresolvable-citation rule) or into
a requirement (R20 for pre-artifact judgments). R10's point query is not the
repository-wide index the BRIEF fenced out -- D4 drew that line explicitly and
the PRD keeps it. The PRD adds one exclusion the BRIEF did not carry (CI
deletion blindness), which is a narrowing with a stated reason and is fine.

One consequence worth surfacing to the DESIGN rather than counted as a gap: the
findings hold that "BRIEF-to-PRD works because the child carries, not because
the parent merges" and that "any new absorbable hop needs the same child-side
consumption block, not just a home." Whether that work exists at all depends
entirely on Open Question 2 (child at drafting time versus parent at fold time),
which the PRD correctly leaves open -- but the PLAN's decomposition will be
materially different under the two answers, and the PRD does not say so.

---

## Summary of what must change to pass

1. Requirement + criterion for the content-boundary carve-out (1.1).
2. Requirement + criterion for D1's `R<n>` citation-resolution rule, or an
   explicit recorded decision to drop it (1.2).
3. R18 rewritten to cover all four consolidation-family evals and the two
   peripheral ones, plus a positive criterion so AC 16 cannot be satisfied by
   deletion (1.3).
4. Criteria for R4, R7, R8, R12, R13, R17 (section 2).
5. D4's firewall sentence and the BRIEF-to-PRD follow-on named in Out of Scope
   (1.4).
6. A requirement scoping when the judgment fires, so the re-entry case is not
   left to the DESIGN to guess (1.5).
