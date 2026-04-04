---
status: Draft
problem: |
  Roadmap and Plan artifact types share 70% conceptual overlap (lifecycle
  states, sequencing, dependency tracking, progress) but are treated as
  fully independent. The /roadmap creation skill (Feature 2) would duplicate
  lifecycle management, transition scripts, and validation patterns already
  built for /plan. The boundary between them is unclear to users.
goals: |
  Clarify the relationship between Roadmap and Plan so that Feature 2 can
  be designed with the right level of reuse, and users understand when to
  use which.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Roadmap and Plan Artifact Relationship

## Status

Draft

## Problem Statement

The workflow system has two artifact types that both sequence work items
with dependencies: Roadmap (portfolio-level, sequences features) and Plan
(implementation-level, sequences issues). They share the same lifecycle
(Draft -> Active -> Done), both track progress, both have ordered items
with dependencies, and both feed into downstream workflow steps.

The Feature 2 design for /roadmap essentially recreates /plan's structure
with different agent roles — duplicating dependency management, progress
tracking, lifecycle scripting, and validation patterns. Meanwhile, users
must learn two formats that look structurally similar but serve different
levels of abstraction.

The question isn't whether they're the same artifact (they're not — research
confirms five fundamental differences). The question is what they should
share and how their relationship should be formalized.

## Goals

- Define which structural elements Roadmap and Plan share vs which are
  type-specific
- Establish a shared conventions layer that both types follow, reducing
  duplication in skills, transition scripts, and validation
- Make the boundary clear enough that users and agents can confidently
  pick the right type
- Enable Feature 2 (/roadmap skill) to reuse shared infrastructure rather
  than duplicating it

## User Stories

1. As a workflow skill author, I want shared lifecycle conventions so that
   building a new artifact skill doesn't require reimplementing status
   transitions, validation, and progress tracking from scratch.

2. As a user deciding between /roadmap and /plan, I want a clear
   decision rule so I don't pick the wrong one and have to redo work.

3. As an agent running /explore, I want the crystallize framework to
   clearly distinguish Roadmap from Plan signals so it routes correctly.

4. As a maintainer, I want lifecycle transition scripts to share a common
   interface so I can learn one pattern and apply it across artifact types.

## Requirements

### Functional

**R1. Separate artifact types with shared conventions.** Roadmap and Plan
remain separate artifact types with separate file locations, frontmatter
schemas, and required sections. They share: lifecycle states
(Draft -> Active -> Done), transition script interface, upstream linking
convention, and status validation pattern.

Rationale: The Go `parsePlanDoc()` function, /implement's PLAN-only
contract, and /plan's roadmap-as-input/plan-as-output flow all assume
distinct types. Unification would require breaking changes across the Go
binary, /implement, /plan, and the state file schema — disproportionate
to the benefit.

**R2. Shared transition script interface.** All artifact transition scripts
follow a consistent interface: same argument pattern, same output format,
same error reporting conventions. Type-specific behavior (preconditions,
directory movement, forbidden transitions) is internal to each script. A
user who learns one script can use any of them. The existing design doc
transition script is the reference implementation; new scripts should match
its interface conventions.

**R3. Decision rule for Roadmap vs Plan.** The boundary is abstraction
level, not structure:

| Question | Roadmap | Plan |
|----------|---------|------|
| What are the work items? | Features (each needs its own PRD/design) | Issues (each is one implementation session) |
| What do items produce? | Upstream artifacts (PRDs, designs, spikes) | Code changes (PRs, commits) |
| What labels do items carry? | `needs-*` annotations | Complexity labels + acceptance criteria |
| Who consumes this? | /plan (decomposes features into issues) | /implement, /work-on |
| When is it done? | All features have terminal status | All issues closed or PR merged |

The crystallize framework already captures this: Roadmap signals include
"multiple features to sequence" and "portfolio-level planning." Plan
signals include "existing PRD or design doc" and "work understood well
enough to break into issues."

