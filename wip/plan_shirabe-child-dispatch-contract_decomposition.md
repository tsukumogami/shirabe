---
design_doc: docs/designs/DESIGN-shirabe-child-dispatch-contract.md
input_type: design
decomposition_strategy: horizontal
strategy_rationale: "Documentation reconciliation with clear sequenced phases (A → B,C); no e2e flow to skeleton through. Phase A creates the cross-reference target; Phases B and C land symmetric edges to it."
confirmed_by_user: false
issue_count: 13
execution_mode: single-pr
---

# Plan Decomposition: shirabe-child-dispatch-contract

## Strategy: Horizontal

The DESIGN's Implementation Approach names Phases A, B, C, D, E (with D deferred and E folded into A). Phase A lands the contract section in the pattern reference; Phases B and C land cross-references pointing at it. The slicing follows the natural phase boundaries and within each phase splits along file/attachment-point granularity.

**Why horizontal over walking skeleton.** This is documentation reconciliation, not feature implementation. There is no runtime pipeline to exercise end-to-end; the deliverable is text on disk. Walking skeleton would force an artificial e2e-stub issue; horizontal lets each issue stand as a focused, reviewable doc change.

**Why 13 issues.** The 7 children in Phase C are mutually independent and each child's two edits (team.yaml + SKILL.md Team Shape section) are tightly coupled — splitting them would create trivial half-issues. Phase A's three sub-edits each touch a distinct reference file and can land independently once the contract section exists. Phase B splits along the two parents' asymmetric Phase 2 structures (one attachment point in /scope, four in /charter — but all four in /charter touch the same file, so they combine).

## Issue Outlines

### Issue 1: docs(parent-skill-pattern): add Dispatch Contract section

- **Type**: standard
- **Complexity**: critical
- **Goal**: Land the `## Dispatch Contract` section in `references/parent-skill-pattern.md` between `## Team-Shape Declarator` and `## Required SKILL.md Structural Elements`, with five labelled sub-sections (Dispatch Mechanism, Pre-Dispatch State, Observability Surface, Hand-Back Contract, Child Team-Shape Declaration), an opening paragraph naming the contract as a contract, and a closing paragraph carrying the Layer-1/Layer-2 split label, the no-per-parent-override-in-v1 statement, and the R11 forward-looking note.
- **Section**: DESIGN Component 1 + Decision 1 + Decision 2's v1 runtime-read semantics note + Decision 4 + Decision 6
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: None

### Issue 2: docs(parent-skill-pattern): rework Binding Notes for /charter and add Binding Notes for /scope

- **Type**: standard
- **Complexity**: testable
- **Goal**: Reword the existing `### Binding Notes for /charter` subsection (lines 464-481 of pre-edit `references/parent-skill-pattern.md`) to reflect that R19/I-7 binds inside the child against the child's own peers (not at the child-skill-dispatch layer); add a new `### Binding Notes for /scope` subsection symmetrically. Discipline content (sleep-check-nudge loop, terminal exits, timing table, idle-pings rule, nudge content rule, ci_outcome semantics) preserved verbatim — only the binding-layer description changes.
- **Section**: DESIGN Component 5
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 3: docs(parent-skill-pattern): annotate state-schema with dispatch-contract cross-reference

- **Type**: standard
- **Complexity**: simple
- **Goal**: Add a one-paragraph annotation under the `parent_orchestration:` block schema in `references/parent-skill-state-schema.md` noting that the block is the pre-dispatch state element of the dispatch contract, with a cross-reference to the new `## Dispatch Contract` section. No schema fields change.
- **Section**: DESIGN Component 6
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 4: docs(scope,charter): cross-reference Dispatch Contract from parent Team Shape sections

- **Type**: standard
- **Complexity**: testable
- **Goal**: Add a closing cross-reference sentence to `skills/scope/SKILL.md`'s `## Team Shape` section and to `skills/charter/SKILL.md`'s `## Team Shape` section, both pointing at the new `## Dispatch Contract` section in `references/parent-skill-pattern.md`. The cross-reference text is VERBATIM between the two parents (only parent name and child names differ). Use `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` form to match the idiom both files already use.
- **Section**: DESIGN Component 3
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 5: docs(scope): cross-reference Dispatch Contract from Phase 2 Child Invocation

- **Type**: standard
- **Complexity**: testable
- **Goal**: Add a leading cross-reference sentence to the `## Child Invocation` section of `skills/scope/references/phases/phase-2-chain-orchestration.md`, pointing at the new `## Dispatch Contract` section as the source of the dispatch mechanism. Existing "the child's existing input mode" wording is preserved; the cross-reference is additive.
- **Section**: DESIGN Component 4 (/scope side)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 6: docs(charter): cross-reference Dispatch Contract from Phase 2 per-child Invocation Rules

