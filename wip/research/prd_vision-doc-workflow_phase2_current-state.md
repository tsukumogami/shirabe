# Phase 2 Research: Current-State Analyst

## Lead 5: PROJECTS.md Integration with /explore Workflow

### Findings

#### 1. PROJECTS.md: Current Format and Location

PROJECTS.md lives at `vision/org/PROJECTS.md`. Its full content is a two-section document: a "Current Projects" table with one entry (tsuku, status Active) and a "Future Ideas" section that says "To be populated as ideas emerge." The file has no frontmatter, no lifecycle states, no links to evaluation artifacts, and no connection to any workflow.

The file header describes it as "Future project ideas for the tsukumogami organization."

#### 2. Vision Repo README: A Separate, Richer Project Registry

The vision repo README has its own project table that's more detailed than PROJECTS.md:

| Project | Directory | Description | Status |
|---------|-----------|-------------|--------|
| tsuku | projects/tsuku/ | Self-contained package manager | Active - v0.4.0 |
| shirabe | docs/prds/ | Doc workflow plugin | Planning |

This table includes shirabe, which PROJECTS.md does not. The README also defines three status values:
- **Active**: Under active development with regular releases
- **Planning**: Requirements defined, implementation planning in progress
- **Concept**: Early exploration, no committed timeline

These three statuses overlap with but don't match the proposed lifecycle (Idea, Evaluating, Committed, Active, Maintained, Archived, Rejected). "Concept" maps roughly to Idea/Evaluating; "Planning" maps to Committed; "Active" matches. Maintained, Archived, and Rejected have no current equivalents.

The README also links to `org/PROJECTS.md` with the note "See org/PROJECTS.md for future project ideas and concepts under consideration" -- positioning PROJECTS.md as the pre-committed pipeline and the README table as the post-committed registry.

**Key implication:** There are two project registries today that are already out of sync. Shirabe appears in the README but not in PROJECTS.md. Any design needs to either consolidate them or define clear ownership boundaries.

#### 3. Vision Repo Directory Structure

The vision repo has two main hierarchies:

- `projects/<name>/` -- per-project strategic docs (DESIGN-*, RESEARCH-*, PLAN-*, ROADMAP). Only `projects/tsuku/` exists.
- `docs/` -- org-level strategic docs organized by type:
  - `docs/prds/` -- PRD-shirabe.md, PRD-niwa.md
  - `docs/designs/` -- five DESIGN-*.md files (cross-project)
  - `docs/roadmaps/` -- ROADMAP-niwa.md, ROADMAP-shirabe.md
  - `docs/competitive/` -- COMP-superpowers-vs-koto.md

There is no `docs/visions/` directory. VISION documents don't exist yet anywhere in the workspace. The `org/` directory contains only PROJECTS.md and `guides/new-repo-playbook.md`.

#### 4. Where VISION Docs Should Live: The Cross-Repo Problem

The scope doc says VISION docs live at `docs/visions/VISION-<name>.md`. But which repo's `docs/visions/`?

The skill that produces VISIONs lives in shirabe (public). But the natural home for VISION artifacts depends on scope:

- **Org-level VISIONs** (scope: org) -- These evaluate whether a project belongs in the org. They may contain pre-announcement details, resource assessments, competitive positioning. The vision repo (private) is the natural home, matching the existing pattern where PRDs for new projects (PRD-shirabe.md, PRD-niwa.md) already live in `vision/docs/prds/`.

- **Project-level VISIONs** (scope: project) -- These capture a project's ongoing identity and thesis. They could live in the target project repo alongside other docs.

The CLAUDE.md convention is explicit: "Link TO public repos, never FROM public repos to here." A public skill (shirabe) cannot reference private artifact locations in its templates or output messages. The skill needs to be location-agnostic -- it determines the content, and the location is resolved from the working directory context.

#### 5. New-Repo-Playbook: Thorough but Disconnected

The playbook at `org/guides/new-repo-playbook.md` is a detailed two-part guide (automated script + manual checklist) covering repo creation, GitHub settings, branch protection, CI setup, workspace integration, and plugin manifest creation.

It has no connection to PROJECTS.md or any evaluation workflow. The playbook's "Next steps" assume the decision to create a repo has already been made. There's no step that says "verify project is Committed in PROJECTS.md" or "link to the VISION/Brief that justified this project."

The scope doc explicitly marks new-repo-playbook automation as out of scope. The playbook remains a manual guide, but the PRD should specify that PROJECTS.md entries in "Committed" state should reference the playbook as the next step.

#### 6. Existing Artifact Production Pattern

The /explore crystallize framework currently supports five artifact types (PRD, Design Doc, Plan, No Artifact, Rejection Record) as "supported" and five as "deferred" (Spike Report, Decision Record, Competitive Analysis, Prototype, Roadmap). Decision Record was recently promoted from deferred to supported, establishing the pattern for adding new types.

