---
status: Accepted
decision: Draft BRIEF rejected; no BRIEF warranted at this time
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the discard commit SHA plus
  the conclusion the BRIEF-boundary rejection reached.
---

<!--
Decision Record template for /scope's BRIEF-boundary rejection
sub-shape. The author SHOULD NOT edit this file as a real Decision
Record — /scope populates a copy at runtime when /brief Phase 5
Reject runs INSIDE a /scope chain and /scope observes the discard
commit via git log; see skills/scope/references/phases/phase-3-exit-finalization.md.

Filename pattern at runtime:
  docs/decisions/DECISION-brief-<topic>-rejection-<YYYY-MM-DD>.md

State-file fields consumed: topic (slug into filename);
discard_commit_sha (git SHA, into Context); rejection_rationale
(free-text, into Decision; /brief's discard commit carries no body,
so the rationale is the one the hop recorded with `outcome: rejected`);
chain_completed (ISO-8601, into filename date).
-->

# BRIEF-Boundary Rejection Decision Record

## Status

`{Draft|Accepted}` — set by `/scope` at finalization. Default
`Accepted`: the record IS the finalization act for the rejection
sub-shape.

## Context

The chain's Phase 1 discovery framed the topic, `/brief` drafted
a BRIEF against that framing, and the author rejected the Draft at
`/brief` Phase 5. The Draft BRIEF was discarded in commit
`<discard_commit_sha>`. The prose walks the reader from the
chain's starting question through the Draft BRIEF's framing to
the rejection; the discard-commit reference appears inline so a
future reader can navigate to the git history.

## Decision

Draft BRIEF rejected; no BRIEF warranted at this time

The Draft BRIEF `/brief` produced was rejected at its Phase 5
approval; no BRIEF is warranted for this topic at this time. The
author's stated rejection rationale (`<rejection_rationale>`)
follows as 1-3 sentences explaining the reasoning.

## Options Considered

The Phase 5 approval considered three options and chose to
reject. The two REJECTED alternatives:

- **accept the Draft BRIEF** — rejected. Acceptance would have
  routed downstream children against a framing the author
  concluded was wrong or unwarranted.
- **request changes** — rejected. The author concluded the
  problem itself, not the draft's wording, needed to change.

## Consequences

- **No BRIEF on disk.** After the discard commit, no BRIEF exists
  at `docs/briefs/BRIEF-<topic>.md`.
- **Chain ended at this Decision Record.** No force-materialized
  partial is produced.
- **Downstream children auto-skipped.** The `/prd`, `/design` and
  `/plan` children in `planned_chain:` are auto-skipped;
  `chain_skipped:` records them as `{child, reason}` entries with
  reason `brief-boundary-rejection`, the vocabulary member for a
  rejection at the BRIEF boundary.
- **Next steps.** The author may re-open the topic with a
  reframed problem, reuse the same topic slug after rethinking,
  or drop the question entirely. The Consequences prose names
  the path that fits the rejection rationale.
