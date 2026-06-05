# Phase 2 Research: Codebase Analyst (inline, single-role)

This is an inline-research artifact. In auto-dispatched mode (the /prd skill running as a /scope-dispatched child), spawning N parallel subagents to investigate research leads would itself hit the dispatch-contract ambiguity the PRD is about. The /prd controller does the research inline against the in-worktree material the BRIEF cites and persists findings here for resume / Phase 4 review.

## Lead 1: Pattern-reference dispatch-contract section shape

### Findings

`references/parent-skill-pattern.md` (481 lines) has a clear ordering of section blocks that gesture at the dispatch contract without ever naming it as a contract:

1. **Two-Layer Contract** (lines 18-39) — names Layer 1 (semantic invariants, substrate-agnostic) and Layer 2 (reference implementation, substrate-bound). The split is what lets the pattern admit amplifier-layer substrate later. Any dispatch contract belongs to Layer 1 semantically (the contract names properties that hold across substrates) with a Layer-2 binding for the v1 mechanism.
2. **Semantic Invariants** (lines 40-77) — names I-1 through I-7. I-7 (Active Orchestration) is the existing invariant the dispatch contract operationalizes. The dispatch contract is the missing answer to "I-7 operationalizes against WHAT dispatch mechanism?"
3. **Three Exit Paths** (lines 78-112) — full-run / re-evaluation / abandonment-forced. The exit-path contract is what a dispatched child can return into; the dispatch contract specifies how parent reads that exit.
4. **Gate Vocabulary** (lines 113-153) — four gate shapes (EITHER-signal, ALWAYS, shape-dependent, Mandatory-with-auto-skip). Gates determine whether a child invocation fires; the dispatch contract specifies how it fires once the gate opens.
5. **Conditional Feeder Invocation Shape** (lines 154-206) — includes the `parent_orchestration:` sentinel discipline, which is one of the four contract elements the new section must name.
6. **Named Substitution Surfaces** (lines 207-248) — defines `storage_substrate` and `team_primitive` substitution variables. `team_primitive` is the substitution surface the dispatch mechanism choice slots into. v1's `single-team-per-leader-no-nested` value already constrains the mechanism space; the new contract section names which of the surviving mechanism options v1 uses.
7. **Team-Shape Declarator** (lines 249-298) — declares that "each parent skill declares its team shape so a parent-of-the-parent can materialize peers upfront." Critical finding: the existing declarator text describes the PARENT declaring its OWN team shape, not the CHILD declaring its team shape for the PARENT to read. The PRD must either widen this section's scope or add a paired declarator clause for children.
8. **Required SKILL.md Structural Elements** (lines 299-332) — seven elements every parent SHALL contain. Does NOT currently include a dispatch-contract reference.
9. **Team-Lead Operating Discipline** (lines 333-482) — R19 / I-7 binding. The discipline names the loop, the priority ordering, the timing table, the terminal exits. Does NOT name the dispatch mechanism it operates on.

### Implications for Requirements

The natural slot for the new dispatch-contract section is between Team-Shape Declarator (which sets up parent-side declaration) and Team-Lead Operating Discipline (which sets up the in-flight protocol). The PRD must require the section to name four contract elements: (1) dispatch mechanism, (2) pre-dispatch state, (3) observability surface, (4) hand-back contract. The PRD must also require that the existing Team-Shape Declarator section either widen to cover children or be paired with a Child-Side Team-Shape Declarator clause.

The Required SKILL.md Structural Elements list (currently 7 elements) is the grep-anchor for symmetric application across parents. The PRD MAY require an eighth structural element naming the dispatch-contract reference; alternately the PRD MAY require the contract reference to land inside an existing element (most naturally the Team-Shape declarator clause). DESIGN owns the placement.

### Open Questions

- Does the contract section live as a new top-level `## Child-Dispatch Contract` section in the pattern reference, or as a sub-section of an existing section (Team-Shape Declarator is the natural home)? DESIGN territory.
- Does the Layer-1 / Layer-2 split apply to the new section, and how? The contract's PROPERTIES are Layer 1; the v1 mechanism choice is Layer 2.

## Lead 2: Child SKILL.md team-shape declaration surface

### Findings

Searched all SKILL.md files for "Team Shape" headings (`grep -n "Team Shape"`). Results:

- `skills/scope/SKILL.md` line 43: `## Team Shape` (declares single-agent, no team)
- `skills/charter/SKILL.md` line 32: `## Team Shape` (declares single-agent, no team)
- All seven children (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`): **NO `## Team Shape` section exists.**

The Team-Shape Declarator section in `parent-skill-pattern.md` (lines 249-298) explicitly says: "Each parent skill declares its team shape so a parent-of-the-parent (the agent invoking the skill) can materialize peers upfront." The declaration shape (fixed roles vs reviewer-shaped vs variable-cardinality-worker with upper bound) is well-specified — but it's specified for **parents**, not for the **children** in a parent-skill chain.

This is a critical finding: the BRIEF's outcome states "A skill author maintaining one of the children knows, from the contract, what shape their child's `## Team Shape` section must take to be readable by the parent." But there are no Team Shape sections in any child today. Either:

(a) The contract requires children to ADD a `## Team Shape` section (greenfield), or
(b) The contract requires a DIFFERENT child-readable surface (e.g., the BRIEF/PRD-format declaration of internal team needs, declared somewhere the parent can grep — which today does not exist), or
(c) The pattern's Team-Shape Declarator section already covers this because every child IS a parent-skill (`/prd` invokes Phase-4 jury agents inline, `/design` invokes decision-researchers, `/plan` invokes decomposers); the declaration is missing not because it's a new concept but because the children's own Phase work was authored before the parent-skill pattern crystallized.

Reading the Team-Shape Declarator's "Reviewer-shaped roles vs variable-cardinality worker role types" subsection (lines 287-298), it explicitly cites `/design`'s `decision-researcher` and `/plan`'s `decomposer` as variable-cardinality worker role types — implying these children ARE recognized as team-emitting, but their declaration sections haven't been added to their SKILL.md yet. So the contract's child-side requirement is: every child that fits the team-emitting pattern MUST declare its team shape in a parent-readable section.

Specifically, the children's team-emitting status (from inspection):
- `/brief`: 2-reviewer jury (per SKILL.md description) — reviewer-shaped roles.
- `/prd`: 3-agent jury (Phase 4 per phase-4-validate.md) — reviewer-shaped roles. Plus parallel research agents in Phase 2 — variable-cardinality worker.
- `/design`: decision-researchers (one per decision question) — variable-cardinality worker. Plus reviewer jury.
- `/plan`: decomposers (one per outline) — variable-cardinality worker.
- `/vision`, `/strategy`, `/roadmap`: similar mix per their respective SKILL.md descriptions.

### Implications for Requirements

Requirements MUST bind: every child SHALL declare its team shape in a parent-readable section in its SKILL.md. The declaration MUST distinguish reviewer-shaped from variable-cardinality-worker role types with an upper bound. The PRD MUST NOT prescribe the section's exact format (heading text, ordering, frontmatter vs body) — that's DESIGN — but MUST require the declaration to be present, grep-anchorable, and complete.

The PRD MUST require that the migration covers all seven children. None of them have a Team Shape section today; all seven need one. The PRD MUST also clarify what counts as "internal child documentation" (preserved as-is) versus "contract surface" (parent-readable, format-bound by the dispatch contract).

### Open Questions

- Children that are themselves "single-agent" at the child-itself layer (analogous to `/scope` and `/charter`'s vacuous bindings) — should they declare an explicit "no team" Team Shape section, or omit it? DESIGN territory; the PRD requires presence-or-explicit-absence, format TBD.

## Lead 3: Three-passage reconciliation across `/scope` and `/charter`

### Findings

The BRIEF cites three passages that today read in tension:

1. **`/scope` SKILL.md Team Shape (line 43-64)**: "`/scope` runs as a single-agent skill in the v1 core layer — no team is spawned at the `/scope`-itself layer." Continues: "R19 (the Team-Lead Operating Discipline, semantic invariant I-7 in the pattern's invariants list) binds at the child-skill-dispatch layer rather than at the parent-itself layer."

2. **`/scope` Phase 2 (phase-2-chain-orchestration.md line 24-25)**: "Child invocation. Invoke the child via its existing input mode (topic-slug argument)."

3. **`references/parent-skill-pattern.md` R19/I-7 Team-Lead Operating Discipline (lines 333-482)**: Names the 5-step sleep-check-nudge loop, the three terminal exits (PASS / FAIL / ESCALATE), the strict priority ordering, the timing table. Says nothing about WHAT primitive carries the dispatch.

Reading the three together, the existing text already names **two layers** of binding: (a) "parent-itself layer" (vacuous in v1 — no peers at the `/scope` layer) and (b) "child-skill-dispatch layer" (the R19 discipline applies). The contract is essentially declared piecewise across the three passages: the Team Shape says where the discipline binds; Phase 2 names the input mode; R19 names the in-flight protocol. What's missing is a single section that ties them together AND names the mechanism that carries the dispatch.

`/charter` mirrors `/scope` structurally. The SKILL.md Team Shape section (lines 32-43) is symmetric to `/scope`'s. The Team-Lead Operating Discipline section in `parent-skill-pattern.md` (lines 464-482) has explicit "Binding Notes for `/charter`" naming the child-skill dispatch layer as the concrete binding — same shape as `/scope`'s.

### Implications for Requirements

Requirements MUST bind: after the contract section lands, the three passages SHALL agree. Specifically:

- The `## Team Shape` section in `/scope` and `/charter` SHALL cross-reference the new dispatch-contract section in the pattern reference, naming the contract as the source of the mechanism.
- The Phase 2 child-invocation step SHALL reference the contract section as the source of the dispatch mechanism, and SHALL NOT contradict the contract (today's "the child's existing input mode" wording reads as a per-phase interface note; the contract section absorbs that statement and the Phase 2 text becomes a back-reference).
- The R19 / I-7 Team-Lead Operating Discipline SHALL cite the contract section as the source of which dispatch mechanism the discipline binds against, removing the dispatch-mechanism ambiguity from R19.

Symmetry between `/scope` and `/charter` is the load-bearing acceptance criterion: both parents reference the contract identically, and the only per-parent variation is the names of the children they dispatch to. The contract section must apply verbatim to both, with no per-parent fork.

### Open Questions

- Per-parent override slot — does the contract need one? If `/scope` and `/charter` are both single-agent at the parent-itself layer with identical dispatch behavior at the child-dispatch layer, no per-parent override is needed in v1. A future `/work-on` that uses a different mechanism would benefit from an override slot, but that's downstream. The PRD names per-parent override slots as out-of-scope unless DESIGN finds a v1 need.

## Lead 4: Pre-dispatch, mid-flight, hand-back contract elements

### Findings

Working backwards from the BRIEF's outcome (the four things every orchestrator should be able to read off the docs), here is what already exists in the codebase versus what is missing:

**Pre-dispatch state**:
- `parent_orchestration:` sentinel block (existing, in scope state-file schema): `invoking_child`, `suppress_status_aware_prompt`, `rationale`. Documented in `references/parent-skill-pattern.md` Conditional Feeder Invocation Shape section (lines 192-206).
- State-file fields written before dispatch (existing per `/scope` SKILL.md): `boundary:`, `plan_execution_mode:`, child snapshots from prior children.
- Worktree-staleness gate output (existing per `parent-skill-worktree-discipline.md`): rebase or impact-classification or escalation outcome.

What's missing: a single statement that enumerates what the parent SHALL have written before the dispatch fires. The pieces exist; the enumeration as a contract does not.

**Observability surface during the run**:
- Filesystem under `wip/` (existing per pattern-state schema): child writes its own scratch files; parent does not read them per R14 child-isolation (`parent-skill-child-inspection.md`).
- Child durable artifact growth (existing per phase-2 chain orchestration): parent can poll `docs/<type>/<TYPE>-<topic>.md` for terminal-artifact appearance.
- Structured messages from a coordinator (UNDEFINED): only relevant if the chosen mechanism uses message-passing; existing v1 has no message-passing channel between parent and child.
- `git log` for new commits since dispatch (existing per Team-Lead Discipline step 3): used for Phase-N Reject detection.

What's missing: a contract statement that names which of these the parent IS allowed to inspect mid-run (the observability surface) and which the parent is NOT allowed to inspect (child internals, per R14). Today, R14 covers "child internals are never read"; the contract section makes the positive statement (what IS the parent's observability surface).

**Hand-back contract on completion**:
- R20 structural file-existence check (existing per phase-2 chain orchestration): parent reads child's canonical artifact path post-return.
- Frontmatter `status:` value (existing per pattern reference Lifecycle Management): parent reads it from the child's artifact.
- Git blob hash (existing per child snapshot schema): parent captures it for drift detection on resume.
- Phase-N Reject discard-commit detection (existing per phase-2 chain orchestration lines 206-247): parent reads `git log <pre_invocation_sha>..HEAD` for discard commit, captures SHA and rationale.
- Decision Records (existing per scope SKILL.md Slot 5/6 rows).

What's missing: a contract statement that enumerates the hand-back read sequence and what teardown the parent SHALL perform between dispatches (clear `parent_orchestration:` sentinel — already exists; capture child snapshot — already exists; validate — already exists). Same shape as observability — the pieces exist; the contract framing does not.

### Implications for Requirements

Requirements MUST bind: the contract section SHALL name all four contract elements with their already-existing constituent pieces as the v1 binding. The PRD does NOT introduce new constituent pieces (worktree-staleness gate, R14 isolation, R20 file-existence check, `parent_orchestration:` sentinel, child snapshot, validator pass-through, discard-commit detection are all v1-existing); the contract section simply names them under the contract heading.

The teardown discipline (clear sentinel, capture snapshot, validate, log) is in-scope for the hand-back element. The PRD must require teardown to be named as part of the hand-back contract, not relegated to an unnamed "next-child setup" phase.

### Open Questions

- Does the contract section need to forward-reference the team-construction layer choice (one team at /scope-itself vs per-child team)? The BRIEF explicitly names this as DESIGN territory. The contract should specify that the choice has a single answer (legibility requirement) without naming what that answer is.

## Summary

Inline single-role research found: (1) the natural slot for the dispatch-contract section is between Team-Shape Declarator and Team-Lead Operating Discipline in `parent-skill-pattern.md`; (2) NONE of the seven children currently have a `## Team Shape` section — the contract requires all seven to add one (greenfield migration), with format TBD by DESIGN; (3) the three in-tension passages already name "parent-itself layer" vs "child-dispatch layer" distinction — the contract section binds the latter with a single mechanism reading; (4) all four contract elements (pre-dispatch state, mechanism, observability, hand-back) have v1-existing constituent pieces; the missing artifact is the contract section that names them under one heading. The PRD requirements MUST bind the contract surface without prescribing the harness primitive, declarator format, or team-construction layer (all DESIGN territory).