**R4. /plan enriches roadmaps directly — no separate PLAN doc.** When
/plan consumes a roadmap, it creates GitHub issues (one per feature with
needs-* labels), adds an Implementation Issues table and Mermaid dependency
graph directly into the roadmap document, creates a GitHub milestone, and
transitions the roadmap to Active. No separate PLAN doc is produced.

Rationale: The PLAN doc would duplicate information already in the roadmap
(feature list, dependencies, needs-* annotations, progress). The roadmap
IS the plan at the portfolio level. Each feature's issue then triggers its
own pipeline (PRD -> design -> plan -> implement) — the per-feature PLAN
docs are where implementation-level planning lives.

This means roadmap planning is always multi-pr (one issue per feature, each
independently progressing through downstream workflows). The single-pr
execution mode doesn't apply to roadmaps.

### Non-Functional

**R5. No Go code changes.** Shared conventions are implemented in skill
markdown and shell scripts, not in the workflow-tool binary.
`parsePlanDoc()` and the state file schema remain unchanged.

**R6. Backward compatible.** Existing Plan artifacts, /plan workflows,
and /implement consumers continue to work without modification.

## Acceptance Criteria

- [ ] Roadmap and Plan remain separate artifact types with distinct file
      locations (`docs/roadmaps/` vs `docs/plans/`)
- [ ] Both transition scripts follow a consistent interface matching the
      design doc transition script's conventions (argument pattern, output
      format, error reporting)
- [ ] A decision rule exists (in /explore's routing guide or skill docs)
      that distinguishes Roadmap from Plan based on abstraction level
- [ ] /plan consuming a roadmap adds Implementation Issues table and Mermaid
      dependency graph directly into the roadmap (no separate PLAN doc)
- [ ] /plan consuming a roadmap creates a GitHub milestone and per-feature
      issues with needs-* labels
- [ ] /plan consuming a roadmap transitions the roadmap from Draft to Active
- [ ] Roadmap planning is always multi-pr (no single-pr mode for roadmaps)
- [ ] No changes to the Go workflow-tool binary
- [ ] Existing Plan artifacts and /plan workflows for design/PRD inputs
      are unaffected

## Out of Scope

- Unifying Roadmap and Plan into a single artifact type (research ruled
  this out — five fundamental differences, hard codebase constraints)
- Go code changes to parsePlanDoc() or the state file schema
- Changes to /implement, /work-on, or other Plan consumers
- Retroactive changes to existing Plan or Roadmap artifacts
- The specific /roadmap creation workflow phases (that's the design's job)

## Known Limitations

- The transition script interface is shared by convention (following the
  design doc script as reference), not by shared code. Each script is a
  standalone bash file. A future refactoring could extract shared functions
  into a library, but that's premature until more artifact types exist.
- Shared conventions live inline in each skill rather than in a dedicated
  document. If a third sequencing artifact type emerges, extracting a
  shared conventions reference becomes justified.

## Decisions and Trade-offs

- **Separate types over unification**: The codebase has hard constraints
  (Go parser, /implement contract, /plan's input/output distinction) that
  make unification expensive. The 25% raw structural overlap doesn't
  justify the breaking changes. Industry consensus (5 of 6 tools) also
  favors separate types.
- **Inline conventions over shared document**: With only two sequencing
  artifact types, a standalone conventions document is premature abstraction.
  Each skill follows the design doc transition script as the reference
  implementation. A shared document becomes justified when a third type
  emerges.
- **Enrich roadmap over separate PLAN doc**: When /plan consumes a roadmap,
  it writes the issues table and dependency graph directly into the roadmap
  rather than producing a thin PLAN doc that duplicates roadmap content.
  The roadmap IS the plan at the portfolio level. This reduces artifact
  count and avoids maintaining two documents for the same initiative.
  Per-feature PLAN docs still exist for implementation-level decomposition.
