---
schema: prd/v1
status: Done
problem: |
  The parent-skill pattern v1 docs (`references/parent-skill-pattern.md`,
  `skills/scope/SKILL.md`, `skills/charter/SKILL.md`) describe parents
  (`/scope`, `/charter`) walking authors through a chain of children but
  never pin down which harness mechanism carries the parent-to-child
  dispatch. Three internally-coherent passages (Team Shape says
  "single-agent, no team spawned"; Phase 2 says "the child's existing
  input mode"; R19/I-7 describes a sleep-check-nudge discipline that
  assumes asynchronous dispatch) reach three different mechanism
  readings, and an orchestrator (human or agent) reading the docs cold
  cannot reconcile them into one reading that matches authorial intent
  across the chain.
goals: |
  An orchestrator reading the parent-skill pattern v1 docs finishes them
  with one unambiguous reading of how a parent invokes a child, named at
  the pattern layer as a single child-dispatch contract. The contract
  surfaces four elements (dispatch mechanism, pre-dispatch state,
  observability surface, hand-back contract), reads symmetrically across
  `/scope` and `/charter`, applies to all seven children via a
  parent-readable team-shape declaration in each child's SKILL.md, and
  preserves the pattern's seven semantic invariants (I-1 through I-7)
  without renumbering them. The PRD specifies the contract surface; the
  choice of harness primitive, declarator format, and
  team-construction layer is downstream DESIGN territory.
upstream: docs/briefs/BRIEF-shirabe-child-dispatch-contract.md
---

# PRD: shirabe-child-dispatch-contract

## Status

Done

## Problem Statement

shirabe's parent-skill pattern v1 ships two parents — `/scope` (tactical chain) and `/charter` (strategic chain) — that walk an author through a sequence of children: `/brief`, `/prd`, `/design`, and `/plan` under `/scope`; `/vision`, `/strategy`, and `/roadmap` under `/charter`. The pattern's contract surface is documented in `references/parent-skill-pattern.md` plus the two parents' `SKILL.md` files. What these documents do not name is the *mechanism* by which a parent invokes a child. An orchestrator (human or agent) reading the docs reaches at least three plausible mechanism readings:

- **Inline Skill-tool invocation** — the literal reading of Phase 2's "the child's existing input mode."
- **A single general-purpose subagent** — the compromise reading that splits the difference between single-agent-at-parent-layer and the asynchronous shape of R19/I-7.
- **A `TeamCreate`-backed team with coordinator and peers** — the team-aware reading of the Team-Lead Operating Discipline.

Each reading is internally coherent with one of the three passages that touch the handoff (Team Shape, Phase 2, R19/I-7); none of them is coherent with all three. The choice changes what happens during a child run — whether peer roles are available, whether the discipline has anything to observe, whether the parent's R20 file-existence check reads evidence from one agent or many — and the specific choice an orchestrator picks against authorial intent is not visible until a human reviews the run output.

The gap is pattern-level, not parent-local. `/scope` and `/charter` share the same shape and the same legibility gap. A future third parent (`/work-on` is the obvious candidate when it migrates into the pattern) would hit the same gap unless the contract is named at the pattern layer. The deeper problem is that the dispatch *contract* is not articulated as a contract: the Team Shape section reads as a declaration about parent-itself coordination; the Phase 2 step reads as a per-phase interface note; R19 reads as a behavioral spec that assumes the dispatch mechanism is known. The contract is the thing the docs are missing, even though each passage gestures at a piece of it.

Issue `tsukumogami/shirabe#150` ("docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch") is the upstream conversation that surfaced the gap. The issue's suggested fix names one possible mechanism choice; this PRD deliberately does not adopt that choice as the answer and leaves the mechanism for downstream DESIGN.

## Goals

