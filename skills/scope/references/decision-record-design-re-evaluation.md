---
status: Accepted
decision: bet still holds; no revision warranted
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the evidence reviewed plus
  the conclusion the DESIGN-boundary re-evaluation reached.
---

<!--
Decision Record template for /scope's DESIGN-boundary re-evaluation
sub-shape. The author SHOULD NOT edit this file as a real Decision
Record — /scope populates a copy at runtime when the sub-shape
fires; see skills/scope/references/phases/phase-3-exit-finalization.md.

Filename pattern at runtime:
  docs/decisions/DECISION-design-<topic>-re-evaluation-<YYYY-MM-DD>.md

State-file fields consumed: topic (slug into filename);
referenced_artifact (the Current-lifecycle path
docs/designs/current/DESIGN-<topic>.md per the Planned-to-Current
move that precedes Acceptance, into Consequences);
chain_completed (ISO-8601, into filename date).
-->

# DESIGN-Boundary Re-Evaluation Decision Record

## Status

`{Draft|Accepted}` — set by `/scope` at finalization. Default
`Accepted`: the record IS the finalization act, no draft-and-
review interlude.

## Context

Cite at least one named evidence item the re-evaluation reviewed
— a URL, a repo file path, or a paraphrased finding (named
inline). The prose explains what triggered the re-evaluation (a
referenced contract changed, an acceptance criterion came under
question, a periodic review) and what it examined.

## Decision

bet still holds; no revision warranted

The existing DESIGN's chosen approach continues to apply; the
chain ends without re-authoring the DESIGN. Supporting prose MAY
name which architectural decisions or trade-offs the re-evaluation
re-examined and confirmed.

## Options Considered

The re-evaluation considered three options and recorded the bet
as still holding. The two REJECTED alternatives:

- **revise the DESIGN** — rejected. The existing approach
  remained warranted; no fresh Draft was authored.
- **force-abandon the chain** — rejected. Force-abandonment fits
  a stalled chain, not one whose upstream DESIGN still holds.

## Consequences

The existing DESIGN at the `referenced_artifact:` path (the
Current-lifecycle path `docs/designs/current/DESIGN-<topic>.md`)
stays at Accepted; the PLAN authored against this DESIGN
continues to apply; no PLAN regeneration is triggered by this
re-evaluation. `child_snapshots:` stays frozen on the existing
DESIGN per Decision 5, so future drift detection compares
against the same upstream the re-evaluation confirmed.

The next re-evaluation against the DESIGN boundary is triggered
when a referenced contract changes, the underlying technical
choice is challenged by new evidence, or the author re-invokes
`/scope` against the same topic and Slot 5 surfaces the DESIGN-
Accepted row.
