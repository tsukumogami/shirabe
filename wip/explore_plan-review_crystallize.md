# Crystallize Decision: plan-review

## Chosen Type
Design Doc

## Rationale

What to build is clear — an adversarial plan review skill that replaces Phase 6 in /plan,
callable standalone or as a sub-operation, analogous to how /decision is called by /design.
How to build it is the open question: the verdict artifact schema, two-tier execution model,
loop-back protocol mechanics, and AC discriminability heuristics all require technical decisions
that a design doc captures and records for future implementers.

## Signal Evidence

### Signals Present
- What to build is clear, how to build it is not: framework categories (A-D) are defined but the skill's phases, verdict artifact structure, and two-tier execution model are open.
- Technical decisions between approaches: delete review artifact on loop-back vs. keep it with Phase 7 gated on verdict; fast-path (single agent inside /plan) vs. full adversarial (multi-agent standalone); flag AC failures only vs. generate replacement ACs.
- Architecture and integration questions remain: /plan Phase 6 replacement interface, loop-back protocol (which wip/ artifacts to delete per target phase), verdict artifact YAML schema consumed by /plan resume logic.
- Multiple viable implementation paths surfaced: delete-vs-gate for Phase 7, two execution tiers.
- Architectural decisions made during exploration that should be on record: loop-back target mapping (design contradiction → Phase 1, coverage/atomicity → Phase 3, AC quality → Phase 4, dependency → Phase 5); /decision as structural analogue; two-consumer problem scoped to /plan only.
- Core question is "how should we build this?"

### Anti-Signals Checked
- What to build is still unclear: not present — the "what" is well-defined.
- No meaningful technical risk or trade-offs: not present — multiple significant trade-offs identified.
- Problem is operational, not architectural: not present.

## Alternatives Considered

- **PRD**: Ranked lower because requirements were provided as input before exploration started (Issue #7 defined the scope and key design decisions); a PRD would recapture what's already known.
- **Plan**: Ranked lower — no design doc exists yet and architectural decisions are still open; a plan can't sequence work that hasn't been decided.
- **No artifact**: Ranked lower — architectural decisions were made during exploration that should be on record, and others will implement from this doc.

## Deferred Types
None identified.
