---
status: Accepted
decision: Draft STRATEGY rejected; no STRATEGY warranted
rationale: |
  1-3 sentence justification referencing the body's Context or Options
  sections (~250-character soft cap). Names the discard commit SHA plus
  the conclusion the rejection reached.
---

<!--
This file is a Decision Record template for the rejection
sub-shape of `/charter`'s re-evaluation exit. The author SHOULD
NOT edit this file as a real Decision Record — `/charter`
populates a copy at runtime when the rejection sub-shape fires
(see `skills/charter/references/phases/phase-finalization.md` for
the orchestration logic that selects this template; specifically,
the rejection sub-shape fires when `/strategy` Phase 5 Reject
runs INSIDE a `/charter` chain).

Filename pattern at runtime:
  docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md

The `DECISION-` prefix matches shirabe's `<TYPE>-<name>.md`
convention (alongside BRIEF-, DESIGN-, PLAN-, PRD-, ROADMAP-,
STRATEGY-, VISION-).

Runtime population reads from `/charter`'s state file at
`wip/charter_<topic>_state.md` per the schema documented in
`skills/charter/references/phases/phase-state-management.md`.
Fields consumed when populating this template:

- `topic` — slug substituted into the filename.
- `discard_commit_sha` — git SHA of the commit `/strategy` Phase
  5 Reject produced when discarding the Draft STRATEGY;
  substituted into Context section's discard-commit reference.
- `rejection_rationale` — free-text rejection rationale the
  author entered at `/strategy` Phase 5 Reject; substituted into
  the Decision section.
- `chain_completed` — ISO-8601 timestamp; the `<YYYY-MM-DD>` in
  the filename derives from its date portion.
-->

# Rejection Decision Record

## Status

`{Draft|Accepted}` — set by `/charter` at finalization. Default
`Accepted` for rejection Decision Records (the record IS the
finalization act for the rejection sub-shape).

## Context

Cite the chain's discovery (what `/charter` learned during Phase
1) and the Draft STRATEGY's framing (the bet `/strategy` produced
that the author then rejected). The Context section's prose
walks the reader from the chain's starting question through the
Draft STRATEGY's conclusion to the rejection.

The Context section MUST reference the discard commit SHA
(populated at runtime from the state file's `discard_commit_sha:`
field). The reference shape: cite the SHA inline in the prose
(e.g., "the Draft STRATEGY was discarded in commit
`<discard_commit_sha>`") so a future reader can navigate from
the Decision Record to the git history showing the discard.

## Decision

Draft STRATEGY rejected; no STRATEGY warranted

The Decision section states this conclusion as a complete
sentence: the Draft STRATEGY `/strategy` produced was rejected at
its Phase 5 finalization judgment; no STRATEGY is warranted for
this topic at this time. The author's stated rejection rationale
(populated at runtime from the state file's `rejection_rationale:`
field) follows as 1-3 sentences explaining the reasoning the
author entered when picking Reject.

The combination of the canonical conclusion plus the author's
rationale gives a future reader both the structural decision
("rejected; no STRATEGY warranted") and the substantive reasoning
behind it.

## Options Considered

The Phase 5 finalization judgment considered three options and
chose to reject the Draft STRATEGY. The two REJECTED alternatives
are named explicitly so a future reader sees the reasoning
trail:

- **accept the Draft** — rejected. Accepting would have
  transitioned the Draft STRATEGY to Accepted; the author
  concluded the Draft's bet was wrong or unwarranted enough that
  acceptance would have committed to a flawed strategic
  framing. (Prose explains why acceptance was rejected — based
  on the rejection rationale above.)
- **revise instead of reject** — rejected. A revision would have
  produced a new Draft STRATEGY superseding the current one; the
  author concluded the question itself was flawed enough that a
  revision would have re-encoded the same flawed framing rather
  than producing a sound new bet. (Prose explains why revision
  was rejected — typically: the topic itself needs to be
  reframed before a STRATEGY can be authored, or the strategic
  question turns out to not warrant a STRATEGY at all.)

Both alternatives MUST appear in the Options Considered section
with their rejection rationale. Their absence makes the Decision
Record incomplete per AC13.

## Consequences

The rejection Decision Record describes the post-rejection state
of the topic:

- **No STRATEGY on disk.** The Draft STRATEGY was discarded in
  the commit identified by `discard_commit_sha:` (substituted
  from the state file); no STRATEGY exists at
  `docs/strategies/STRATEGY-<topic>.md` after the rejection.
  Future `/charter` invocations against the same topic see no
  STRATEGY at the published path.
- **Chain discarded.** The `/charter` chain that produced the
  rejected Draft ended at this Decision Record; any in-progress
  wip/ intermediates `/strategy` was working with were cleaned
  up by `/strategy`'s discard procedure. The chain does NOT
  produce a force-materialized partial; the rejection is a
  deliberate finalization, not a bail.
- **Next steps for the strategic question.** Name the paths
  available to the author for re-engaging the strategic
  question. Typical options: open the question again later when
  the underlying conditions change; reframe the question (the
  topic slug itself may need to change to capture a different
  framing); drop the question entirely if the rejection reveals
  the question itself was unwarranted. The Consequences section
  picks the path that fits the rejection rationale and prose
  about that path.

The Consequences section is the place where the rejection's
durable evidence lands — what changed on disk (no STRATEGY), what
the chain history records (the discard commit), and what the
author's next strategic move could be.
