# Phase 5: Dependency Mapping

Define the dependency graph between issues.

## Resume Check

If key `work/dependencies.md` exists in `plan-<topic>`, read it and skip to Phase 6.

## Prerequisites

Read:
- Key `work/decomposition.md` - Issue outlines with initial dependencies
- Key `work/manifest.json` - Generated issue bodies (keys `work/issue_<id>_body.md`) and complexity levels

## Goal

Establish clear sequencing:
- Which issues block which others
- What can be parallelized
- Critical path through implementation

## Input Type Branching

Read `input_type` from key `work/decomposition.md`'s YAML frontmatter.

- **design** or **prd**: Follow the standard dependency flow (steps 5.1 through 5.6)
- **roadmap**: Follow the roadmap dependency import flow (step 5.R1), then rejoin at step 5.2

---

## Steps

### 5.R1 Import Roadmap Dependencies (input_type: roadmap only)

Import dependencies from the roadmap's Sequencing Rationale section (captured in key `work/analysis.md` under "Sequencing Rationale" and "Cross-Feature Dependencies"):

1. Read key `work/analysis.md` to get the Sequencing Rationale and Cross-Feature Dependencies
2. For each dependency relationship:
   - **Hard dependencies** (technical blockers explicitly stated in the Sequencing Rationale, e.g., "Feature B requires Feature A's API"): Map to `Blocked by <<ISSUE:N>>` edges
   - **Soft dependencies** (ordering preferences, e.g., "Feature B ideally follows Feature A"): Record as notes in the dependency artifact, NOT as `Blocked by` edges
3. Match feature names from the analysis artifact to issue IDs from the decomposition artifact
4. Update the issue outlines in key `work/decomposition.md` (get it, edit, add it back) if any hard dependencies were missing from Phase 3's initial mapping

After importing, proceed to step 5.2 to build the dependency graph.

### 5.1 Identify Dependencies (input_type: design or prd)

For each issue, ask:
- Does this require another issue to be done first?
- Does this block other issues?
- Are there any circular dependencies? (these indicate a decomposition problem)

Review the dependencies declared in Phase 3 and verify they are still accurate after seeing the full issue bodies from Phase 4.

### 5.2 Build Dependency Graph

Create a visual representation of dependencies:

```
Issue 1 (no deps)
Issue 2 (no deps)
├── Issue 3 (blocked by 1)
├── Issue 4 (blocked by 2)
    └── Issue 5 (blocked by 3, 4)
```

### 5.3 Identify Parallelization

Note which issues can be worked on simultaneously:
- Issues with no dependencies can start immediately
- Issues with same blockers can be parallelized after blocker completes

### 5.4 Calculate Critical Path

Identify the longest chain of dependencies - this determines minimum time to completion.

### 5.5 Validate Sequencing

Check for problems:
- [ ] No circular dependencies
- [ ] All blockers are in the issue list
- [ ] Critical path is reasonable (not too long)
- [ ] Some issues can start immediately (no "first issue" bottleneck)

### 5.6 Write Artifact

Write key `work/dependencies.md` in `plan-<topic>` (`koto context add plan-<topic> work/dependencies.md`,
the content on stdin):

```markdown
# Plan Dependencies: <design-doc-name>

## Summary
- Total issues: <count>
- Issues with no dependencies: <count>
- Maximum dependency depth: <count>

## Dependency Graph

```
Issue 1 (skeleton, no deps)
├── Issue 2 (blocked by 1)
├── Issue 3 (blocked by 1)
    └── Issue 4 (blocked by 2, 3)
```

## Issue Dependencies

| Issue | Title | Blocked By | Blocks |
|-------|-------|------------|--------|
| 1 | <title> | None | 2, 3 |
| 2 | <title> | 1 | 4 |
| 3 | <title> | 1 | 4 |
| 4 | <title> | 2, 3 | None |

## Parallelization Opportunities

- **Immediate start**: Issues 1 (no dependencies)
- **After Issue 1**: Issues 2, 3 can be worked in parallel
- **After Issues 2, 3**: Issue 4

## Critical Path

Issue 1 -> Issue 2 -> Issue 4

Length: 3 issues

## Validation

- [x] No circular dependencies
- [x] All blockers exist in issue list
- [x] At least one issue has no dependencies
- [x] Critical path length is reasonable
```

## Quality Checklist

Before proceeding:
- [ ] All dependencies documented
- [ ] Dependency graph created
- [ ] No circular dependencies

## Next Phase

Proceed to Phase 6: Review (`phase-6-review.md`)
