# PLAN Artifact Format Specification

Reference for constructing `PLAN-<topic>.md` artifacts. The plan
profile of the shared issues-table framework owns table shape and
strikethrough rules; the shared dependency-diagram convention owns
the mermaid graph. This file carries the plan-specific deltas, the
plan lifecycle, and the issue-outline / decomposition-strategy
content that has no shared analogue.

## Table of Contents

- [Shared References](#shared-references)
- [File Location](#file-location)
- [Frontmatter](#frontmatter)
- [Lifecycle](#lifecycle)
- [Required Sections](#required-sections)
- [Execution Mode Differences](#execution-mode-differences)
- [Decomposition Strategies](#decomposition-strategies)
- [Section Placement](#section-placement-legacy-context)
- [Examples](#examples) (in `plan-doc-examples.md`)

## Shared References

Both the issues-table format (plan profile) and the dependency-diagram
convention live at the plugin root and are consumed by both the plan
and roadmap workflows:

- `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` -- the shared
  issues-table framework. The plan profile keys on issues with the
  `Issue | Dependencies | Complexity` shape, the `[#N: <title>](url)`
  link form, the Complexity values (`simple`, `testable`,
  `critical`), and the child reference row for `tracks-design` and
  `tracks-plan` issues. This reference owns table shape, description
  rows, child reference rows, strikethrough rules, and the milestone
  heading.

- `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md` -- the
  shared dependency-diagram convention. Owns the mermaid syntax
  rules, the fixed status-class palette, node format, class
  assignment, initial status, status updates, and legend.

- `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` -- the
  five principles both workflows derive from. The single-pr default
  (P1) and the lowest-ceremony principle (P2) drive the execution
  mode choice below.

## File Location

PLAN artifacts live at `docs/plans/PLAN-<topic>.md`. When a PLAN
reaches Done status, move it to `docs/plans/done/PLAN-<topic>.md`.

## Frontmatter

```yaml
---
schema: plan/v1
status: Draft
execution_mode: single-pr  # single-pr | multi-pr
upstream: docs/designs/DESIGN-<topic>.md  # optional, path to source design/PRD
milestone: "<Milestone Name>"
issue_count: <N>
---
```

**Required fields:** `schema`, `status`, `execution_mode`,
`milestone`, `issue_count`.

**Optional fields:** `upstream` -- path to the design doc, PRD, or
roadmap that this plan decomposes.

The `milestone` field is always present (it names the logical work
unit) but GitHub milestone creation only happens in multi-pr mode.

## Lifecycle

| Status | Meaning | Trigger |
|--------|---------|---------|
| Draft | Plan being written during /plan phases | /plan creates the PLAN artifact |
| Active | Implementation underway | multi-pr: GitHub issues created; single-pr: /work-on starts |
| Done | Implementation complete, move to `docs/plans/done/` | multi-pr: all issues closed; single-pr: PR merged |

**Coordinated lifecycle with design docs:**

| Design doc | PLAN doc | Trigger |
|------------|----------|---------|
| Accepted | _(doesn't exist)_ | /design or /explore approval |
| Planned | Draft | /plan creates the PLAN artifact |
| Planned | Active | /plan finishes (issues created or /work-on starts) |
| Planned | _(updated per issue)_ | Issues implemented via /work-on |
| Current | Done | /complete-milestone (all issues closed) |

## Required Sections

Every PLAN artifact has these 7 sections, in order:

1. **Status** -- current lifecycle state
2. **Scope Summary** -- 1-2 sentence description of what this plan covers
3. **Decomposition Strategy** -- walking skeleton, horizontal, or feature-by-feature planning, with rationale
4. **Issue Outlines** -- brief description of each issue before full bodies exist (populated in single-pr mode)
5. **Implementation Issues** -- table with issue links, dependencies, complexity (populated in multi-pr mode). See `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` for the canonical plan profile shape, description rows, child reference rows, and strikethrough rules.
6. **Dependency Graph** -- Mermaid diagram showing issue relationships. See `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md` for syntax rules, status classes, node format, and legend.
7. **Implementation Sequence** -- critical path and parallelization opportunities

## Execution Mode Differences

| Section | single-pr | multi-pr |
|---------|-----------|----------|
| Issue Outlines | Populated with structured outlines (goal, acceptance criteria, dependencies) | Empty or omitted |
| Implementation Issues | Empty or omitted (no GitHub issues to link) | Populated with issue table |

In single-pr mode, Phase 4 agents produce structured outlines that
become sub-sections under Issue Outlines. These give /work-on the
decomposition it needs without creating GitHub artifacts. The PLAN
doc stays at Draft and transitions to Active when /work-on starts.

In multi-pr mode, Phase 4 agents write full issue body files. Phase 7
creates GitHub issues and milestones, populates the Implementation
Issues table with links, and transitions the PLAN doc to Active.

### Issue Outline Format

Each issue under `## Issue Outlines` follows this structure:

```markdown
### Issue N: <title>

**Goal**: <one sentence describing what this issue delivers>

**Acceptance Criteria**:
- [ ] <specific, testable criterion>

**Dependencies**: None | Blocked by <<ISSUE:N>>

**Type**: code                                    # optional: code | docs | task (default: code)
**Files**: `path/to/file.md`, `path/to/other.md`  # optional: write targets for conflict detection
```

**`**Type**:`** (optional)

Valid values: `code`, `docs`, `task`. When absent, the `ISSUE_TYPE`
template variable is omitted entirely when the child workflow is
initialized.

This is a hint for the analysis agent, not a binding declaration.
The analysis agent may confirm or override this classification based
on what the work actually entails. Routing at `implementation` is
determined by the agent's confirmed type, not the PLAN author's
annotation.

- `code` -- implementation that runs through the full
  scrutiny/review/QA pipeline
- `docs` -- writing, structure, and clarity changes that skip the
  code review panels
- `task` -- operational work (run commands, execute scripts) that
  produces no meaningful code or doc artifacts for review; skips
  code review panels

**`**Files**:`** (optional)

Comma-separated list of file paths, each enclosed in backticks.
Declares which files this issue intends to write to.
`plan-to-tasks.sh` parses this field and wires a star topology to
prevent concurrent overwrites: the first outline to declare a file
becomes its owner; every later outline that shares that file gets a
`waits_on` edge pointing to the owner. Two non-owner outlines that
share the same file do NOT wait on each other -- only on the owner.

This field is opt-in -- add it only when concurrent file conflicts
are plausible. Omitting it does not prevent parallel execution; it
means the author accepts responsibility for ensuring no conflicts
exist.

Example with both optional fields:

```markdown
### Issue 3: feat(work-on): add issue_type routing

**Goal**: Add issue_type routing to work-on.md.

**Acceptance Criteria**:
- [ ] Three-way routing at implementation.accepts

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`
```

## Decomposition Strategies

Three decomposition strategies are available:

| Strategy | When Used | Issue Type |
|----------|-----------|------------|
| Walking skeleton | New feature with end-to-end flow | Code implementation issues |
| Horizontal | Refactoring, documentation, loosely coupled components | Code implementation issues |
| Feature-by-feature planning | Roadmap input (`input_type: roadmap`) | Planning issues (artifact production) |

**Feature-by-feature planning** maps each roadmap feature 1:1 to a
planning issue. The issues track artifact creation (PRDs, designs,
spikes, decisions) rather than code implementation. All planning
issues are `simple` complexity. Each issue carries a `needs_label`
indicating what upstream artifact the feature requires (needs-prd,
needs-design, needs-spike, or needs-decision).

The strategy section in the PLAN doc should explain the mapping:

```markdown
## Decomposition Strategy

**Feature-by-feature planning.** Each roadmap feature becomes one planning issue that tracks
the creation of its required upstream artifact. The per-feature `needs-*` label indicates
what type of artifact each feature requires next.
```

## Section Placement (Legacy Context)

In design docs that predate the PLAN artifact, the Implementation
Issues section was inserted directly into the design doc body,
immediately after Status. In the PLAN artifact, this content lives in
its own document, so placement is governed by the Required Sections
order above.

## Examples

See `plan-doc-examples.md` for complete examples of multi-pr,
completed issues, inline implementation, and roadmap modes.
