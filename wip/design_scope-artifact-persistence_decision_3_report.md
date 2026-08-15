<!-- decision:start id="prior-chain-amendment" status="assumed" -->
### Decision: Whether and how to amend the falsified claims in the shipped consolidation chain

**Context**
`PRD-scope-artifact-persistence.md` R1 replaces the type-level absorbability
mapping ("is the required-section mapping total for this pair of *types*?")
that the previous, already-shipped consolidation chain used, with a per-hop
judgment against the two *documents actually present*. That earlier chain --
`DESIGN-scope-consolidation-over-skipping.md` (status `Current`) and
`PRD-scope-consolidation-over-skipping.md` (status `Done`) -- both sit durably
on `main` and both are reachable from this chain's own References section.
Two passages in them rest on the type-level premise R1 removes: DESIGN
Decision 9's rationale for leaving `/charter` alone, and the old PRD's R14
durable-artifact floor. Research surfaced a third: DESIGN Decision 8 rests on
the identical premise, and unlike Decision 9, its *conclusion* is now actually
false, not just its reasoning -- R11 of the new PRD makes DESIGN-to-PLAN
absorbable, so a `/scope` run can end with fewer than PRD+DESIGN+PLAN, exactly
what Decision 8 said was structurally impossible. A fourth, independent claim
in the old PRD's Out of Scope section ("the commit history is the recovery
path" for an absorbed document) is false after squash-merge with branch
deletion.

Neither format spec (`skills/prd/references/prd-format.md`,
`skills/design/references/lifecycle.md`) forbids editing a settled document's
prose, and nothing in `shirabe validate` compares requirement or decision
*content* across documents, so a stale claim left in place is permanently
invisible to CI. The asymmetry that matters: `BRIEF-scope-artifact-persistence.md:160`
already cites "DESIGN Decision 9 declined to add one deliberately" as a live
reference, so a reader following this chain's own reference list lands
directly on the falsified reasoning, while the `wip/` files carrying today's
correction are deleted before merge -- "the newer document governs" is not
discoverable from where a reader actually lands.

**Assumptions**
- The team executing this recommendation can land the amendment as part of, or
  alongside, this work's own PR rather than needing a separate initiative. If
  wrong, the recommended edits still stand as a named to-do for a follow-on PR.
- The two claims named in the open question, plus the recovery-path claim and
  the Decision-8 finding surfaced by this research, are the complete set of
  contradicted passages in scope for this decision. If a further pass finds
  more, those need a separate decision.

**Chosen: Append dated, scoped Amendment sections to both documents, following the repo's own precedent (commit `26465a2`, PR #224)**
Add one `## Amendment — 2026-08-14: consolidation premise superseded by
scope-artifact-persistence` section to the end of each document. Follow the
exact shape the repo already established for amending a `Done` PRD and a
`Current` DESIGN together: the amendment is appended, the original prose is
left completely untouched (not edited, not deleted), frontmatter is untouched,
and the amendment states plainly which passages it corrects and why.

Exact edits:

