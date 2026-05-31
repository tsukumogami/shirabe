---
status: Accepted
decision: Draft DESIGN rejected; no DESIGN warranted at this time
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the discard commit SHA plus
  the conclusion the DESIGN-boundary rejection reached.
---

<!--
Decision Record template for /scope's DESIGN-boundary rejection
sub-shape. The author SHOULD NOT edit this file as a real Decision
Record — /scope populates a copy at runtime when /design Phase 6
Reject runs INSIDE a /scope chain and /scope observes the discard
commit via git log; see skills/scope/references/phases/phase-3-exit-finalization.md.

Filename pattern at runtime:
  docs/decisions/DECISION-design-<topic>-rejection-<YYYY-MM-DD>.md

State-file fields consumed: topic (slug into filename);
discard_commit_sha (git SHA, into Context); rejection_rationale
(free-text, into Decision); chain_completed (ISO-8601, into
filename date).
-->

# DESIGN-Boundary Rejection Decision Record

## Status

`{Draft|Accepted}` — set by `/scope` at finalization. Default
`Accepted`: the record IS the finalization act for the rejection
sub-shape.

## Context

The chain accepted the PRD-boundary, `/design` authored a Draft
DESIGN against the Accepted PRD, and the author rejected the
Draft at `/design` Phase 6. The Draft DESIGN was discarded in
commit `<discard_commit_sha>`. The prose walks the reader from
the Accepted PRD through the Draft DESIGN's approach to the
rejection; the discard-commit reference appears inline so a
future reader can navigate to the git history.

## Decision

Draft DESIGN rejected; no DESIGN warranted at this time

The Draft DESIGN `/design` produced was rejected at its Phase 6
finalization judgment; no DESIGN is warranted for this topic at
this time. The author's stated rejection rationale
(`<rejection_rationale>`) follows as 1-3 sentences explaining
the reasoning.

## Options Considered

The Phase 6 finalization judgment considered three options and
chose to reject. The two REJECTED alternatives:

- **accept the Draft DESIGN** — rejected. Acceptance would have
  routed `/plan` against a DESIGN the author concluded was
  unsound.
- **continue revising** — rejected. The author concluded the
  technical approach itself needed to change in a way revision
  could not reach.

## Consequences

- **No DESIGN on disk.** After the discard commit, no DESIGN
  exists at `docs/designs/DESIGN-<topic>.md`.
- **Chain ended at this Decision Record.** No force-materialized
  partial is produced.
- **`/plan` auto-skipped.** Any `/plan` child in `planned_chain:`
  is auto-skipped; `chain_skipped:` records it with reason
  "DESIGN-boundary rejection". Only `/plan` is affected.
- **PRD remains in place.** The existing PRD at
  `docs/prds/PRD-<topic>.md` remains at Accepted; the DESIGN-
  boundary rejection does NOT roll back the PRD-boundary.
- **Next steps.** Re-engage with a different technical approach
  (re-invoke `/scope`; the Accepted PRD is the anchor), or drop.