- **Type**: standard
- **Complexity**: testable
- **Goal**: Add a leading cross-reference sentence to each of the four per-child Invocation Rule sections in `skills/charter/references/phases/phase-2-chain-orchestration.md`: `## /vision Invocation Rule (R4)`, `## /comp Invocation Rule (R5 + R12)`, `## /strategy Invocation Rule (R6)`, `## /roadmap Invocation Rule (R7)`. The cross-reference TEXT is IDENTICAL across all four attachment points and identical to Issue 5's /scope text. Per-child Invocation Rule content (conditional invocation logic for /charter) is preserved; the cross-reference is additive.
- **Section**: DESIGN Component 4 (/charter side)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 7: docs(brief): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/brief/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing `content-quality-reviewer` (cardinality reviewer, phase phase-4-validate) and `structural-format-reviewer` (cardinality reviewer, phase phase-4-validate). Add a brief `## Team Shape` section to `skills/brief/SKILL.md` cross-referencing `./team.yaml` with the v1-not-parsed-at-dispatch-time clarifier per Decision 2. Source: `skills/brief/references/phases/phase-4-validate.md`. USE THE VERIFIED MIGRATION TABLE FROM DESIGN COMPONENT 2 VERBATIM.
- **Section**: DESIGN Component 2 (/brief row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 8: docs(prd): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/prd/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing `completeness-reviewer`, `clarity-reviewer`, `testability-reviewer` (all cardinality reviewer, phase phase-4-validate). Add a brief `## Team Shape` section to `skills/prd/SKILL.md` cross-referencing `./team.yaml`. Source: `skills/prd/references/phases/phase-4-validate.md`. USE THE VERIFIED MIGRATION TABLE VERBATIM.
- **Section**: DESIGN Component 2 (/prd row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 9: docs(design): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/design/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing four entries: `decision-researcher` (cardinality worker, upper_bound 9, phase phase-2-execution), `security-researcher` (cardinality reviewer, phase phase-5-security), `architecture-reviewer` (cardinality reviewer, phase phase-6-final-review), `security-reviewer` (cardinality reviewer, phase phase-6-final-review). Add a brief `## Team Shape` section to `skills/design/SKILL.md` cross-referencing `./team.yaml`. Sources: `phase-2-execution.md`, `phase-5-security.md`, `phase-6-final-review.md`. USE THE VERIFIED MIGRATION TABLE VERBATIM (this is the most complex roster — do not deviate).
- **Section**: DESIGN Component 2 (/design row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 10: docs(plan): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/plan/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing exactly one entry: `decomposer` (cardinality worker, upper_bound 20, phase phase-4-agent-generation). Add a brief `## Team Shape` section to `skills/plan/SKILL.md` cross-referencing `./team.yaml`. Source: `skills/plan/references/phases/phase-4-agent-generation.md`. Per DESIGN, the Phase 6 invocation of `/review-plan` is a CHILD invocation (not a peer) and MUST NOT appear in `child_layer.peers`. USE THE VERIFIED MIGRATION TABLE VERBATIM.
- **Section**: DESIGN Component 2 (/plan row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 11: docs(vision): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/vision/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing `thesis-quality-reviewer`, `content-boundary-reviewer`, `section-guidance-reviewer` (all cardinality reviewer, phase phase-4-validate). Add a brief `## Team Shape` section to `skills/vision/SKILL.md` cross-referencing `./team.yaml`. Source: `skills/vision/references/phases/phase-4-validate.md`. USE THE VERIFIED MIGRATION TABLE VERBATIM.
- **Section**: DESIGN Component 2 (/vision row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 12: docs(strategy): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/strategy/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing `bet-quality-reviewer`, `altitude-reviewer`, `structural-format-reviewer` (all cardinality reviewer, phase phase-4-validate). Add a brief `## Team Shape` section to `skills/strategy/SKILL.md` cross-referencing `./team.yaml`. Source: `skills/strategy/references/phases/phase-4-validate.md`. USE THE VERIFIED MIGRATION TABLE VERBATIM.
- **Section**: DESIGN Component 2 (/strategy row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

### Issue 13: docs(roadmap): add team.yaml and Team Shape section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/roadmap/team.yaml` declaring `parent_layer.peers: []` and `child_layer.peers` listing `theme-coherence-reviewer`, `sequencing-and-dependency-reviewer`, `annotation-and-boundary-reviewer` (all cardinality reviewer, phase phase-4-validate). Add a brief `## Team Shape` section to `skills/roadmap/SKILL.md` cross-referencing `./team.yaml`. Source: `skills/roadmap/references/phases/phase-4-validate.md`. USE THE VERIFIED MIGRATION TABLE VERBATIM.
- **Section**: DESIGN Component 2 (/roadmap row)
- **Milestone**: shirabe-child-dispatch-contract
- **Dependencies**: Issue 1

## Execution Mode Selection

`execution_mode: single-pr` (locked by /scope state file's `plan_execution_mode: single-pr`).

Rationale: all 13 issues land in `tsukumogami/shirabe` (single repo); no merge gates between issues (each issue is an independent doc edit; Issue 1 must land before Issues 2-13 read the cross-reference target, but within a single branch they can land as sequential commits without separate PR boundaries); not a roadmap input. Default to single-pr per Phase 3 procedure; no hard constraint forces multi-pr.

In single-pr mode: Phase 4 produces structured outlines (no full issue bodies); Phase 7 writes them into the PLAN doc's Issue Outlines section; no GitHub issues or milestone are created; PLAN status stays at Draft.
