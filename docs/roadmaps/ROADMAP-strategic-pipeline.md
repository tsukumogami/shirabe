---
status: Draft
theme: |
  Complete the strategic-to-tactical pipeline by adding the missing inception
  layer and closing gaps in traceability, routing, and artifact production.
  Seven of eight pipeline stages are well-covered; this roadmap addresses
  Stage 1 (Inception/Strategic) and cross-cutting improvements that make the
  full pipeline coherent.
scope: |
  Covers the shirabe workflow skills plugin and its integration points.
  Features touch /explore (crystallize framework, Phase 5 handlers),
  artifact schemas (frontmatter fields), and documentation. Does not cover
  Go code changes to workflow-tool, private-plugin-only skills, or migration
  of existing documents to new formats.
---

# ROADMAP: Strategic Pipeline Completion

## Status

Draft

## Theme

The artifact-centric workflow redesign (Features 1-7 in the private plugin)
built a solid pipeline from discovery through delivery. But it starts at
the PRD level -- it assumes you already know what project you're building.
There's no structured path from "I have a project idea" to "I have
requirements I can design against."

This roadmap fills that gap and closes cross-cutting issues that emerged
during the pipeline mapping. The work follows a three-diamond model where
the pipeline groups naturally into Explore/Crystallize, Specify/Scope, and
Implement/Ship. Each diamond is a diverge-converge pair. Five named
transitions connect them: Advance, Recycle, Skip, Hold, Kill.

### Pipeline Model

```
Diamond 1: EXPLORE / CRYSTALLIZE
  /explore (diverge) -> crystallize (converge)
  
Diamond 2: SPECIFY / SCOPE  
  /prd, /design (diverge) -> /plan (converge)
  
Diamond 3: IMPLEMENT / SHIP
  /work-on, /implement (diverge) -> /release (converge)
```

Five complexity levels route work through the pipeline:

| Level | Entry Point | Diamonds Used |
|-------|------------|---------------|
| Trivial | /work-on (no issue) | Diamond 3 only |
| Simple | /work-on <issue> | Diamond 3 only |
| Medium | /design -> /plan | Diamonds 2-3 |
| Complex | /explore -> full pipeline | All three |
| Strategic | VISION -> Roadmap -> per-feature | All three, with branching |

## Cross-Cutting Decisions

**Each document type gets its own skill with a creation workflow.** Every
artifact type (VISION, Roadmap, etc.) should have a dedicated skill that
owns format spec, creation workflow, lifecycle management, and validation
-- all in one place. /explore hands off to these skills via auto-continue
(same pattern as /prd and /design). Skills also work standalone when
someone already knows what they want. This replaces the earlier approach
of reference-only skills with inline /explore production.

## Features

### Feature 1: VISION Artifact Type

Add VISION as a supported artifact type in the crystallize framework.
VISION captures project thesis, audience, value proposition, org fit,
success criteria, and non-goals -- the pre-PRD layer that justifies a
project's existence.

**Dependencies:** None
**Status:** Not Started
**Downstream:** Needs PRD

Key decisions from exploration:
- Template: thesis, audience, value proposition, org fit, success criteria,
  non-goals, open questions, downstream artifacts
- Lifecycle: Draft -> Accepted -> Active -> Sunset (stays Active, never
  "completes")
- Naming: `VISION-<name>.md` in `docs/visions/`
- Frontmatter: status, thesis (summary), scope (org/project), upstream
- Gated to strategic scope; tactical scope is a hard anti-signal
- Dedicated /vision skill with creation workflow (per cross-cutting decision)
- /explore hands off via auto-continue; also works standalone
- Works at org-level and project-level via scope field
- Visibility controls content richness, not availability

Crystallize integration:
- Signal/anti-signal table with project-existence as the key discriminator
- Tiebreaker rules vs PRD, Roadmap, No Artifact, Rejection Record
- Disambiguation: when exploration surfaces both thesis and requirements,
  VISION comes first (strategic justification before requirements)

