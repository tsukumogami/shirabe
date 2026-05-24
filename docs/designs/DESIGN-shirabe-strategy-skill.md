---
status: Proposed
problem: |
  shirabe's PRD-shirabe-strategy-skill commits to introducing
  STRATEGY as a first-class artifact type with its own loadable
  skill, format reference, Phase 4 jury, and validate-CLI coverage.
  The PRD names what to build; the technical question is how to
  slot the new type into the existing skill / format-reference /
  validate-CLI / evals / transition-script infrastructure without
  introducing new validation pipelines or breaking the per-skill
  conventions the other five artifact types already follow.
decision: |
  Mirror the per-skill structure established by /vision and /prd:
  one Go-side Formats-map entry, one custom visibility-gating
  check, one SKILL.md plus phase files, one format-reference,
  one transition-status.sh, one evals.json. Phase 4 spawns three
  parallel reviewer agents through the same pattern /vision Phase
  4 uses today. Sunset moves files to docs/strategies/sunset/
  matching VISION's directory-as-state convention.
rationale: |
  The PRD's core-layer constraint is "ships using current shirabe
  patterns." Every technical decision in this design either copies
  an established precedent verbatim or makes a deliberate
  divergence with explicit rationale. The cost of inventing new
  patterns at this layer (skill loaders, validation pipelines,
  transition mechanics) compounds against shirabe's discipline-vs-
  artifact decoupling thesis; the design rejects all such
  invitations.
upstream: docs/prds/PRD-shirabe-strategy-skill.md
---

# DESIGN: shirabe-strategy-skill

## Status

Proposed

This design is being authored ahead of PRD acceptance — PR #94
carries both the brief and PRD in Draft, with the design stacked
on top. The intent is to land all three artifacts together so the
implementing PR has a complete requirements-through-design trace
on landing. The skill's documented flow (`Phase 0: STOP if PRD is
not Accepted`) is deliberately deviated from at user direction;
the design treats the PRD content as the authoritative requirements
input and will be re-validated against the merged PRD before
implementation begins.

## Context and Problem Statement

The PRD commits shirabe to a new artifact type integrated across
five touch points in the existing infrastructure:

- A new skill at `skills/strategy/` following the per-skill
  convention (SKILL.md + `references/phases/` + `scripts/` +
  `evals/`).
- A new format reference at `skills/strategy/references/strategy-format.md`
  mirroring the skeleton of `vision-format.md` / `roadmap-format.md` /
  `prd-format.md`.
- A new entry in the Go-side Formats map at
  `internal/validate/formats.go` activating FC01-FC04 automatically.
- A new custom check in `internal/validate/checks.go` enforcing
  the visibility-gated Competitive Considerations section, mirroring
  the existing `checkVisionPublic` pattern.
- A new transition-status script at
  `skills/strategy/scripts/transition-status.sh` handling
  Draft → Accepted → Active → Sunset transitions.

Each touch point has an established precedent. The technical
problem is not "how do we invent these"; it is "which precedent
fits, and where do we deliberately diverge."

The PRD intentionally deferred design-level decisions in six
areas: per-section content rules for STRATEGY's unique sections,
Phase 4 jury prompt text, Sunset directory mapping, the custom
check's function name and dispatch shape, transition-script
behavior contract, and evals fixture content. This design owns
each of those decisions.

The PRD also flagged the Building Blocks granularity rubric (R6.1)
as revisable through the format reference rather than amending the
PRD. The design specifies how that revisability surface is exposed.

## Decision Drivers

Constraints inherited from the PRD that shape implementation:

- **Core-layer constraint (R5, R11).** The skill ships as a
  plain-English SKILL.md following `/vision` and `/decision`
  precedent. No koto-driven structure, no new runtime
  infrastructure, no dependencies on workspace-context-surface
  features that haven't shipped.

- **No new validation infrastructure (R12).** Implementation
  reuses `internal/validate/` and the existing reusable
  `validate-docs.yml` workflow. No parallel pipelines, no new CLI
  binaries.

- **Three-reviewer jury parallelism (R6).** Phase 4 must spawn
  three review agents in parallel using the Agent tool with
  `run_in_background: true`. Verdict aggregation matches
  `/vision` Phase 4.3.

- **Visibility-gated Competitive Considerations (R7).** The
  custom check must reject the section in public-visibility
  contexts unless `cfg.Visibility == "private"`, following the
  exact precedent `checkVisionPublic` sets.

- **Lifecycle four-state contract (R4).** Draft, Accepted,
  Active, Sunset. Transitions through `transition-status.sh` only
  — no auto-triggers.

- **Format-reference skeleton symmetry.** The new
  `strategy-format.md` must mirror the skeleton (Frontmatter →
  Required Sections → Optional Sections → Visibility-Gated
  Sections → Content Boundaries → Lifecycle → Validation Rules →
  Quality Guidance) used by `vision-format.md`.

- **Revisable rubric surface (R6.1).** Numeric defaults for the
  Building Blocks granularity rubric must live in the format
  reference (not the Go validation code), so revising them does
  not require a PRD amendment or a code change.

Implementation-specific drivers added at design time:

- **Pattern-fidelity over creativity.** Where a precedent exists,
  copy it. The design must be reviewable against existing
  artifact-type implementations; deviations require explicit
  rationale.

- **Read-time discoverability.** Future skill authors looking at
  `skills/strategy/` should be able to learn the convention by
  diffing it against `skills/vision/`. Structural divergence
  should be minimized.

- **Test fidelity at jury level.** Evals must exercise the format
  spec's correctness rules, not just the skill's happy path. A
  passing evals run should mean the format spec works, not just
  that the skill emits files.

<!-- Phase 1-6 content lands below this point. -->
