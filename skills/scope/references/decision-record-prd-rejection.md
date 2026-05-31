---
status: Accepted
decision: Draft PRD rejected; no PRD warranted at this time
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the discard commit SHA plus
  the conclusion the PRD-boundary rejection reached.
---

<!--
Decision Record template for /scope's PRD-boundary rejection
sub-shape. The author SHOULD NOT edit this file as a real Decision
Record — /scope populates a copy at runtime when /prd Phase 4
Reject runs INSIDE a /scope chain and /scope observes the discard
commit via git log; see skills/scope/references/phases/phase-3-exit-finalization.md.

Filename pattern at runtime:
  docs/decisions/DECISION-prd-<topic>-rejection-<YYYY-MM-DD>.md

State-file fields consumed: topic (slug into filename);
discard_commit_sha (git SHA, into Context); rejection_rationale
(free-text, into Decision); chain_completed (ISO-8601, into
filename date).
-->

# PRD-Boundary Rejection Decision Record

## Status

`{Draft|Accepted}` — set by `/scope` at finalization. Default
`Accepted`: the record IS the finalization act for the rejection
sub-shape.

## Context

The chain's Phase 1 discovery framed the topic, `/prd` authored
a Draft PRD against that framing, and the author rejected the
Draft at `/prd` Phase 4. The Draft PRD was discarded in commit
`<discard_commit_sha>`. The prose walks the reader from the
chain's starting question through the Draft PRD's framing to
the rejection; the discard-commit reference appears inline so a
future reader can navigate to the git history.

## Decision

Draft PRD rejected; no PRD warranted at this time

The Draft PRD `/prd` produced was rejected at its Phase 4
finalization judgment; no PRD is warranted for this topic at
this time. The author's stated rejection rationale
(`<rejection_rationale>`) follows as 1-3 sentences explaining
the reasoning. The combination of the canonical conclusion plus
the author's rationale gives the reader both the structural
decision and the substantive reasoning.

## Options Considered

The Phase 4 finalization judgment considered three options and
chose to reject. The two REJECTED alternatives:

- **accept the Draft PRD** — rejected. Acceptance would have
  routed downstream children against a PRD the author concluded
  was wrong or unwarranted.
- **continue revising** — rejected. The author concluded the
  question or framing needed to change before any PRD could be
  authored.

## Consequences

- **No PRD on disk.** After the discard commit, no PRD exists at
  `docs/prds/PRD-<topic>.md`.
- **Chain ended at this Decision Record.** No force-materialized
  partial is produced.
- **Downstream children auto-skipped.** Any `/design` or `/plan`
  children in `planned_chain:` are auto-skipped; `chain_skipped:`
  records them with reason "PRD-boundary rejection".
- **Next steps.** The author may re-open the topic with a
  reframed question, reuse the same topic slug after rethinking,
  or drop the question entirely. The Consequences prose names
  the path that fits the rejection rationale.
