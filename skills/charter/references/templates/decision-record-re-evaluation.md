---
status: Accepted
decision: bet still holds; no revision warranted
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the evidence reviewed plus
  the conclusion the re-evaluation reached.
---

<!--
This file is a Decision Record template for the re-evaluation
sub-shape of `/charter`'s re-evaluation exit. The author SHOULD
NOT edit this file as a real Decision Record — `/charter`
populates a copy at runtime when the re-evaluation sub-shape fires
(see `skills/charter/references/phases/phase-finalization.md` for
the orchestration logic that selects this template).

Filename pattern at runtime:
  docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md

The `DECISION-` prefix matches shirabe's `<TYPE>-<name>.md`
convention (alongside BRIEF-, DESIGN-, PLAN-, PRD-, ROADMAP-,
STRATEGY-, VISION-).

Runtime population reads from `/charter`'s state file at
`wip/charter_<topic>_state.md` per the schema documented in
`skills/charter/references/phases/phase-state-management.md`.
Fields consumed when populating this template:

- `topic` — slug substituted into the filename.
- `referenced_strategy` — path to the existing STRATEGY this
  re-evaluation references (substituted into the Consequences
  section's "existing STRATEGY at <path>" prose).
- `chain_completed` — ISO-8601 timestamp; the `<YYYY-MM-DD>` in
  the filename derives from its date portion.
-->

# Re-Evaluation Decision Record

## Status

`{Draft|Accepted}` — set by `/charter` at finalization. Default
`Accepted` for re-evaluation Decision Records (the record IS the
finalization act; there is no draft-and-review interlude for
re-evaluation sub-shape records in the v1 flow).

## Context

Cite at least one named evidence item that the re-evaluation
reviewed. MUST be present — a re-evaluation Decision Record with
no named evidence in Context is a contract violation (the
re-evaluation must have considered SOMETHING concrete to record
"bet still holds"). Acceptable evidence shapes:

- A URL to a published source the re-evaluation considered.
- A file path within the repo (or a related repo) that the
  re-evaluation read.
- A paraphrased finding from a conversation, briefing, or
  internal investigation (the paraphrase is named; the source is
  cited by description).

The Context section's prose explains what triggered the
re-evaluation (new evidence, periodic review, etc.) and what the
re-evaluation examined. The named evidence items appear inline in
the prose.

## Decision

bet still holds; no revision warranted

The Decision section states this conclusion as a complete
sentence: the existing STRATEGY's bet continues to hold; no
revision is warranted; the chain ends without re-authoring the
STRATEGY. The prose MAY add 1-2 supporting sentences explaining
why the bet holds (e.g., naming which Bet-Specific Falsifiability
claims were re-examined and confirmed), but the canonical
statement is the load-bearing content.

## Options Considered

The re-evaluation considered three options and chose to record
the bet as still holding. The two REJECTED alternatives are named
explicitly so a future reader sees the reasoning trail:

- **revise the STRATEGY** — rejected. A revision would have
  produced a fresh Draft STRATEGY superseding the existing one;
  the re-evaluation concluded the existing Draft remained
  warranted, so no revision was authored. (Prose explains why
  revision was rejected in this specific case — typically: the
  evidence supports the existing bet rather than contradicting
  it.)
- **force-abandon and rewrite** — rejected. Force-abandonment
  would have removed the existing STRATEGY and started a fresh
  chain; this would be appropriate when the existing bet is
  refuted, not when it holds. (Prose explains why
  force-abandonment was rejected — typically: the evidence does
  not refute the bet; it confirms it.)

Both alternatives MUST appear in the Options Considered section
with their rejection rationale. Their absence makes the Decision
Record incomplete per AC12.

## Consequences

The re-evaluation Decision Record has two halves of consequence
prose: what remains in effect, and what triggers the next
re-evaluation.

**What remains in effect.** The existing STRATEGY at the
`referenced_strategy:` path stays at its current status
(Accepted or Active); no ROADMAP regeneration is triggered. Any
downstream PRDs, designs, or plans that cite the STRATEGY
continue to apply. The re-evaluation produced a Decision Record;
it did NOT produce a new STRATEGY draft.

**What triggers the next re-evaluation.** Name the conditions
under which a future `/charter` invocation against this topic
SHOULD re-open the question — typically a falsifiability-claim
flip (a Bet-Specific Falsifiability condition the STRATEGY named
becomes triggered) or a stated review cadence. The
next-re-evaluation prose is not a binding schedule; it is
guidance for the human reader (or a future agent) to recognize
when re-opening would be warranted.

The Consequences section also explicitly cites the existing
STRATEGY by path (substituted from the state file's
`referenced_strategy:` field at runtime) so the reader can
navigate from the Decision Record back to the STRATEGY it
references.