The production pattern splits into two categories:
- **Handoff types** (PRD, Design Doc, Decision Record): Write a brief to wip/, then invoke the downstream skill in the same session.
- **Inline types** (Rejection Record, No Artifact, and all deferred-now-supported types like Roadmap, Spike Report, Competitive Analysis): Produce the artifact directly within Phase 5 without invoking another skill.

The scope doc says VISION uses inline production. This matches -- there's no standalone /vision command to hand off to.

#### 7. State Transition Mechanics

The exploration research (Lead 1) proposed these transitions:

| Transition | Trigger |
|------------|---------|
| Idea -> Evaluating | /explore starts for the project topic |
| Evaluating -> Committed | VISION doc status set to Accepted |
| Evaluating -> Rejected | VISION doc status set to Rejected (or Rejection Record produced) |
| Committed -> Active | Development starts (first release, or active work begins) |
| Active -> Maintained | Project reaches stability (manual transition) |
| Maintained -> Archived | Project deprecated (manual transition) |

Only the first three transitions (Idea -> Evaluating -> Committed/Rejected) connect to the /explore workflow. The rest are lifecycle events with no current workflow triggers.

### Implications for Requirements

#### R1: PROJECTS.md Format Needs a Complete Redesign

The current two-section format (Current Projects / Future Ideas) can't support lifecycle states. The new format needs:
- A single table with all projects regardless of state
- Columns: Project name, state, VISION doc link (if exists), project directory link (if exists), last updated date
- No separate "Future Ideas" section -- Idea state replaces it

#### R2: Two Registries Must Be Reconciled

The vision repo README's project table and PROJECTS.md track overlapping information with different scopes and freshness. Options:
1. PROJECTS.md becomes the single source of truth; README links to it (cleanest)
2. README keeps a curated "Active/Planning" subset; PROJECTS.md tracks the full pipeline (allows README to stay human-friendly)

The PRD should specify which approach, since both require README updates.

#### R3: /explore Phase 5 Produce Handler Must Be Location-Agnostic

The skill lives in public shirabe but artifacts may be written to any repo. The produce handler should:
- Determine the output directory from the working directory context (not hardcoded paths)
- Use `docs/visions/VISION-<name>.md` as the relative path convention
- Not reference private repo paths in skill text or user-facing messages

#### R4: PROJECTS.md Updates Should Be Specified as Manual with Guidance

Automatic PROJECTS.md updates during /explore would require the skill to know the vision repo path and write to it regardless of which repo /explore runs in. This is fragile (cross-repo writes, path assumptions). A better approach:
- The produce handler outputs a formatted PROJECTS.md entry the user can paste
- The handler tells the user to update PROJECTS.md with the new state
- This keeps the skill repo-agnostic while making the update easy

#### R5: Upstream Field Creates a Dependency Chain

The `upstream` frontmatter field (linking project-level VISIONs to org-level VISIONs) means the produce handler needs to:
- Ask whether this is org-level or project-level during Phase 5
- If project-level, check for an existing org-level VISION to link
- Populate the upstream field accordingly

#### R6: The README Status Taxonomy Needs Alignment

The README's three statuses (Active, Planning, Concept) should map to PROJECTS.md states. Either:
- Replace the README taxonomy with PROJECTS.md states (breaking change to README)
- Map: Concept = Idea/Evaluating, Planning = Committed, Active = Active, and add the missing terminal states

### Open Questions

1. **Should PROJECTS.md updates be automatic (cross-repo write) or manual (user pastes formatted entry)?** Automatic is more reliable but couples the skill to vision repo structure. Manual is simpler but risks drift.

2. **How should the two registries (README table vs PROJECTS.md) be reconciled?** The README already has shirabe listed that PROJECTS.md doesn't -- this gap predates the new workflow.

3. **Should the Committed -> Active transition be tracked?** It has no workflow trigger today. If it's manual-only, it may never happen, and the registry drifts.

4. **What happens when /explore runs in a public repo but the topic is an org-level project?** The VISION doc would contain strategic content that may not belong in a public repo. Should the produce handler detect this and suggest running in the vision repo instead?

5. **Should project-level VISIONs written in target repos (public) omit sections that org-level VISIONs (private) include?** The scope doc says "visibility controls content richness." The produce handler needs visibility-aware section gating -- the same pattern competitive analysis already uses.

## Summary

PROJECTS.md is a stub with one entry and no lifecycle process. The vision repo README maintains a separate, richer project table that's already out of sync. VISION docs don't exist anywhere yet -- the `docs/visions/` directory is new. The main integration challenge is that the skill lives in public shirabe but org-level VISION artifacts naturally belong in the private vision repo, requiring the produce handler to be location-agnostic and visibility-aware. The cleanest path is making PROJECTS.md the single project registry with lifecycle states, having the produce handler output formatted entries the user pastes rather than attempting cross-repo writes, and aligning the README's status taxonomy (Active/Planning/Concept) with the new lifecycle states.