- **Contract legibility.** An orchestrator (human or agent) reading the pattern v1 docs end-to-end reaches one unambiguous reading of the parent-child dispatch mechanism, the state established before dispatch, the observability surface during the run, and the hand-back protocol on completion.
- **Symmetric application.** The contract reads identically across `/scope` and `/charter` and applies to all seven children in their respective chains. A future third parent (e.g., `/work-on` when it migrates into the pattern) inherits the contract verbatim.
- **Invariant preservation.** The contract operationalizes the existing semantic invariants (I-1 through I-7, especially I-3 child-isolated resume and I-7 active orchestration) without renumbering them or changing their wording. The two-layer Layer-1/Layer-2 split is preserved; the contract's *properties* are Layer 1, while its v1 mechanism binding is Layer 2.
- **Pattern-level boundary.** The contract is named at the pattern layer (`references/parent-skill-pattern.md`), not duplicated per-parent. Per-parent overrides exist only in named override slots; no parent contradicts the contract.
- **Forward-compatible.** The contract framing remains stable when the amplifier-layer substrate ships (Layer 2 substitution under `team_primitive` and `storage_substrate`). v1 prose declarators stay v1; the contract does not pull forward structured-metadata declarations.

## User Stories

User stories are framed as concrete journeys — actors interacting with the contract surface — rather than role-based stories, since the artifact under specification is a contract document set rather than a feature with end users.

- **U1 — Orchestrator agent running `/scope` cold.** An orchestrator agent runs `/scope <topic>` for the first time, reads `/scope` SKILL.md end-to-end to understand the workflow, follows the Team Shape and Phase 2 references into `references/parent-skill-pattern.md`, reaches the dispatch-contract section, and finishes the docs with one mechanism reading. The agent invokes `/brief` through that mechanism and continues through the chain without the author needing to flag a mismatched reading.

- **U2 — Orchestrator agent running `/charter` cold.** A second orchestrator agent runs `/charter <topic>` for the first time and traces the same path: SKILL.md → pattern reference → dispatch-contract section. The orchestrator reaches the same mechanism reading as U1 — both parents converge on one mechanism through the same contract, not through independent best-effort interpretation.

- **U3 — Skill author maintaining a child.** A skill author maintaining one of the seven children (say `/design`) reviews the child's `## Team Shape` section and can answer two questions from the docs alone: (a) which fields in the section are read by the parent at dispatch time, and (b) which fields are internal to the child. The author can edit the child's team needs without breaking the dispatch contract by accident.

- **U4 — Reviewer evaluating a dispatch-behavior change.** A reviewer is evaluating a PR that proposes changing how `/scope` spawns its children (e.g., tightening the worktree-staleness gate, adding a new sentinel field, changing R20). The reviewer reads the contract section and can tell whether the proposed change is in-scope for the contract (so `/charter` must change symmetrically and the pattern reference must be updated) or a per-parent override (so `/charter` stays untouched). The boundary is legible.

- **U5 — Future-parent author migrating `/work-on`.** A skill author later migrating `/work-on` into the parent-skill pattern reads the contract section and inherits it verbatim — no re-deriving the mechanism, no parent-local divergence. The contract is the reference; `/work-on` references it the same way `/scope` and `/charter` do.

## Requirements

Functional requirements (R1-R8) bind what the contract surface must expose. Non-functional requirements (R9-R11) bind how the contract is applied across the codebase. Each requirement is independently testable.

### Functional Requirements

**R1 — Single dispatch-contract section at the pattern layer.** `references/parent-skill-pattern.md` SHALL contain exactly one named section that defines the parent-child dispatch contract. The section SHALL be grep-anchorable by a stable heading text, and SHALL name the contract as a contract (not as a per-phase interface note, not as a discipline-internal binding). The contract section SHALL be the single source of truth for the dispatch mechanism; other passages SHALL cross-reference it rather than re-declare it.

**R2 — Four contract elements named.** The dispatch-contract section SHALL name four contract elements, with each element identified by a stable sub-heading or equivalent grep-anchor:

