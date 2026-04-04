---
status: Draft
problem: |
  The /plan skill produces separate PLAN docs regardless of input type, but
  when consuming roadmaps this creates a thin duplicate of information already
  in the roadmap. The plan skill also lacks a unified model for how "being
  planned" works across different upstream artifact types.
goals: |
  Rework /plan to enrich roadmaps directly (no separate PLAN doc) and
  establish a consistent model for what "planned" means across all upstream
  artifact types (roadmaps, design docs, PRDs).
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Plan Skill Rework

## Status

Draft

## Problem Statement

The /plan skill currently produces a PLAN doc for every input type (design
doc, PRD, roadmap). For design docs and PRDs, this makes sense -- the PLAN
doc adds decomposition strategy, dependency graph, and issue tracking that
the upstream artifact shouldn't carry. But for roadmaps, the PLAN doc is
a thin duplicate: the roadmap already has features (work items), dependencies,
sequencing rationale, and progress tracking.

Additionally, /plan lacks a unified model for what "being planned" means.
Design docs get status "Planned." PRDs get status "In Progress." Roadmaps
get... nothing (they don't change status when /plan runs). The completion
cascade is also inconsistent: PLAN docs get deleted when done, but design
docs transition to "Current." There's no consistent answer to "what happens
to the upstream artifact when all planned work is complete?"

## Goals

- /plan enriches roadmaps directly instead of producing separate PLAN docs
- Establish consistent "planned" semantics across all upstream types
- Define the completion cascade: what happens to upstream artifacts when
  all planned work finishes
- Progress consistency: downstream completion events propagate to upstream
  artifacts

## User Stories

1. As a user who planned a roadmap, I want the issues table and dependency
   graph to live in the roadmap itself so I have one document to track.

2. As a user completing features, I want the roadmap's progress to update
   when I close GitHub issues so the roadmap stays accurate.

3. As a user who finished all planned work, I want a clear answer to
   "what do I do with the upstream artifact now?" regardless of whether
   it's a roadmap, design doc, or PRD.

## Requirements

### Functional

**R1. Roadmap mode: enrich instead of produce.** When /plan consumes a
roadmap (`input_type: roadmap`), it adds Implementation Issues table and
Mermaid dependency graph directly into the roadmap document. Creates
GitHub milestone and per-feature issues with needs-* labels. Transitions
roadmap Draft -> Active. No separate PLAN doc produced.

**R2. Roadmap mode is always multi-pr.** Each feature becomes an
independent GitHub issue. Single-pr mode doesn't apply to roadmaps.

**R3. Consistent upstream status transitions.** When /plan runs:
- Roadmap: Draft -> Active (features locked, planning complete)
- Design doc: Accepted -> Planned (existing behavior, preserved)
- PRD: Accepted -> In Progress (existing behavior, preserved)

**R4. Progress consistency invariant.** When a planned issue is closed
on GitHub, the upstream artifact's tracking section must reflect it.
For roadmaps: Progress section and Issues table. For PLAN docs: Issues
table (existing strikethrough behavior). The invariant is the same;
the target artifact differs by input type.

**R5. Completion cascade.** When all planned issues reach terminal state:
- Roadmap: transition to Done (all features delivered or dropped)
- PLAN doc from design: delete PLAN, transition design to Current
- PLAN doc from PRD: delete PLAN, transition PRD to Done

### Non-Functional

**R6. Backward compatible.** Existing Plan docs, /implement workflows,
and design-doc-based planning are unaffected. The changes only affect
roadmap-mode behavior and formalize cascades that were previously manual.

**R7. No Go code changes for roadmap mode.** Roadmap enrichment is
handled in the skill's Phase 7, not in the Go binary. `parsePlanDoc()`
continues to parse PLAN docs only.

## Acceptance Criteria

- [ ] /plan consuming a roadmap adds Issues table + Mermaid graph into
      the roadmap (no PLAN doc produced)
- [ ] /plan consuming a roadmap creates milestone + per-feature issues
- [ ] /plan consuming a roadmap transitions it Draft -> Active
- [ ] Roadmap mode is always multi-pr
- [ ] Design doc and PRD modes continue to produce PLAN docs (unchanged)
- [ ] Issue closure propagates to upstream artifact's tracking section
- [ ] All-issues-complete triggers appropriate upstream transition per R5
- [ ] Existing /implement and /work-on workflows are unaffected

## Out of Scope

- /roadmap creation skill (separate PRD: PRD-roadmap-skill.md)
- Changes to /implement or /work-on
- Go code changes to parsePlanDoc()
- New artifact types or lifecycle states
- How /complete-milestone interacts with the cascade (future refinement)

## Known Limitations

- The progress consistency invariant (R4) describes what must be true,
  not how enforcement works. The mechanism (hook, skill step, or CI
  check) is a design decision.
- The completion cascade (R5) is triggered by "all issues terminal" but
  detecting this reliably requires either polling or event-driven
  automation, which is outside current skill capabilities.
