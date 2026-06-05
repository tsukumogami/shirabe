# Plan Analysis: shirabe-child-dispatch-contract

## Source Document
Path: docs/designs/DESIGN-shirabe-child-dispatch-contract.md
Status: Accepted
Input Type: design

## Scope Summary
Reconcile the parent-skill pattern's three in-tension passages by landing a single `## Dispatch Contract` section in `references/parent-skill-pattern.md`, propagating cross-references symmetrically from `/scope` and `/charter`, and creating parent-readable `team.yaml` declarations under each of the seven child skill directories. Documentation-only change; introduces no new code paths.

## Components Identified
- **C1 — Pattern reference `## Dispatch Contract` section.** New top-level section in `references/parent-skill-pattern.md` between `## Team-Shape Declarator` and `## Required SKILL.md Structural Elements`. Five labelled sub-sections (Dispatch Mechanism, Pre-Dispatch State, Observability Surface, Hand-Back Contract, Child Team-Shape Declaration) plus opening/closing paragraphs. ~110 lines.
- **C2 — Child team-shape declarations.** Seven new `skills/<name>/team.yaml` files (for `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`), each ~10 lines, with content derived from the verified migration table in DESIGN. Each child's SKILL.md also gets a brief `## Team Shape` section pointing at the sibling `team.yaml`. Two edits per child × seven children = 14 atomic file changes.
- **C3 — Parent cross-references.** `/scope` SKILL.md and `/charter` SKILL.md each get an updated `## Team Shape` section adding a closing cross-reference to the new `## Dispatch Contract` section. The cross-reference text is verbatim between the two parents.
- **C4 — Phase 2 cross-references (asymmetric).** `/scope`'s Phase 2 reference has one attachment point (`## Child Invocation`); `/charter`'s Phase 2 reference has four (`## /vision Invocation Rule (R4)`, `## /comp Invocation Rule (R5 + R12)`, `## /strategy Invocation Rule (R6)`, `## /roadmap Invocation Rule (R7)`). The cross-reference TEXT is identical across all five attachment points.
- **C5 — R19/I-7 Binding Notes rewording.** `references/parent-skill-pattern.md`'s `### Binding Notes for /charter` subsection (lines 464-481) is reworded; a new `### Binding Notes for /scope` subsection is added symmetrically. Discipline content preserved verbatim; only binding-layer description changes.
- **C6 — State-schema annotation.** `references/parent-skill-state-schema.md` gets a one-paragraph annotation under the `parent_orchestration:` block schema cross-referencing the new contract section. No schema fields change.

## Implementation Phases (from design)

### Phase A — Land the contract section (single PR)

1. Add `## Dispatch Contract` section to `references/parent-skill-pattern.md` with the five sub-sections specified in Component 1 (Dispatch Mechanism, Pre-Dispatch State, Observability Surface, Hand-Back Contract, Child Team-Shape Declaration).
2. Reword `### Binding Notes for /charter` and add `### Binding Notes for /scope`.
3. Annotate `references/parent-skill-state-schema.md`.

This is one atomic edit to the pattern reference. After this phase, the contract section exists and is the single source of truth, but the parents and children do not yet cross-reference it.

### Phase B — Update parent SKILL.md and Phase 2 cross-references (asymmetric)

1. Update `skills/scope/SKILL.md` `## Team Shape` section.
2. Update `skills/charter/SKILL.md` `## Team Shape` section.
3. Update `skills/scope/references/phases/phase-2-chain-orchestration.md` `## Child Invocation` section.
4. Update `skills/charter/references/phases/phase-2-chain-orchestration.md` per-child Invocation Rule sections (four attachment points).

Five attachment points total. Cross-reference text is identical.

### Phase C — Migrate child team-shape declarations

Seven children. For each: (1) create `skills/<name>/team.yaml`; (2) add a brief `## Team Shape` section to `skills/<name>/SKILL.md`.

### Phase D — Validator extension (DEFERRED)

`shirabe validate` learns to parse `skills/<name>/team.yaml`, check schema conformance, verify cross-references, optionally verify the declared shape matches actual team construction at runtime. NOT decomposed into issues; captured as future work in Consequences.

