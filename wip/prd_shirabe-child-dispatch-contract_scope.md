# /prd Scope: shirabe-child-dispatch-contract

## Problem Statement

The parent-skill pattern v1 documents (`references/parent-skill-pattern.md`, `skills/scope/SKILL.md`, `skills/charter/SKILL.md`) describe parents (`/scope`, `/charter`) walking authors through a chain of children (`/brief`, `/prd`, `/design`, `/plan` tactically; `/vision`, `/strategy`, `/roadmap` strategically) but never pin down which harness mechanism carries the parent-to-child dispatch. Three internally-coherent passages (Team Shape says "single-agent, no team spawned"; Phase 2 says "the child's existing input mode"; R19/I-7 describes a sleep-check-nudge discipline that assumes asynchronous dispatch) reach three different mechanism readings (inline Skill-tool, single subagent, `TeamCreate`-backed team), and an orchestrator (human or agent) reading the docs cold cannot reconcile them into one reading that matches authorial intent across the chain.

## Initial Scope

### In Scope

- Requirements binding what the parent-child dispatch contract MUST surface (legibility, declarator format, pre-dispatch state, observability surface, hand-back contract, teardown discipline) without prescribing which harness primitive carries the dispatch.
- Requirements binding the invariants the contract preserves from pattern v1 (I-1 through I-7, especially I-3 child-isolated resume and I-7 active orchestration; the four gate shapes; the three exit paths; the two-layer Layer-1/Layer-2 split).
- Requirements binding which SKILL.md surfaces declare what (every child's parent-readable team-shape declaration; `/scope` and `/charter` symmetric contract reference; the pattern reference's single dispatch-contract section).
- Requirements binding the migration path for the two existing parents and seven existing children — what edits land where, what stays untouched.
- Acceptance criteria an implementer can test for: e.g., an orchestrator reading `/scope` SKILL.md reaches one unambiguous mechanism reading; each child's SKILL.md declares its parent-readable team shape in a grep-able section; the pattern reference contains a single section that names the dispatch contract; `/scope` and `/charter` reference the same contract section identically.

### Out of Scope

- The choice of harness primitive (Skill-tool inline vs single subagent vs `TeamCreate` vs another shape). The PRD specifies the contract; DESIGN picks the mechanism.
- The declarator format choice (YAML frontmatter block vs structured markdown section vs prose subsection with grep-anchors).
- Whether the team is constructed once at the `/scope`-itself layer or per-child-dispatch — both readings remain open for DESIGN.
- Changes to the underlying harness substrate (`TeamCreate`, `SendMessage`, the team-lead discipline's primitives) — the contract names which primitives are used; it does not redesign them.
- The amplifier-layer team-shape declarator (Layer 2 / `team_primitive` substitution). v1 prose-declarator form stays; the structured-metadata path remains a known migration.
- The `/work-on` migration into the pattern. A future third parent inherits the contract verbatim, but its migration is downstream feature work.
- Pattern-invariant renumbering. The seven invariants I-1 through I-7 stand as ratified; the contract operationalizes I-7 without changing its wording.
- Authoring net-new children. The seven children that exist today are the children the contract applies to.
- Migration of existing in-flight chain runs. Forward-looking only.
- Editing workspace or shirabe CLAUDE.md to surface the contract at the user-facing layer.

## Research Leads

1. **Pattern-reference dispatch-contract section shape**: where in `references/parent-skill-pattern.md` the dispatch contract section should land (between Team-Shape Declarator and Team-Lead Operating Discipline is the natural slot — both adjacent sections gesture at the contract without naming it), what four contract elements it MUST name (mechanism, pre-dispatch state, observability surface, hand-back), and how the section interacts with the Layer 1 / Layer 2 split.
2. **Child SKILL.md team-shape declaration surface**: today only the two parents have `## Team Shape` sections; none of the seven children do. The contract requires children to expose a parent-readable team-shape surface. What fields must be present (peer-role names, cardinality shape: fixed vs reviewer-shaped vs variable-cardinality-worker with upper bound), what is internal to the child versus contract-load-bearing, and what is the migration path for the seven children.
3. **Three-passage reconciliation across `/scope` and `/charter`**: the "single-agent at the parent-itself layer" statement, the "child's existing input mode" wording in Phase 2, and the R19/I-7 discipline cross-reference must agree once the contract section exists. Requirements must bind what each of the three passages says after reconciliation, what cross-references each must add, and how the per-parent overrides slot (if any) is named.
4. **Pre-dispatch, mid-flight, hand-back contract elements**: enumeration of what the parent writes before dispatch (sentinel, state-file fields, worktree-staleness gate output), what the parent observes mid-run (`wip/` filesystem, child status file, structured messages from a coordinator if the mechanism uses one), and what the parent reads back on return (R20 structural file-existence check, frontmatter `status:`, git blob hash, Phase-N Reject discard commit, Decision Records).

## Coverage Notes

- The BRIEF's `## References` section pre-resolves passage citations. The PRD can lean on the BRIEF for grounding without re-deriving it.
- The PRD must NOT prescribe the mechanism, the declarator format, or the team-construction layer. These are DESIGN-territory and named explicitly as out-of-scope above.
- Acceptance criteria should be grep-checkable where possible (e.g., "every child's SKILL.md contains a `## Team Shape` heading" is grep-testable; "an orchestrator reaches one unambiguous reading" is judgment-testable and must be staged via concrete sub-criteria — section presence, cross-reference targets, contract-section field enumeration).
- The contract is pattern-level (per the BRIEF's outcome). Symmetry across `/scope` and `/charter`, plus inheritance by a future `/work-on`, must be explicit in the requirements.
