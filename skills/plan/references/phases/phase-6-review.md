# Phase 6: AI Review

Validate completeness and sequencing before creating issues.

## Resume Check

If `wip/plan_<topic>_review.md` exists, read it and skip to Phase 7.

## Prerequisites

Read:
- `wip/plan_<topic>_analysis.md` - Original design analysis
- `wip/plan_<topic>_decomposition.md` - Issue outlines
- `wip/plan_<topic>_manifest.json` - Generated issue bodies
- `wip/plan_<topic>_dependencies.md` - Dependency graph

## Goal

Catch problems before creating GitHub artifacts:
- Missing issues
- Incorrect dependencies
- Scope problems
- Quality issues

## Steps

### 6.1 Launch Review Agent

Use the Task tool to review the issue plan:

```
Task: Review the issue decomposition for a design implementation

Questions to address:
1. Does the issue set fully cover the design document scope?
2. Are there missing issues that would leave gaps in implementation?
3. Are dependencies correctly mapped? Any circular or missing dependencies?
4. Are issues appropriately atomic? Any that should be split or combined?
5. Is the sequencing realistic? Will the first issues provide value early?

Context:
- Design document path: <from wip/plan_<topic>_analysis.md>
- Issue count: <from manifest>
- Issue titles: <list from manifest>
- Dependency graph: <from wip/plan_<topic>_dependencies.md>
- Decomposition strategy: <from wip/plan_<topic>_decomposition.md>

Output: Provide structured review with findings and recommendations.
```

### 6.2 Process Feedback

For each piece of feedback from the review:

| Feedback | Severity | Action | Applied |
|----------|----------|--------|---------|
| <finding> | High/Medium/Low | <how to address> | [ ] |

### 6.3 Apply Fixes

For high and medium severity findings:
- Update issue body files if needed
- Update dependency mapping if needed
- Re-run validation if changes were made

### 6.4 Final Validation

Before proceeding to creation:
- [ ] All high-severity feedback addressed
- [ ] Medium-severity feedback addressed or deferred with rationale
- [ ] Issue list finalized
- [ ] Dependencies validated

### 6.5 Write Artifact

Create `wip/plan_<topic>_review.md` (Write tool):

```markdown
# Plan Review: <design-doc-name>

## Review Summary

- Review date: <timestamp>
- Issues reviewed: <count>
- Findings: <count high> high, <count medium> medium, <count low> low

## Coverage Assessment

- [x] All design components have corresponding issues
- [x] No gaps identified
- [ ] Gap found: <description> (if applicable)

## Dependency Validation

- [x] Dependencies correctly mapped
- [x] No circular dependencies
- [x] Critical path is reasonable (<N> issues)

## Issue Quality

- [x] Titles follow conventional commits
- [x] Acceptance criteria are testable
- [x] Each issue is atomic

## Findings and Actions

| Finding | Severity | Action Taken |
|---------|----------|--------------|
| <finding 1> | High | <action> |
| <finding 2> | Medium | <action> |
| <finding 3> | Low | Deferred |

## Deferred Items

<List any low-severity findings not addressed, with rationale>

## Recommendation

[x] Proceed to Phase 7: Creation
[ ] Requires additional work before proceeding
```

## Quality Checklist

Before proceeding:
- [ ] AI review completed
- [ ] All high-severity feedback addressed
- [ ] Issue specifications finalized
- [ ] Milestone assignments confirmed
- [ ] `wip/plan_<topic>_review.md` written

## Next Phase

Proceed to Phase 7: Creation (`phase-7-creation.md`)
