# Crystallize Decision: execute-friction

## Chosen Type

Design Doc (routes to /design)

## Rationale

The friction log GIVES the desired behaviors (the "what"): land into an existing
branch/PR, pause for review before finalization, guarantee docs coverage, emit a
template-conformant PR, keep report-upstream artifacts durable. What the
exploration produced is the "how" — and the how carries four genuine technical
decisions between approaches, plus several architectural choices that must be on
record before the work can be sequenced into issues. That is the Design Doc
signal profile exactly.

## Signal Evidence

### Signals Present (Design Doc — 6, no anti-signals)

- **What to build is clear, but how is not**: the friction is concrete and
  scoped (A+B+C+D); the open questions are all mechanism — which user surface for
  F1, what pause-state shape for F3, what detection contract for F4, what guard
  home for F5b.
- **Technical decisions need to be made between approaches**: F1 has four surface
  options (generalize override / `--branch`-`--pr` flag / home-PR auto-detect /
  formalize `/scope→/execute` handoff); F4 has prose-grep vs. a structured
  `user_visible_surface` field; F5b has a guard-home choice in `shirabe validate`.
- **Architecture/integration questions remain**: the `/scope→/execute` branch-PR
  handoff seam; the pause-state interaction with the DRAFT-before-READY cascade;
  the `/execute` closed-write-target security envelope constraining F6/F7.
- **Multiple viable implementation paths surfaced**: see F1's four.
- **Architectural decisions were made during exploration that should be on
  record**: the F5 a/b split, F4's ownership landing on `/plan` (not `/execute`)
  for a metadata-only-contract reason, the F7 reframe as convention.
- **Core question is "how should we build this?"**: yes.

### Anti-Signals Checked

- *What to build is still unclear (→ PRD)*: NOT present — the friction log is the
  requirements input.
- *No meaningful technical risk/trade-offs*: NOT present — every cluster has a
  real design choice.
- *Problem is operational, not architectural*: NOT present — the changes touch
  the skill state machine, the cascade weld, and the security envelope.

## Alternatives Considered

- **Plan**: demoted (2 anti-signals — "technical approach is still debated" and
  "open architectural decisions need to be made first"). No upstream artifact
  exists to decompose. Becomes the right artifact AFTER the design settles the
  four decisions.
- **PRD**: demoted. Requirements were GIVEN (friction log), not IDENTIFIED during
  exploration — the PRD-vs-Design tiebreaker resolves to Design Doc.
- **Decision Record**: demoted — this is multiple interrelated decisions, not a
  single one; a design doc is the right container.
- **No Artifact**: demoted — decisions were made that future contributors need on
  record; multiple skills/files change.

## Scope note for the design

Primary: the `/execute` finalize-correctly seam (F1, F5, F6) + the review-gate
pause (F3). Adjacent, in the same design or as called-out sections: F4 (a `/plan`
docs-emission change + detection contract) and F7 (a friction-log durability
convention). F2 is explicitly out of scope (install/marketplace + plugin-cache,
owned by niwa / Claude Code; benign).

## Handoff option

Because shirabe now has the `/scope` parent skill (tactical chain
BRIEF→PRD→DESIGN→PLAN), the user may prefer `/scope execute-friction` to run the
full chain in one sitting rather than `/design` alone. The friction log already
supplies BRIEF/PRD-level framing, so entering at `/design` is also reasonable.
Surface both at the produce handoff.
