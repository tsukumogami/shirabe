# Design Summary: shirabe-comp-skill

## Input Context (Phase 0)

**Source PRD:** docs/prds/PRD-shirabe-comp-skill.md (transitioned
from Accepted to In Progress at Phase 0).

**Upstream BRIEF:** docs/briefs/BRIEF-shirabe-comp-skill.md (Accepted).

**Problem (implementation framing):** Operationalize the three
architectural alternatives the PRD deferred — Phase 4 jury rubric
content, validate-CLI visibility-check field shape, and
format-content porting strategy — and produce a concrete file
inventory the downstream /plan can decompose into atomic
implementation issues.

## Decisions (Phase 2-3)

**Decision 1 — Visibility-check field shape:** Generic `Private bool`
field on `FormatSpec` consumed by a shared new check
`checkPrivateOnly` emitting error code R9. Chosen over (a)
comp/v1-specific check function and (c) `RequiresVisibility
[]string` enum field. Declarative at type-definition site; minimum
surface; forward-compatible for a future second consumer.

**Decision 2 — Phase 4 jury reviewer rubrics:** Three rubrics
specified verbatim in the design, each scoped to a distinct
failure mode (marketing-language detection for competitive-
framing; dimension-rigor and external-sourcing for content-
quality; six mechanical checks for structural-format). Rubric
text lands verbatim in `phase-4-validate.md`; tunability surface
lives there.

**Decision 3 — Format-content authoring strategy:** Structural
skeleton authored fresh per the shirabe convention (matching
strategy/brief/prd-format.md). Content guidance synthesized from
PRD requirements, sibling format references, and the existing
workspace-level COMP format reference consulted as authoring
input only — no verbatim port. Workspace-level reference stays
in place; `comp-format.md` becomes canonical.

## Security Review (Phase 5)

**Outcome:** Option 2 (document considerations).

**Summary:** Feature operates on local markdown files only; no
network I/O. Three dimensions warrant attention: R9 fail-closed
semantics (mirrors VISION/STRATEGY precedent), Phase 4 reviewer
prompt-injection mitigations (transfer from /strategy security
review), and external References discipline (no SSRF risk
because no URL-fetching; private-path-leak risk caught by
content-quality reviewer rubric). Transition script argument
handling mirrors brief's defensive practices.

## Current Status

**Phase:** Complete (Proposed for orchestrator commit).
**Last Updated:** 2026-05-31

## Artifact

`docs/designs/DESIGN-shirabe-comp-skill.md` — status Proposed,
schema design/v1.

Implementation Issues table present (9 issues with dependency
diagram). Ready for /plan.
