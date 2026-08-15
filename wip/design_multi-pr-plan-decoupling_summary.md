# Design Summary: multi-pr-plan-decoupling

## Input Context (Phase 0)

**Source:** /explore handoff

**Problem:** `/plan`'s `execution_mode` flag fuses three independent questions --
can this land in one PR, should it, and does it get GitHub issues and a milestone.
The forced and preferred cases are decided in one branch at
`phase-3-decomposition.md` step 3.6, and tracking is a hardcoded consequence in
`phase-7-creation.md`, so a repo can express no preference on either axis and no
plan records why it is not single-pr.

**Constraints:**

- Reuse the CLAUDE.md convention-header channel on the existing
  `flag > CLAUDE.md-header > default` stack; a `.shirabe.toml` layer was already
  rejected as disproportionate.
- The name `Execution Mode` is unavailable (taken by the autonomy header,
  collides with the `execution_mode` frontmatter enum).
- Do not weaken or carve out Phase 3.5a's value-confirmation guard.
- Amend `DESIGN-roadmap-plan-standardization.md` Decision 6 rather than
  re-deriving it; distinguish explicitly from `DESIGN-capstone-orchestration.md`
  Decision G's rejection of an orthogonal flag.
- New checks land on `PostureClass::DraftTolerable` -- notice in draft, error at
  ready. No new enforcement subsystem.
- Recording slot ships before either preference.

**Settled during exploration** (see the design's "Decisions Already Made"): the
posture-inversion shape over promoting reviewability into P1; a free-text
`split_rationale` frontmatter field rather than a section or an enum; two
independently triggered decisions on one shared mechanism in one document; the
milestone question reframed from significance to whether a GitHub-side grouping
handle is needed.

**Open for the design:** where each preference binds and what the headers are
named; the structural check that keeps free text from degrading to a
non-emptiness test; the conditional-required-field mechanism `FormatSpec` lacks;
the third source-var scheme for issueless multi-pr in `plan-to-tasks.sh`; the
`/work-on M<N>` substitute; whether to define the reviewability ceiling or defer
it; whether `execution_mode: coordinated`'s missing wiring is in scope.

## Current Status

**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** 2026-08-15
