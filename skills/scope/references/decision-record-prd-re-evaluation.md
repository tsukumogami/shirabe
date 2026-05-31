---
status: Accepted
decision: bet still holds; no revision warranted
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the evidence reviewed plus
  the conclusion the PRD-boundary re-evaluation reached.
---

<!--
Decision Record template for /scope's PRD-boundary re-evaluation
sub-shape. The author SHOULD NOT edit this file as a real Decision
Record — /scope populates a copy at runtime when the sub-shape
fires; see skills/scope/references/phases/phase-3-exit-finalization.md.

Filename pattern at runtime:
  docs/decisions/DECISION-prd-<topic>-re-evaluation-<YYYY-MM-DD>.md

State-file fields consumed: topic (slug into filename);
referenced_artifact (existing PRD path, into Consequences);
chain_completed (ISO-8601, into filename date).
-->

# PRD-Boundary Re-Evaluation Decision Record

## Status

`{Draft|Accepted}` — set by `/scope` at finalization. Default
`Accepted`: the record IS the finalization act, no draft-and-
review interlude.

## Context

Cite at least one named evidence item the re-evaluation reviewed
— a URL, a repo file path, or a paraphrased finding (named
inline). A Decision Record with no named evidence is a contract
violation; the re-evaluation must have considered something
concrete to record "bet still holds". The prose explains what
triggered the re-evaluation (new evidence, periodic review,
downstream signal) and what it examined.

## Decision

bet still holds; no revision warranted

The existing PRD's requirements continue to apply; the chain ends
without re-authoring the PRD. Supporting prose MAY name which
acceptance-criteria flips were checked and confirmed unchanged.

## Options Considered

The re-evaluation considered three options and recorded the bet
as still holding. The two REJECTED alternatives:

- **revise the PRD** — rejected. The existing PRD remained
  warranted; no fresh Draft was authored.
- **force-abandon the chain** — rejected. Force-abandonment fits
  a stalled chain, not one whose upstream PRD still holds.

## Consequences

The existing PRD at the `referenced_artifact:` path stays at
Accepted; downstream DESIGN and PLAN artifacts citing the PRD
continue to apply; `child_snapshots:` stays frozen on the
existing PRD per Decision 5, so future drift detection compares
against the same upstream the re-evaluation confirmed.

The next re-evaluation against the PRD boundary is triggered when
an acceptance-criterion flip occurs or the author re-invokes
`/scope` against the same topic and Slot 5 surfaces the PRD-
Accepted row. The next-re-evaluation prose is guidance, not a
binding schedule.