1. **`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`** --
   append one Amendment section, after the existing `## References` section,
   covering both Decision 8 and Decision 9:
   - State that R1 of `PRD-scope-artifact-persistence.md` replaces the
     type-level mapping test Decision 4 established, so "Decision 4 makes
     every hop above BRIEF-to-PRD unabsorbable" no longer holds.
   - Decision 8 ("The durable-artifact floor"): state that its *conclusion*
     no longer holds -- R11 of the new PRD makes DESIGN-to-PLAN absorbable, so
     a `/scope` run can now end with fewer than PRD+DESIGN+PLAN. Point to the
     new PRD/DESIGN as the current source of truth for the floor question
     rather than restating it here.
   - Decision 9 ("Whether the model generalizes to `/charter`"): state that
     its *reasoning* ("zero strategic hops are absorbable... a type-level
     mapping test") no longer describes the mechanism, but its *conclusion*
     (leave `/charter` alone) still holds, now on the grounds already present
     in the same paragraph -- no consolidation judgment exists in `/charter`
     to change, and the judgment's logic lives entirely in `/scope`'s own
     phase files, so extending it is new machinery, not a ported rule.
2. **`docs/prds/PRD-scope-consolidation-over-skipping.md`** -- append one
   Amendment section, after the existing `## Known Limitations` section:
   - R14: state that it is superseded by R1 and R11 of
     `PRD-scope-artifact-persistence.md` -- the durable-artifact floor is no
     longer structural, since DESIGN-to-PLAN can now be absorbed.
   - Out of Scope's "the commit history is the recovery path" claim: state
     that this is false under squash-merge with branch deletion (an absorbed
     document never existed on `main`), and point to the newer PRD's R20 (the
     mechanically-produced fold record with a content hash) as the actual
     answer to "what recovers an absorbed document's content."

Neither document needs a status/lifecycle transition. `Superseded` (DESIGN) or
"create a new PRD" (PRD's own guidance for fundamental changes) would falsely
declare the *whole* document replaced, when seven of nine DESIGN decisions and
all but one PRD requirement are untouched by R1.

**Rationale**
This is the smallest change that closes the actual gap: a reader following the
BRIEF's citation to Decision 9, or citing R14 from anywhere else in the future,
now finds the correction next to the claim rather than having to already know
a newer PRD exists and re-derive the contradiction themselves. It costs one
paragraph per document and touches nothing load-bearing -- no frontmatter, no
`upstream:` field, no section a validator or another skill parses
structurally. It also matches an established repo convention exactly (the
same shape was used to amend a `Done`-then-still-cited PRD and a `Current`
DESIGN together after two other post-ship defects), rather than inventing a
new correction mechanism for this repository to maintain two ways of doing the
same thing.

**Alternatives Considered**
- **Leave both untouched; newer artifacts govern by recency**: rejected
  because nothing mechanical enforces recency-as-authority, and the one
  concrete citation this decision could verify (`BRIEF-scope-artifact-persistence.md:160`)
  proves a reader lands on the falsified passage directly, not on a document
  list they'd need to sort by date first.
- **Transition to Superseded/archived (the lifecycle mechanism)**: rejected
  because it overcorrects -- it would archive or obsolete documents that are
  still correct on every axis except one premise each, discarding real,
  unaffected content (Decisions 1-7, most of the PRD's requirements) behind a
  status that tells readers not to trust any of it.
- **Amend only Decision 9; leave R14 to recency**: rejected on the evidence
  that R14 is exactly as durably wrong as Decision 9 and sits in a `Done` PRD
  this chain's own References section names -- there's no basis in the
  research for treating one as higher-traffic than the other, and the research
  found a third passage (Decision 8) with the same defect that this
  alternative would also miss entirely.
- **Rewrite the passages in place with no dated marker**: rejected because it
  erases the audit trail of what changed and when, breaks the "original prose
  is authoritative record of what was decided when" property every other
  settled document in this repo preserves, and has no precedent in this
  repository -- the one prior amendment episode found in git history
  deliberately chose append-only for this reason.

**Consequences**
Two settled documents each gain one short section; nothing else in either
document, and nothing that cites them, changes. The DESIGN stays `Current` and
the PRD stays `Done` -- no lifecycle transition, no frontmatter edit, no
`upstream:` re-point. A future reader following the BRIEF's citation to
Decision 9, or citing the old R14, finds the correction in the same file
rather than needing to discover a newer, unrelated PRD first. The change
establishes (by reuse, not invention) that this repository's answer to "a
settled document turns out to rest on a premise a later accepted document
removes" is a dated, append-only Amendment section -- worth naming explicitly
if a lifecycle or format reference ever gets written up, since it is currently
pure convention with no mechanized enforcement.
<!-- decision:end -->
