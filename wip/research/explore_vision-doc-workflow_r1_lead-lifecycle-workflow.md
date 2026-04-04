# Lead: What lifecycle and workflow changes are needed?

## Findings

### Current State: Infrastructure Exists but Gaps Are Wide

The org already has most of the physical infrastructure for project inception:

1. **Vision repo** (`private/vision/`) serves as a strategic planning hub with a `projects/` directory and an `org/` directory.
2. **PROJECTS.md** exists at `org/PROJECTS.md` and has a table with one entry (tsuku). The "Future Ideas" section says "To be populated as ideas emerge."
3. **A new-repo-playbook** exists at `org/guides/new-repo-playbook.md` -- a thorough script + checklist for setting up a GitHub repo. It covers everything from `gh repo create` to branch protection rulesets.
4. **Per-project directories** under `projects/<name>/` hold strategic docs (DESIGN-*, RESEARCH-*, PLAN-*, ROADMAP). Currently only `projects/tsuku/` exists.
5. **The README** references a project status taxonomy: Active, Planning, Concept.

What's missing is the workflow that connects "I have an idea" to "I have a project directory with requirements I can design against." The new-repo-playbook handles repo creation mechanics but assumes the project decision has already been made. PROJECTS.md is a registry stub with no process around it. There's no equivalent of /explore or /prd that operates at the org-project level rather than the feature level.

### Gap Analysis: Five Missing Pieces

**Gap 1: No "project inception" workflow.** The existing /explore skill routes to artifact types (PRD, Design Doc, Plan, etc.) scoped to a single repo. It has no mode for "I want to evaluate whether a new project belongs in this org." The signals in the crystallize framework are all feature-level: "What should we build?" vs "How should we build it?" None address "Should we build a new project at all, and where does it live?"

**Gap 2: PROJECTS.md has no lifecycle.** The file has a static table but no status transitions, no template for entries, and no workflow that reads from or writes to it. Contrast with how the roadmap works for tsuku -- ROADMAP.md tracks versions with status, features, and dependencies. PROJECTS.md needs a similar structure: idea -> evaluation -> committed -> active.

**Gap 3: Vision docs have no standard pre-project format.** The vision repo's `projects/tsuku/` directory contains DESIGN-*, RESEARCH-*, PLAN-*, and ROADMAP files. But these were all created after tsuku was already a committed project. There's no artifact type for the earlier stage: "Here's a project thesis, here's why it belongs in this org, here's what it would look like if we pursued it."

**Gap 4: Scope confusion between org-level and project-level vision.** The workspace CLAUDE.md defines a context model with Visibility (Private/Public) and Scope (Strategic/Tactical). Strategic scope in the vision repo means "designs scope multiple repos and define high-level architecture." But there's a level above that: org-level decisions about which projects to pursue. The existing scope model doesn't account for org-level strategic thinking.

**Gap 5: No connection between project registry and downstream workflows.** Even if PROJECTS.md becomes a living registry, nothing connects a "Committed" project entry to the new-repo-playbook, to initial PRD creation, or to the workspace CLAUDE.md update. These are manual steps someone needs to remember.

### What /explore Would Need to Change

Adding a "project inception" mode to /explore is the most natural path. The alternatives -- a standalone command or a manual process -- create more friction:

- **A new command** (e.g., /incept or /project) would duplicate /explore's discover-converge loop, scoping conversation, and crystallize framework. The structure is identical; only the artifact types differ.
- **A manual process** defeats the purpose of having structured workflows.

The changes to /explore would be:

1. **New scope level in Phase 1:** When the user's intent is "evaluate a new project for the org," Phase 1 should detect this and switch to org-level scoping. Signals: user mentions "new project," "new repo," topic doesn't map to an existing project, or the working directory is the vision repo.

2. **New artifact type in the crystallize framework:** "Project Brief" -- a document that captures the project thesis, org fit assessment, scope boundaries, and the decision on whether to proceed. It would live in the vision repo at `org/briefs/BRIEF-<project-name>.md` (or similar).

3. **New Phase 5 produce handler:** When crystallize selects "Project Brief," produce the brief and optionally update PROJECTS.md.

4. **Modified adversarial lead for project-level validation:** The existing demand-validation questions are feature-scoped ("Is demand real? What do people do today instead?"). At the project level, the questions shift: "Does this project overlap with existing org projects? Is the org the right home for this? What's the minimum viable scope?"

### Org-Level vs Project-Level Vision

These serve different purposes and should live in different places:

| Level | Purpose | Location | Example |
|-------|---------|----------|---------|
| Org-level | Which projects to pursue, org identity, resource allocation | `vision/org/` | PROJECTS.md, BRIEF-*.md |
| Project-level strategic | Multi-version roadmap, cross-cutting designs, pre-announcement features | `vision/projects/<name>/` | ROADMAP.md, DESIGN-*.md |
| Project-level tactical | Feature requirements, implementation designs, issue decomposition | Target project repo (e.g., `tsuku/docs/`) | PRD-*.md, DESIGN-*.md |

The current structure already separates project-level strategic (vision repo) from project-level tactical (target repos). The missing layer is org-level -- artifacts that evaluate and track projects as a portfolio rather than individual deliverables.

### PROJECTS.md as a Living Document

PROJECTS.md should evolve from a static table to a registry with lifecycle states:

| State | Meaning | Transition |
|-------|---------|------------|
| Idea | Someone proposed it, no evaluation yet | -> Evaluating (when /explore starts) |
| Evaluating | Active exploration underway | -> Committed or Rejected |
| Committed | Decision to build, pre-repo or early-repo | -> Active (when development starts) |
| Active | Under development with regular work | -> Maintained or Archived |
| Maintained | Stable, receiving fixes but not new features | -> Archived |
| Archived | No longer maintained | Terminal |
| Rejected | Evaluated and decided against, with reasoning | Terminal |

Each entry should link to its evaluation artifact (the Project Brief) and its project directory if one exists.

### Proposed Project Brief Format

A Project Brief would be the output of project-level /explore. It captures enough to make a go/no-go decision without committing to full requirements:

```markdown
---
status: Draft | Accepted | Rejected
project: <project-name>
date: <YYYY-MM-DD>
---

# BRIEF: <Project Name>

## Thesis
<2-3 sentences: what this project would do and why the org should build it>

## Org Fit
- How it relates to existing projects (complement, extension, independent)
- Why it belongs in this org rather than as an independent project or
  contribution to an existing project

## Problem Space
<What problem area this addresses, who has the problem, how they solve
it today>

## Minimum Viable Scope
<The smallest useful version of this project -- what it would do in v0.1>

## Open Questions
<What needs to be answered before committing>

## Decision
<Accepted with conditions / Rejected with reasoning / Pending>
```

## Implications

1. **The crystallize framework needs a new artifact type.** "Project Brief" is distinct from PRD (which assumes a project already exists) and from Roadmap (which sequences features within a project). The signals and anti-signals are different: org fit, overlap with existing projects, minimum viable scope clarity.

2. **PROJECTS.md becomes a workflow touchpoint, not just a file.** If /explore's produce phase can update PROJECTS.md, the registry stays current. If it's manual, it'll drift. The new-repo-playbook should also read from PROJECTS.md to validate that a project has been committed before repo creation.

3. **The vision repo's directory structure needs an `org/briefs/` directory** (or similar) to hold Project Brief artifacts. These sit between the ephemeral wip/ research files and the per-project strategic docs.

4. **Scope detection in Phase 1 needs refinement.** The current system detects Strategic vs Tactical from CLAUDE.md. Org-level scoping is a third level that only applies in the vision repo, and only when the topic is a new project rather than a feature within an existing project.

5. **The new-repo-playbook connects downstream.** When a Project Brief is accepted, the next step is either: (a) create a project directory in vision/ and write a PRD, or (b) run the new-repo-playbook to create the actual repo. A "Committed" state in PROJECTS.md could trigger guidance about which path to take.

## Surprises

1. **The new-repo-playbook is thorough but orphaned.** It exists as a guide with no workflow pointing to it. Nobody would discover it unless they browsed the vision repo's org/guides/ directory. It handles repo mechanics well but has no upstream trigger and no connection to project evaluation.

2. **Shirabe (this repo) already has a PRD in the vision repo** (`docs/prds/PRD-shirabe.md` referenced in the README), showing that PRDs for new projects do happen -- they just bypass any project-level evaluation process. The project was created directly with a PRD rather than going through any "should we build this?" stage.

3. **The "Concept" status in the README's project taxonomy** hints that someone already thought about pre-commitment project states, but it's not connected to any workflow or artifact type.

4. **Decision Record was recently added as a supported (non-deferred) artifact type** in Phase 5 produce, which means the pattern for adding new artifact types to the crystallize framework has been exercised recently.

## Open Questions

1. **Should Project Briefs live in the vision repo or in a new org-level location?** The vision repo is private, which is appropriate for pre-announcement projects. But if a project is public from the start, should its brief be public too?

2. **Is "Project Brief" the right granularity, or should inception produce a lightweight PRD instead?** A brief is smaller and more decision-focused. A PRD is more detailed and requirements-focused. The question is whether the go/no-go decision needs its own artifact or whether a PRD with a "not yet committed" status serves the same purpose.

3. **How does the adversarial demand lead adapt to project-level validation?** Feature-level demand validation checks issue reporters and workarounds. Project-level validation needs to check for overlap with existing projects, ecosystem fit, and whether the problem space is big enough to justify a separate project.

4. **Should the new-repo-playbook become a skill or remain a manual guide?** Automating it as a post-brief workflow step (triggered when a brief is accepted) would close the loop, but it's a one-time activity per project that may not warrant skill investment.

5. **What triggers project status transitions in PROJECTS.md?** If the workflow updates it automatically during /explore produce, that handles Idea -> Evaluating -> Committed/Rejected. But Active, Maintained, and Archived transitions are ongoing lifecycle events that don't map to any current workflow.

## Summary

The org has physical infrastructure for project planning (vision repo, PROJECTS.md, new-repo-playbook) but no workflow connecting "I have a project idea" to "I've evaluated it and decided to proceed" -- adding a Project Brief artifact type to /explore's crystallize framework and making PROJECTS.md a lifecycle-tracked registry would close this gap without requiring a new command. The main implication is that /explore needs a third scope level (org-level, above strategic/tactical) with project-specific evaluation criteria and adversarial leads. The biggest open question is whether Project Briefs deserve their own artifact type or whether a PRD with a pre-commitment lifecycle state would serve the same purpose with less workflow machinery.
