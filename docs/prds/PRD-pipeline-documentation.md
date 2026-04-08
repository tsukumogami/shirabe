---
status: Done
problem: |
  Individual skills (/explore, /prd, /design, /plan, /work-on) are well
  documented, but the system connecting them isn't. The three-diamond model,
  five complexity levels, transition graph, and traceability chain exist only
  as fragments in the roadmap and individual skill docs.
goals: |
  Create a pipeline reference document that gives the workflow a conceptual
  home. Individual skill docs reference it instead of re-explaining the model.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Pipeline Documentation

## Status

Done

## Problem statement

The strategic pipeline roadmap describes a three-diamond model with five
complexity levels, named transitions (Advance, Recycle, Skip, Hold, Kill),
and a traceability chain linking artifacts from VISION to implementation.
But this description lives only in the roadmap's Theme section -- it was
written to justify the initiative, not to serve as a reference.

Individual skills document their own phases thoroughly. What's missing is
the connective tissue: how the skills form a workflow, how complexity
determines which skills are involved, what state transitions look like
across artifact types, and how the traceability chain works end-to-end.

An agent encountering a new task has to read the /explore SKILL.md routing
tables, then maybe the crystallize framework, then the /plan SKILL.md for
execution modes. There's no single place that explains the pipeline as a
system.

## Goals

- One reference document that describes the pipeline model, not individual
  skill internals
- Agents can understand the workflow without reading all five skill docs
- Individual skill docs can reference the pipeline doc instead of
  re-explaining the model
- The document is a reference, not a tutorial -- concise and scannable

## User stories

1. As an agent receiving a task, I want one document that tells me which
   skills apply and in what order, so I don't have to piece it together
   from five skill docs.

2. As a skill author adding a new skill, I want a pipeline reference that
   shows where my skill fits in the workflow, so I can design its handoff
   points correctly.

3. As a contributor reading the codebase for the first time, I want a
   pipeline overview that explains how the pieces connect, so I can
   navigate the skill ecosystem.

## Requirements

### Functional

**R1. Pipeline model reference.** Document the three-diamond model with
the five complexity levels and how they map to skill sequences. Include
the pipeline diagram from the roadmap, adapted for reference use rather
than roadmap justification.

**R2. Complexity routing summary.** Summarize the five-level routing model
with entry points. Reference the /explore SKILL.md detection algorithm
rather than duplicating it -- this section explains *what* the levels are
and where they enter the pipeline, not *how* to classify.

**R3. Named transitions.** Document the five transitions (Advance,
Recycle, Skip, Hold, Kill) with definitions and when each applies. These
are mentioned in the roadmap's Theme but not defined anywhere.

**R4. Artifact lifecycle states.** Unified view of lifecycle states across
artifact types. Each type has its own states (Draft/Accepted/Done for
PRDs, Proposed/Accepted/Planned/Current for designs, etc.) but there's no
single place showing the full picture.

**R5. Traceability chain.** Visualize the upstream/downstream chain from
VISION through implementation. Reference the artifact-traceability design
doc and cross-repo-references.md rather than duplicating them.

**R6. Skill routing table.** Map each pipeline entry point to the skill
sequence it follows. A reader should be able to find "I have a strategic
task" and see: /explore -> /vision or /roadmap -> per-feature pipeline.

### Non-functional

**R7. Reference format, not tutorial.** The document should be scannable
with tables and diagrams. No step-by-step instructions -- that's what
skill docs are for.

**R8. Single file.** One document at `references/pipeline-model.md` (or
`docs/guides/pipeline.md` -- location to be decided in design). No
multi-file structure.

**R9. No skill changes.** This feature produces a reference document. It
doesn't modify existing skills. Individual skill docs may later be updated
to reference it, but that's a follow-up, not part of this feature.

## Acceptance criteria

- [ ] Reference document exists with pipeline model diagram
- [ ] Five complexity levels described with entry points
- [ ] Five named transitions defined
- [ ] Artifact lifecycle states shown in unified view
- [ ] Traceability chain visualized
- [ ] Skill routing table maps entry points to skill sequences
- [ ] Document is reference format (tables, diagrams, no tutorials)
- [ ] No changes to existing skills

## Out of scope

- Changes to skill SKILL.md files (follow-up: skills reference the
  pipeline doc)
- Enforcement of pipeline transitions (that's F8/F10 territory)
- New skills or commands
- The crystallize framework's scoring details (belongs in /explore)
- Worked examples or tutorials

## Decisions and trade-offs

**Reference doc, not a guide.** A guide would walk through scenarios
("when you get a bug report, do X"). A reference describes the model
("the pipeline has five levels, here's what they mean"). The reference
is more durable -- it doesn't need updating when skill details change,
only when the model itself changes.

**Single file over multi-file.** The pipeline model is one concept. Splitting
it across files (model in one, states in another, routing in a third)
would recreate the fragmentation this feature solves.

## Related

- **ROADMAP-strategic-pipeline.md** -- Feature 6 describes this work;
  the Theme section contains the three-diamond model and named transitions
- **DESIGN-complexity-routing-expansion.md** (Current) -- F4 added the
  five-level routing model that R2 summarizes
- **DESIGN-artifact-traceability.md** (Current) -- F3 added the upstream
  fields that R5 visualizes
- **skills/explore/SKILL.md** -- contains the detection algorithm and
  routing tables that R2 and R6 reference
