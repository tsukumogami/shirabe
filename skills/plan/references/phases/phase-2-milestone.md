# Phase 2: Milestone Derivation

Derive the single milestone for this source document.

## Resume Check

If `wip/plan_<topic>_milestones.md` exists, read it and skip to Phase 3.

## Prerequisites

Read `wip/plan_<topic>_analysis.md` to get the source document path, input type, and component/feature list.

## Goal

Each source document maps to exactly one GitHub milestone. This phase derives the milestone title from the document's first `#` heading and prepares the description.

For the full milestone convention (title rules, description format, conformance checklist), see the **github-milestone** skill at `../../../github-milestone/SKILL.md`.

## 1:1 Document-to-Milestone Invariant

- One source document = one GitHub milestone
- Milestone title is derived from the source document's first `#` heading
- Milestone description references the source document path
- If work needs multiple milestones, create separate documents via `needs-design` issues

## Steps

### 2.1 Derive Milestone Title from Source Document Heading

Read the source document and find the first `#` heading. Known heading formats:

- `# DESIGN: <Title>` (standard design doc)
- `# Design Document: <Title>` (older design docs)
- `# PRD: <Title>` (PRD format)
- `# ROADMAP: <Title>` (roadmap format)

Extract the title portion after the prefix, trimming any leading and trailing whitespace. The result is a human-readable phrase used as the milestone title.

Examples:
- `# DESIGN: Pipeline Dashboard` becomes **Pipeline Dashboard**
- `# Design Document: Secrets Manager` becomes **Secrets Manager**
- `# ROADMAP: Artifact Workflow` becomes **Artifact Workflow**
- `# PRD: User Authentication` becomes **User Authentication**

The title should read naturally as the answer to "what does this milestone accomplish?" -- not a kebab-case slug or a filename.

### 2.2 Construct Milestone Description

The description references the source document path using backticks. The reference
prefix matches the input type:

| input_type | Description format |
|------------|-------------------|
| design | `Design: \`<path>\`` |
| prd | `PRD: \`<path>\`` |
| roadmap | `Roadmap: \`<path>\`` |

Examples:
```
Design: `docs/designs/DESIGN-pipeline-dashboard.md`
Roadmap: `docs/roadmaps/ROADMAP-artifact-workflow.md`
```

### 2.3 Scope Check

Review the estimated issue count from Phase 1 analysis:

- **If > 15 issues**: Consider whether the document should be split. Large designs may benefit from being broken into multiple designs, each with `needs-design` issues spawning the sub-designs.
- **If 1-3 issues**: This is fine for small, focused documents.
- **If 3-15 issues**: Typical range, proceed normally.

This is guidance, not a hard rule. Some large documents are cohesive and shouldn't be split.

### 2.4 Write Artifact

Create `wip/plan_<topic>_milestones.md` (Write tool):

```markdown
# Plan Milestone: <heading-derived-title>

## Milestone

**Name**: <heading-derived-title>

**Description**: `<Type>: \`<source-doc-path>\``

**Source Document**: `<source-doc-path>`

## Scope Assessment

**Estimated issues**: <count from Phase 1>

**Assessment**: <normal / large - consider splitting / small>
```

Where `<Type>` is `Design`, `PRD`, or `Roadmap` depending on the input type.

## Quality Checklist

Before proceeding:
- [ ] Milestone title extracted from the source document's first `#` heading
- [ ] Title is a human-readable phrase (not kebab-case, not a filename)
- [ ] Description includes source document path in correct format

## Next Phase

Proceed to Phase 3: Decomposition (`phase-3-decomposition.md`)