- **R2.1 — Dispatch mechanism.** Which harness primitive carries each child invocation, and the relationship of that mechanism to the parent's single-agent shape, to the child's team-shape declaration, and to the R19/I-7 discipline that governs the in-flight period.
- **R2.2 — Pre-dispatch state.** What the parent SHALL have written before the dispatch fires (the `parent_orchestration:` sentinel, the relevant state-file fields, the worktree-staleness gate output), what the child's input mode receives, and what state the child can rely on being present when it begins.
- **R2.3 — Observability surface.** What the parent IS allowed to inspect mid-run (the `wip/` filesystem surface the contract permits, the child's durable artifact for terminal-artifact polling, `git log` for new commits, structured messages from a coordinator if the chosen mechanism uses one) and what the parent IS NOT allowed to inspect (child internals, per existing R14 child-isolation). The contract's positive statement of the observability surface SHALL be explicit; relying solely on R14's negative statement is insufficient. (Positive example: "the parent reads the child's durable artifact at `docs/<type>/<TYPE>-<topic>.md` for terminal-artifact polling." Negative example: "R14 prohibits the parent from reading the child's `wip/` internals.")
- **R2.4 — Hand-back contract.** What the parent reads when the child returns (the R20 structural file-existence check, the artifact's frontmatter `status:` value, the artifact's git blob hash, any Phase-N Reject discard commit detected via `git log <pre_invocation_sha>..HEAD`, any Decision Record produced), and what teardown the parent SHALL perform before the next child begins (clearing `parent_orchestration:`, capturing the child snapshot, running the validator pass-through against the child's emitted artifact via `shirabe validate`).

**R3 — Child-side team-shape declaration.** Each of the seven children (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`) SHALL declare its team shape in a parent-readable child-side declaration at a well-known per-skill location (the exact location and file format is DESIGN's choice, subject to the constraints below). The declaration SHALL distinguish reviewer-shaped roles (one peer reviews all N work items in one pass) from variable-cardinality worker role types (one peer per work item) with an upper bound, matching the cardinality-shape vocabulary the existing Team-Shape Declarator section in the pattern reference defines. The declaration SHALL be present even for children whose team is empty in v1 (the explicit "no team" declaration counts; silent omission does not). The declaration's location SHALL be chosen so that a parent reading it loads only the team-shape information into context, not the child's full operating manual.

**R4 — Three-passage reconciliation.** After the contract section lands, the three currently-in-tension passages SHALL agree:

- **R4.1 — Team Shape sections.** `/scope` SKILL.md and `/charter` SKILL.md's `## Team Shape` sections SHALL cross-reference the new dispatch-contract section in the pattern reference as the source of the dispatch mechanism. The Team Shape sections SHALL NOT independently re-state the mechanism.
- **R4.2 — Phase 2 child-invocation step.** The Phase 2 child-invocation step in `/scope`'s phase-2 reference (and `/charter`'s equivalent) SHALL cross-reference the contract section as the source of the dispatch mechanism. Today's "the child's existing input mode" wording SHALL be absorbed into the contract section's R2.1 element; the Phase 2 step becomes a back-reference.
- **R4.3 — R19/I-7 Team-Lead Operating Discipline.** The Team-Lead Operating Discipline section in `references/parent-skill-pattern.md` SHALL cite the dispatch-contract section as the source of which mechanism the discipline binds against. The discipline's posture (sleep-check-nudge, filesystem-evidence-first, PASS/FAIL/ESCALATE terminal exits, idle-pings-are-not-inbox-messages, nudge content rule, ci_outcome semantics) SHALL be preserved verbatim; only the cross-reference is added.

**R5 — Symmetric application across `/scope` and `/charter`.** Both parents SHALL reference the contract section identically: the cross-reference passages are verbatim across the two parents, with substitution permitted only for child names (`/brief`, `/prd`, `/design`, `/plan` vs `/vision`, `/strategy`, `/roadmap`) and topic-slug placeholders. Per-parent variation in mechanism wording or contract structure is prohibited. Any per-parent override of the contract SHALL exist only in a clearly-named override slot in that parent's SKILL.md; absent an override slot, the contract applies verbatim.

**R6 — Invariant preservation.** The dispatch contract SHALL preserve all seven semantic invariants (I-1 through I-7) without renumbering them and without changing their wording. The contract operationalizes I-7 (Active Orchestration) by naming the dispatch mechanism the discipline binds against; it does NOT replace, supersede, or weaken any invariant. The named-but-unsatisfied framing of I-6 (Cross-branch resume) is preserved.

**R7 — Migration of all seven children.** Every one of the seven existing children SHALL have its SKILL.md updated to add the team-shape declaration required by R3. Children that already gesture at their team needs in prose form (e.g., `/prd`'s phase-4-validate.md mentions a 3-agent jury) SHALL have those needs hoisted to the parent-readable section; the prose may remain in its existing location as internal documentation, but the parent-readable section is the contract surface. The PRD does NOT specify which children require new sections vs surfacing-existing-prose; the migration is per-child, and every child ends with a parent-readable team-shape declaration.

**R8 — Layer-1 / Layer-2 split preserved.** The dispatch-contract section SHALL identify which of its statements are Layer 1 (semantic invariants, substrate-agnostic) versus Layer 2 (reference implementation, substrate-bound). The contract's *properties* (legibility, four contract elements, symmetry, invariant preservation) are Layer 1; the v1 mechanism binding is Layer 2 and SHALL be replaceable when the amplifier-layer substrate ships. The Layer-2 binding SHALL slot into the existing `team_primitive` substitution surface; the contract SHALL NOT introduce a new substitution surface.

### Non-Functional Requirements

**R9 — Pattern-reference single-section discipline.** The dispatch-contract section SHALL be a single section in `references/parent-skill-pattern.md`, not split across multiple sections. The section MAY have sub-headings for the four contract elements (R2.1-R2.4); it SHALL NOT be split across non-adjacent top-level sections. Migrating prose from the existing Team-Shape Declarator and Team-Lead Operating Discipline sections into the contract section is permitted; duplicating it is not.

**R10 — No new pattern invariants.** The contract SHALL NOT add new pattern invariants beyond I-1 through I-7. If the contract surfaces a property that today is implicit in pattern v1, that property is named inside the contract section, not promoted to a new top-level invariant. The pattern invariants list stays frozen at seven entries.

**R11 — Forward-looking only.** The contract applies to chain runs initiated after the contract lands. Existing in-flight chain runs (a `/scope` or `/charter` run already mid-chain when the contract commits) SHALL NOT be retroactively re-shaped. The pattern docs SHALL note this scope boundary so a reader of an in-flight run's state file is not confused by the apparent contract mismatch.

## Acceptance Criteria

Each criterion is binary pass/fail. A reviewer who did not write the PRD MUST be able to verify each criterion by reading the resulting documentation, grepping for stable strings, or running the validator.

### Pattern-Level Contract Section

- [ ] **AC1 — Contract section exists.** `references/parent-skill-pattern.md` contains exactly one top-level section whose heading text contains the case-insensitive substring `dispatch contract` or `child-dispatch contract` (the exact heading wording is DESIGN's choice). Running `grep -in 'dispatch contract' references/parent-skill-pattern.md | grep '^[0-9]*:##'` returns exactly one line.

- [ ] **AC2 — Four contract elements named.** The contract section names all four elements from R2 (dispatch mechanism, pre-dispatch state, observability surface, hand-back contract). Each element is identifiable by a sub-heading (e.g., `### Dispatch Mechanism`), a bold-text leader, or an equivalent grep-anchor whose exact form DESIGN specifies. The marker shape is fixed at contract-section time and uniform across the four elements; a grep against the contract section returns four element markers.

- [ ] **AC3 — Dispatch mechanism explicit.** The contract section's mechanism element (R2.1) names exactly one harness primitive (the specific name is DESIGN's choice; the PRD requires that ONE is named, not zero and not multiple). An orchestrator reading the section can answer "what harness primitive carries the dispatch?" by quoting the section.

- [ ] **AC4 — Pre-dispatch state element enumerated.** The pre-dispatch state element names the `parent_orchestration:` sentinel, the worktree-staleness gate output, and the relevant state-file fields the parent writes before dispatching. An orchestrator can list, from the section, what state the child can rely on being present when it begins.

- [ ] **AC5 — Observability surface element enumerated.** The observability surface element names the surface the parent IS allowed to inspect mid-run (`wip/` filesystem positive statement, durable artifact polling, `git log`, structured messages if any) and explicitly references R14 child-isolation for what the parent IS NOT allowed to inspect.

- [ ] **AC6 — Hand-back contract element enumerated.** The hand-back contract element names the R20 file-existence check, the frontmatter `status:` read, the git blob hash capture, the Phase-N Reject discard-commit detection, and the teardown discipline (clear sentinel, capture snapshot, validate). An orchestrator can list, from the section, the read sequence on child return.

### Child-Side Team-Shape Declarations

- [ ] **AC7 — All seven children declare team shape.** Each of the seven child skill directories (`skills/brief/`, `skills/prd/`, `skills/design/`, `skills/plan/`, `skills/vision/`, `skills/strategy/`, `skills/roadmap/`) contains a parent-readable team-shape declaration at the well-known per-skill location DESIGN chose. The exact location, file name, and file format are DESIGN's choice; the PRD requires presence at the location uniformly across all seven children. The grep / glob marker is whichever stable path or heading DESIGN specifies in the contract section; the marker is fixed at contract-section time. Running the glob or grep DESIGN specifies returns exactly seven results — one per child. The location SHALL load only the team-shape information into a parent's context, not the child's full operating manual.

- [ ] **AC8 — Reviewer vs variable-cardinality distinction.** Each team-shape declaration that names peer roles distinguishes reviewer-shaped roles from variable-cardinality worker role types. A child with no peers in v1 explicitly declares "no team" (or equivalent); silent omission fails AC7.

- [ ] **AC9 — Upper bound for variable-cardinality roles.** Where a child declares variable-cardinality worker role types, the declaration names an upper bound for the roster (matching the existing Team-Shape Declarator section's "upper-bound roster declared in the Team Shape section" requirement).

### Three-Passage Reconciliation

- [ ] **AC10 — Team Shape sections cross-reference contract.** `/scope` SKILL.md's `## Team Shape` section and `/charter` SKILL.md's `## Team Shape` section each contain a cross-reference to the dispatch-contract section in `references/parent-skill-pattern.md`. The cross-reference text (or equivalent path-anchor) is identical between the two parents.

- [ ] **AC11 — Phase 2 references contract.** The Phase 2 child-invocation step in `/scope`'s phase-2-chain-orchestration.md (and `/charter`'s equivalent phase-2 reference) cross-references the dispatch-contract section as the source of the dispatch mechanism. Today's "the child's existing input mode" wording is either absorbed into the contract section or retained as a per-phase note that defers to the contract.

- [ ] **AC12 — R19/I-7 cites contract.** The Team-Lead Operating Discipline section in `references/parent-skill-pattern.md` (the R19/I-7 section) cites the dispatch-contract section as the source of which mechanism the discipline binds against. The discipline's posture, timing table, terminal-exit definitions, idle-pings rule, nudge content rule, and ci_outcome semantics are preserved verbatim.

### Symmetric Application

- [ ] **AC13 — Symmetric SKILL.md sections.** `/scope` and `/charter`'s SKILL.md files reference the contract identically. Diffing the contract-relevant passages (Team Shape section bodies excluding parent names; Phase 2 cross-references; pattern-reference cross-references) yields differences only in child names and topic-slug placeholders, not in mechanism wording or contract structure.

- [ ] **AC14 — Per-parent override slots named (if any).** If the contract introduces a per-parent override slot, the slot is named explicitly in the pattern reference's contract section and in the parents' SKILL.md files. If no override slot is needed for v1, the absence is explicit (e.g., a sentence in the contract section that says "v1 has no per-parent overrides").

### Invariant and Layer Preservation

- [ ] **AC15 — Invariants unchanged.** The pattern's seven semantic invariants (I-1 through I-7) appear in the pattern reference with their wording unchanged from the pre-contract state. No new invariants are added; the invariant list still has seven entries.

- [ ] **AC16 — Layer split labelled.** The contract section identifies which statements are Layer 1 (substrate-agnostic) and which are Layer 2 (substrate-bound). The Layer-2 mechanism binding slots into the existing `team_primitive` substitution surface; no new substitution surface is introduced.

- [ ] **AC17 — Forward-looking note present.** The contract section (or an adjacent passage) notes that the contract applies to chain runs initiated after the contract lands; existing in-flight runs are not retroactively re-shaped.

### Orchestrator Legibility (Acceptance Test)

- [ ] **AC18 — Cold-orchestrator test.** An orchestrator (agent or human reviewer) reading `/scope` SKILL.md and following its cross-references — pattern reference, child SKILL.md files — reaches one unambiguous reading of: (a) which harness primitive carries the dispatch, (b) what the parent writes before dispatch, (c) what the parent reads mid-run, (d) what the parent reads on child return. This criterion is judgment-based; verified by a reviewer reading the docs cold and answering each sub-question by quoting the docs.

- [ ] **AC19 — Symmetry test.** An orchestrator running `/charter` cold (per AC18 but for `/charter`) reaches the same mechanism reading as the `/scope` orchestrator. Verified by a reviewer running both reading-paths and confirming the four answers match.

- [ ] **AC20 — Reviewer-boundary test (per Journey 4).** A reviewer evaluating a hypothetical dispatch-behavior change (e.g., adding a new field to the `parent_orchestration:` sentinel) can identify, from the contract section, whether the change is contract-level (both parents change, pattern reference updated) or per-parent. Verified by a reviewer reading the contract section and classifying a sample change.

## Out of Scope

- **Choice of harness primitive.** The contract specifies that ONE primitive is named (AC3); the choice (Skill-tool inline vs single subagent vs `TeamCreate` vs another shape) is DESIGN's territory. The PRD takes no position.

- **Declarator format.** The PRD requires child team-shape declarations to be present and parent-readable (R3, AC7); the exact format (YAML frontmatter block vs structured markdown section vs prose subsection with grep-anchors) is DESIGN's territory.

- **Team-construction layer.** Whether the team is constructed once at the `/scope`-itself layer (a parent-spanning team that handles all four children) or per-child-dispatch (a fresh team per child invocation) is one of the two readings the BRIEF explicitly names as DESIGN-decidable. The PRD requires that ONE answer is named (it follows from the dispatch mechanism choice in AC3); the answer itself is DESIGN.

- **Harness substrate changes.** The contract names which primitives the dispatch uses; it does not redesign `TeamCreate`, `SendMessage`, the team-lead discipline's internal primitives, or any other substrate-layer concern.

- **Amplifier-layer team-shape declarator.** The pattern's v1 Team-Shape Declarator section already notes that team-emitting parents will declare structured metadata when the amplifier-layer substrate ships. This PRD does not pull that forward — v1 prose declarators stay v1. The Layer-2 substitution surface (`team_primitive`) is preserved as the migration path.

- **`/work-on` migration into the parent-skill pattern.** `/work-on` is a separate parent that depends on workflow-composition substrate that does not exist yet. The contract this PRD specifies WILL apply to `/work-on` when it migrates (R5, U5), but the migration itself is downstream feature work.

- **Pattern-invariant renumbering.** The seven semantic invariants (I-1 through I-7) stand as ratified. The contract operationalizes I-7 (Active Orchestration) but does not change the invariant's wording or add new invariants (R6, R10, AC15).

- **Re-litigating which mechanism is "right" against the others at the abstract level.** The PRD requires that ONE mechanism is named with its rationale (the rationale lives in DESIGN). The PRD does not stake out the comparison; the decision rationale and trade-off analysis live in the downstream design document.

- **Net-new child skills.** The seven children that exist today are the children the contract applies to (R7). New children added later inherit the contract; their authoring is not in scope.

- **Migration of existing chain runs in flight.** Forward-looking only per R11. A `/scope` or `/charter` run that pre-dates the contract continues to work as it does today.

- **Editing the workspace or shirabe CLAUDE.md files** to surface the contract at the user-facing layer. The contract is internal to the pattern's documentation; user-facing CLAUDE.md text is a separate concern that downstream DESIGN may revisit if needed, but this PRD does not commit to.

- **Section placement in the pattern reference.** Whether the contract section lands between Team-Shape Declarator and Team-Lead Operating Discipline (the natural slot Phase 2 research identified), or elsewhere, is DESIGN's choice. The PRD requires a single section (R9, AC1); the placement is downstream.

## Known Limitations

- **L1 — The contract is documentation, not enforcement.** The contract section names the dispatch mechanism, but nothing programmatic prevents a future PR from contradicting it. Symmetry and invariant preservation rely on reviewer discipline plus the existing pattern-validator (which catches structural violations but cannot catch wording drift). This limitation is consistent with the rest of the pattern's contract surface — the pattern reference is documentation; the validator is the structural floor.

- **L2 — Cold-orchestrator legibility is judgment-based.** AC18 / AC19 / AC20 are not grep-checkable acceptance criteria; they require a reviewer to read the docs cold and report on legibility. The PRD accepts this trade-off because the BRIEF's outcome ("one unambiguous reading") is fundamentally a legibility property, not a structural one. Grep-checkable AC1-AC17 provide the structural floor; the cold-orchestrator tests provide the legibility verification.

- **L3 — Children-as-parents asymmetry.** The pattern's Team-Shape Declarator section was written assuming the declaring entity is itself a parent skill. Children that dispatch peers (`/prd`'s 3-agent jury, `/design`'s decision-researchers) are effectively parents in their own right but are being treated as children-of-`/scope` here. The contract may need to acknowledge that some children are themselves team-emitting, in which case their team-shape declaration is simultaneously: (a) parent-readable by `/scope`, and (b) a parent-skill team-shape declaration in its own right. This is a known framing tension; DESIGN may resolve it by either treating these children as pattern-conforming parents directly, or by introducing a "nested parent" concept.

## Decisions and Trade-offs

- **D1 — Contract section at pattern layer, not duplicated per parent.** Research (Lead 1 in Phase 2) identified that `references/parent-skill-pattern.md` is the natural home for the contract because both parents reference it and a future third parent will too. Alternatives: (a) duplicate the contract in each parent's SKILL.md (rejected — symmetry becomes a maintenance burden, and `/work-on` would have to re-derive); (b) put the contract in a new top-level reference (rejected — fragments the pattern surface; readers would need to find the new file). Decision: single section in the existing pattern reference, per R1 / R9.

- **D2 — All seven children get a team-shape declaration even if their team is empty.** Research (Lead 2) found that no child currently has a `## Team Shape` section. The choice is between requiring ALL seven (greenfield migration) or requiring only the team-emitting ones (smaller migration). Alternatives: (a) require only team-emitting children to declare (rejected — the contract becomes conditional on team-emitting-ness, which is itself ambiguous since `/prd`'s Phase 4 jury makes every PRD-emitting run team-emitting); (b) require all seven (chosen — uniform declaration, no per-child boolean for the parent to evaluate). Decision: R3 requires all seven, with explicit "no team" allowed for vacuous cases. AC7 / AC8 enforce.

- **D3 — The PRD does not name the harness primitive.** The user explicitly cautioned against pre-deciding the mechanism. Research (Lead 3) found that the existing three-passage tension is the symptom of the missing contract, not the missing mechanism — the contract can be specified without the mechanism choice. Alternative: pre-commit to a mechanism in the PRD (rejected — user constraint, and DESIGN's trade-off analysis is the right place for the choice). Decision: AC3 requires ONE primitive is named (in DESIGN); the PRD requires the contract surface, not the choice.

- **D4 — Layer-1 / Layer-2 split preserved, not extended.** Research (Lead 1) found that the existing two-layer contract is what lets the pattern admit amplifier-layer substrate later. The contract's properties are Layer 1; the v1 mechanism is Layer 2. Alternative: collapse the layer split for the contract (rejected — would break the amplifier-layer migration path). Decision: R8 / AC16 preserve the split.

- **D5 — DESIGN-deferred decisions surfaced explicitly.** Three decisions the PRD intentionally defers to DESIGN, captured here so DESIGN has a clear backlog: (a) **per-parent override slot in v1** — R5 / AC14 require the absence-or-presence to be explicit, but the PRD does not commit to which; if the chosen mechanism applies identically across `/scope` and `/charter`, no override is needed, otherwise DESIGN introduces one; (b) **child team-shape declaration format granularity** — R3 names presence + reviewer-vs-variable-cardinality distinction + upper bound, but the exact format (heading text, frontmatter key, sub-section shape) is DESIGN's call; (c) **forward-looking note placement** — R11 / AC17 require the note exists, but whether it lives in the contract section, in a separate scope sub-section, or in the parents' SKILL.md files is DESIGN's. Each is deferred deliberately; none changes the PRD's requirements.

## References

- Upstream BRIEF: `docs/briefs/BRIEF-shirabe-child-dispatch-contract.md`.
- Pattern source the contract reconciles: `references/parent-skill-pattern.md` (Team-Shape Declarator section, Team-Lead Operating Discipline / I-7 section).
- Tactical-chain parent: `skills/scope/SKILL.md` (Team Shape section, Phase 2 cross-references in `references/phases/phase-2-chain-orchestration.md`).
- Strategic-chain parent: `skills/charter/SKILL.md`.
- Pattern companion references: `references/parent-skill-state-schema.md`, `references/parent-skill-resume-ladder-template.md`, `references/parent-skill-child-inspection.md`.
- Upstream conversation: GitHub issue `tsukumogami/shirabe#150` ("docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch").