### Phase E — Forward-looking note

Already included in Phase A's contract-section closing paragraph (Decision 6). No separate edit; no separate issue.

## Success Metrics

From DESIGN's Consequences (positives the contract delivers):
- Single mechanism reading replaces three (AC18 / AC19 / AC20 satisfied)
- R14 child-isolation strengthened (explicit positive statement)
- R19/I-7 binding clarified (binds inside whichever skill spawns a team)
- Amplifier-layer migration path preserved (Layer-1 / Layer-2 split labelled)
- Children's existing team behavior codified, not introduced
- Layer-collision question for issue #150 resolved explicitly

Grep-checkable acceptance from PRD AC1-AC17:
- AC1: exactly one `dispatch contract` heading in pattern reference
- AC2-AC6: four contract elements named with stable markers
- AC7: glob `skills/*/team.yaml` returns exactly 7 files
- AC8-AC9: each declaration distinguishes reviewer vs worker; upper_bound for worker
- AC10-AC12: cross-references land at 5 attachment points across `/scope` and `/charter`
- AC13: cross-reference TEXT identical at all 5 attachment points
- AC14: per-parent override absence explicit
- AC15: I-1 through I-7 wording unchanged
- AC16: Layer-1 / Layer-2 split labelled
- AC17: forward-looking note present

## External Dependencies

- **None code-level.** Documentation-only change.
- **Soft dependency on `team_primitive` substitution surface.** The contract labels its Layer-2 binding under the existing `team_primitive` substitution surface in the pattern reference; no new substitution surface is introduced. The pre-existing surface is unchanged.
- **No CI changes required.** Phase D's validator extension is deferred; no shirabe validate changes needed for Phases A-C.

## Verified Migration Table (ground truth for Phase C)

The DESIGN's Component 2 table is the canonical source. Each row was verified against a specific child phase reference file. Phase C decomposers MUST use this table verbatim; they MUST NOT re-derive rosters from skim-reading SKILL.mds.

| Child | parent_layer.peers | child_layer.peers | Source |
|---|---|---|---|
| `/brief` | `[]` | `content-quality-reviewer` (reviewer, phase-4-validate), `structural-format-reviewer` (reviewer, phase-4-validate) | `skills/brief/references/phases/phase-4-validate.md` |
| `/prd` | `[]` | `completeness-reviewer` (reviewer, phase-4-validate), `clarity-reviewer` (reviewer, phase-4-validate), `testability-reviewer` (reviewer, phase-4-validate) | `skills/prd/references/phases/phase-4-validate.md` |
| `/design` | `[]` | `decision-researcher` (worker, upper_bound: 9, phase-2-execution); `security-researcher` (reviewer, phase-5-security); `architecture-reviewer` (reviewer, phase-6-final-review); `security-reviewer` (reviewer, phase-6-final-review) | `skills/design/references/phases/phase-2-execution.md`, `phase-5-security.md`, `phase-6-final-review.md` |
| `/plan` | `[]` | `decomposer` (worker, upper_bound: 20, phase-4-agent-generation) | `skills/plan/references/phases/phase-4-agent-generation.md` (note: `/review-plan` is a child invocation, not a peer) |
| `/vision` | `[]` | `thesis-quality-reviewer`, `content-boundary-reviewer`, `section-guidance-reviewer` (all reviewer, phase-4-validate) | `skills/vision/references/phases/phase-4-validate.md` |
| `/strategy` | `[]` | `bet-quality-reviewer`, `altitude-reviewer`, `structural-format-reviewer` (all reviewer, phase-4-validate) | `skills/strategy/references/phases/phase-4-validate.md` |
| `/roadmap` | `[]` | `theme-coherence-reviewer`, `sequencing-and-dependency-reviewer`, `annotation-and-boundary-reviewer` (all reviewer, phase-4-validate) | `skills/roadmap/references/phases/phase-4-validate.md` |

If a decomposer believes the table is wrong for a specific child, escalate to /scope rather than overriding silently.
