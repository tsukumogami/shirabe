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

**R4. Roadmap -> Plan flow is the connection mechanism.** A Roadmap's
features decompose into Plans via /plan. Each feature becomes a planning
issue that flows through its own PRD/design/plan cycle. The Roadmap
tracks progress across these independent pipelines. This is the hierarchy
pattern (most common in industry tools per research): separate types
connected by a well-defined input/output relationship.

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
- [ ] No changes to the Go workflow-tool binary
- [ ] Existing Plan artifacts and /plan workflows are unaffected

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
- **Connection via /plan over parent-child hierarchy**: /plan already
  consumes roadmaps and produces plans. Formalizing this as the connection
  mechanism avoids adding nesting depth (roadmap -> plan -> issues is
  already three levels).
