# Crystallize Decision: multi-pr-plan-decoupling

## Chosen Type

Design Doc -- one document carrying two decision sections plus the shared
mechanism they ride, following `DESIGN-roadmap-plan-standardization.md`'s shape
(a design whose Decision 6 owns the current single-pr/multi-pr rule).

## Rationale

Every signal in the Design Doc row is present and no anti-signal is. What to
build is settled -- the author stated it, and research confirmed the diagnosis
rather than revising it. How to build it was the entire open question, and the
exploration surfaced genuinely competing implementation paths (invert the
default, promote reviewability into P1, add a sibling principle, defer) that a
four-validator bakeoff had to resolve. Most decisively, the exploration *made*
architectural decisions that a future contributor needs: amending P1's status
from universal to shipped-default, rejecting the trigger-under-P1 shape on the
3.5a collision, sequencing the recording slot ahead of any preference, and
splitting cardinality from tracking as two decisions on one mechanism. Those live
in `wip/` today, which the wip-hygiene rule deletes before the branch merges.
They need a durable home.

The type is unambiguous enough that no further decision-skill run was warranted:
Design Doc scores 6 signals with zero anti-signals, and every competing type
carries at least one anti-signal and is demoted below it.

**One document, not two.** The cross-examination converged on the shape: the two
halves rest on different principles (cardinality on P1, tracking on P2) and are
independently triggered, but they share the `flag > CLAUDE.md-header > default`
resolution stack, the PLAN frontmatter, the Phase 7 creation branch, and the
`PostureClass::DraftTolerable` advisory pattern. Authoring that mechanism once
with two decision sections riding it beats either fusing the decisions or
building the same stack twice. The two GitHub issues the author anticipated fall
out of `/plan` decomposing this design, not out of splitting the design itself.

## Signal Evidence

### Signals Present

- *What to build is clear, but how to build it is not*: the author's diagnosis
  survived research intact; four validators disagreed only about mechanism.
- *Technical decisions need to be made between approaches*: four alternatives
  went through a bakeoff and cross-examination before one carried.
- *Architecture and integration questions remain*: the conditional-required-field
  mechanism does not exist in `FormatSpec`; the Draft->Active gate needs
  re-keying; `plan-to-tasks.sh` needs a third source-var scheme.
- *Exploration surfaced multiple viable implementation paths*: all four
  alternatives were viable; three were rejected on specific evidence, not on
  being unworkable.
- *Architectural decisions were made during exploration that should be on
  record*: recorded in `wip/explore_multi-pr-plan-decoupling_decision_1_report.md`
  and `_decisions.md`, both non-durable.
- *The core question is "how should we build this?"*: yes, from the first turn.

### Anti-Signals Checked

- *What to build is still unclear (route to PRD first)*: not present. The author
  stated the problem concretely and named the boundary (issues and milestones
  only for ROADMAP and multi-pr PLAN, never for single-pr or coordinated).
- *No meaningful technical risk or trade-offs*: not present. The 3.5a collision,
  the undefined ceiling, and the `#N` parsing dependency are all real.
- *Problem is operational, not architectural*: not present. This is a change to
  which principle governs a decision and where its result is recorded.

## Alternatives Considered

- **Decision Record**: scored 3 but carries the anti-signal "multiple
  interrelated decisions need a design doc." The exploration settled one decision
  and left several open (header names, ceiling metric, the `#N` scheme, the gate
  re-key). Demoted. The decision report it would have produced already exists in
  `wip/` and should be carried into the design's Considered Options rather than
  filed separately.
- **Plan**: carries the anti-signal "open architectural decisions need to be made
  first" -- the ceiling metric, the conditional-field mechanism, and the
  issueless task-extraction scheme are all undecided. Demoted. This is the right
  type for the *next* step, after the design lands.
- **No Artifact**: carries the anti-signal "any architectural, dependency, or
  structural decisions were made during exploration," which is emphatically
  present. Demoted hardest of any type.
- **PRD**: requirements were given as input rather than identified by the
  exploration, which is the PRD-vs-Design tiebreaker's distinguishing question.
  Given -> Design Doc.
- **Roadmap**: carries "technical approach for individual items is still
  debated." Demoted. This is one coherent change, not a multi-feature sequence.
- **Spike Report**: carries "the approach is known" and "exploration was broad,
  not focused on a specific technical risk." Demoted.
- **VISION**, **Rejection Record**, **Competitive Analysis**: not applicable --
  the project exists, nothing was rejected, and the repo is public.

## Deferred Types

None scored competitively. Prototype is not a fit: nothing here needs a
proof-of-concept, and the one untested assumption (whether `atomic`'s rescaled
default unit clears the 3.5a value bar) is recorded as the chosen option's
abandonment condition rather than something a prototype would settle.