### Feature 2: Roadmap Creation Skill

Add a dedicated `/roadmap` creation skill for Roadmap artifacts (per
cross-cutting decision: each doc type gets its own skill). Currently the
roadmap skill is format-reference-only -- it defines structure and
lifecycle but doesn't guide creation. The new skill owns format spec,
creation workflow, lifecycle management, and validation, following the
same pattern as /prd, /design, and /vision.

**Dependencies:** None (independent of Feature 1)
**Status:** Not Started
**Downstream:** Needs PRD

/explore hands off to /roadmap via auto-continue. /roadmap also works
standalone. The private plugin's roadmap reference defines the format;
this feature wraps it in a full creation workflow.

### Feature 3: Artifact Traceability

Close the traceability chain from VISION to PR by adding `upstream`
frontmatter fields to Roadmap and Design Doc schemas, and establishing
cross-repo reference conventions.

**Dependencies:** Feature 1 (VISION type must exist for full chain)
**Status:** Not Started
**Downstream:** Needs PRD

Three changes:
1. Add `upstream` to Roadmap frontmatter (currently missing)
2. Add `upstream` to Design Doc frontmatter (currently uses `spawned_from`
   for child designs but has no general PRD-to-design link)
3. Cross-repo reference convention: `owner/repo:path` with `private:`
   prefix for visibility boundaries

Stretch: automate Downstream Artifacts section updates when workflows
create new artifacts (currently manual and often missing).

### Feature 4: Complexity Routing Expansion

Expand the /explore complexity routing table from 3 levels
(Simple/Medium/Complex) to 5 levels (adding Trivial and Strategic). Each
level maps to a specific command path through the pipeline.

**Dependencies:** Feature 1 (Strategic level needs VISION to route to)
**Status:** Not Started
**Downstream:** Needs PRD

Changes:
- Update /explore SKILL.md routing tables
- Add Strategic complexity level with VISION/Roadmap entry points
- Add Trivial complexity level bypassing all artifacts
- Document the five-level model with signals for each level

### Feature 5: Pipeline Documentation

Document the three-diamond model, the five complexity levels, the full
transition graph, and the traceability chain as a reference document. This
gives the pipeline a conceptual home that individual skill docs can
reference.

**Dependencies:** Features 1-4 (documents the completed pipeline)
**Status:** Not Started
**Downstream:** Needs Design (documentation architecture)

This is a docs artifact, not code. Could be:
- A `docs/guides/pipeline.md` reference document
- An update to the workspace CLAUDE.md pipeline section
- A standalone skill reference (like planning-context)

## Sequencing Rationale

Features 1 and 2 are independent and can proceed in parallel. Both fill
Stage 1 gaps -- VISION for project inception, Roadmap creation for
multi-feature sequencing.

Feature 3 (Traceability) depends on Feature 1 because the full chain
requires VISION as the top node. The Roadmap and Design Doc schema changes
could ship earlier, but the cross-repo convention needs VISION to be
meaningful.

Feature 4 (Routing) depends on Feature 1 because the Strategic complexity
level routes to VISION. The Trivial level could ship independently.

Feature 5 (Docs) depends on Features 1-4 because it documents the
completed pipeline. Writing docs before the pipeline is complete creates
maintenance burden.

The recommended order prioritizes the highest-value, lowest-dependency
features first:

```
Feature 1 (VISION) ----+---> Feature 3 (Traceability)
                       |
Feature 2 (Roadmap) ---+---> Feature 4 (Routing)
                       |
                       +---> Feature 5 (Docs)
```

## Progress

| Feature | Status | Downstream Artifact |
|---------|--------|-------------------|
| Feature 1: VISION Artifact Type | Not Started | -- |
| Feature 2: Roadmap Creation Workflow | Not Started | -- |
| Feature 3: Artifact Traceability | Not Started | -- |
| Feature 4: Complexity Routing Expansion | Not Started | -- |
| Feature 5: Pipeline Documentation | Not Started | -- |
