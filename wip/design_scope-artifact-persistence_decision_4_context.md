# Decision Context: What replaces the type-level first stage of the consolidation judgment?

## Question

Under R1, absorbability stops being a property of the artifact *types*, so the
consolidation judgment's Stage 1 (a mapping-table lookup asking whether the
downstream type's required sections have a home for every required section of
the upstream type) has nothing left to decide. What, if anything, occupies that
position in the procedure?

## Complexity

critical (Tier 4 — full path, phases 0-6)

## Mode

`--auto`. Never block on the author; record assumptions instead.

## Constraints (settled, not re-litigable)

1. **The verdict is the judging agent's call.** No reviewer, no human
   confirmation, no mode-conditional gate. Both rival advocates withdrew their
   own alternatives during the D2 decision. (PRD R12)
2. **Nothing judges before the artifact it is about exists.** This killed the
   author-chosen entry altitude and still binds. (PRD R28)
3. **The consolidation judgment remains the only mechanism that reduces the
   artifact set.** A mechanism whose only possible effect is to force `keep`
   does not count as a second mechanism. (PRD R27)
4. **DESIGN-to-PLAN must be absorbable.** (PRD R11)
5. **R2 scoping:** the judgment fires only at a hop where *this run* produced
   both documents; an artifact held back by re-entry protection is not judged.
6. **R30 fail-safe:** the absorb procedure fails toward `keep` at every decision
   point this work adds, and the replaced first stage is named as one of them.
7. **R29:** documents already on disk validate unchanged; nothing added emits on
   a document declaring no absorption.
8. **R25:** the state-file schema must stop documenting absorbability as a
   question about the required-section mapping.

## Known Options (from the parent's framing)

- **(a) Dissolution.** Stage 1 disappears; the judgment becomes a single content
  question (Stage 2) plus the move (Stage 3).
- **(b) Precondition.** Stage 1 survives but stops being about types: it becomes
  an eligibility check — does this run own both documents (R2), is the
  downstream able to receive a contribution section at all.
- **(c) Mechanical pre-filter.** Stage 1 becomes a cheap gate whose only two
  outputs are "proceed to the content question" and "keep", preserving the
  fail-toward-keep property without reading both bodies.
- **(d) Something else.**

## What must also be settled

- Where the R2 ownership check reads its inputs, and how `planned_chain:` /
  `chain_skipped:` / `child_snapshots:` interact with it.
- What "fails toward `keep`" means for the *replaced* stage, concretely enough
  that the PRD criterion "a hop whose first stage cannot reach a verdict leaves
  both documents on disk" is implementable.
- What `consolidation_judgments[].absorbable` becomes (R25).
- What the Durable-Artifact Floor section in `phase-1-discovery.md` becomes: it
  currently instructs maintainers not to add a guard because "its condition
  cannot hold," and that condition now holds.

## Background

### The mechanism today

`skills/scope/references/phases/phase-2-chain-orchestration.md`, "Consolidation
Judgment", is step 8 of an eight-step per-child loop. It runs after the
validator pass-through clears and "only when this chain produced a durable
artifact above the one that just landed." Three stages:

- **Stage 1 — Absorbability.** Look the hop up in a three-row mapping table.
  BRIEF-to-PRD: Yes. PRD-to-DESIGN: No. DESIGN-to-PLAN: No. "When the mapping is
  not total, the only available verdict is `keep`. Record it with the reason
  naming the unmapped sections and stop."
- **Stage 2 — Judgment.** Read both bodies. Does the upstream do work the
  downstream does not?
- **Stage 3 — Carry check and absorb.** Itemize where each upstream required
  section landed; any `carried: false` aborts to `keep`; then re-point
  `upstream:`, `git rm`, re-validate.

### Verified evidence

**The mapping table's provenance claim is false as stated.** The table says its
verdicts "are derived from the per-type required-section contracts in
`crates/shirabe-validate/src/formats.rs`, not enumerated by hand." Read against
the source: `formats.rs` holds `FormatSpec { required_sections: Vec<String> }`
and nothing else relevant. Brief's list is `[Status, Problem Statement, User
Outcome, User Journeys, Scope Boundary]`; PRD's is `[Status, Problem Statement,
Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope]`. There is
no mapping structure anywhere in `crates/` — grep for `User Outcome` outside
`formats.rs` returns only test fixtures. Every semantic edge in the table (User
Outcome→Goals, User Journeys→User Stories, Scope Boundary→Requirements-in-list
*plus* Out-of-Scope-out-list) is authored prose, not derived data. The table also
silently drops `Status` from the Brief's five required sections without saying
so. So the table is hand-enumerated with a false provenance claim attached — the
re-derivation instruction it carries ("If a format ever grows a section,
re-derive the table rather than trusting this snapshot") has never been runnable.

**The procedure has never executed.** All 35 PRDs with an `upstream:` point at
their same-topic BRIEF; no BRIEF has ever been deleted. Both times the one
absorbable hop was reached, the carry check failed on User Journeys — including
on this very chain. Every path below the verdict is untested.

**The validator is not an obstacle to a home.** FC04 requires each name in a
format's ordered `required_sections` to appear as an H2; extra H2 sections are
unconstrained for design, prd and plan. A DESIGN can carry a Requirements
section today without failing anything.

**The state schema encodes the deleted model.** `state-schema.md` annotates
`absorbable: true` with `# is the required-section mapping total?`, and states
"A `keep` entry carries `hop`, `absorbable`, `verdict`, and `finding`."

**The Floor section's instruction.** `phase-1-discovery.md` §"The
Durable-Artifact Floor" reasons: the chain always writes four documents, the
judgment can only absorb where the mapping is total, no hop above BRIEF-to-PRD
qualifies, so the smallest reachable set is PRD+DESIGN+PLAN. It then says a run
leaving nothing behind "is therefore not reachable through `/scope` at all," and
closes: "Do not add a guard for this. Its condition cannot hold, and a check that
can never fire teaches the next maintainer that the case is possible." R1 and R11
make the condition hold, so both the premise and the instruction are falsified.

**R2's current surface.** Step 8 already carries the scoping in prose: "Skipped
when this chain produced no artifact above the current one." Phase 1 writes
`planned_chain:` (the full chain minus re-entry-held children) and
`chain_skipped:` (held-back children with reason
`settled-artifact-at-canonical-path-reentry-protection`). Held-back children are
kept out of `planned_chain:`. Phase 1 also captures initial `child_snapshots:`
for pre-existing durable artifacts it discovered — which is the surface that
distinguishes "this run wrote it" from "it was already here."

### The contribution model this decision sits inside

Each artifact type declares exactly one contribution (R3). A survivor carries an
absorbed ancestor's contribution as a single fixed-heading section placed after
`## Status` (R4, R5), accumulating transitively in chain order (R6), under a
two-sided adequacy criterion (R7), declared in frontmatter and enforced by
`shirabe validate` (R8, R9). Because a home can always be written, absorbability
stops being a property of the types — which is exactly why Stage 1's question
has no content left.
