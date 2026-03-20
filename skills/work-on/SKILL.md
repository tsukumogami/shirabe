---
name: work-on
description: Implement a GitHub issue end-to-end: branch creation, analysis, coding, tests, and pull request with CI monitoring. Use when given an issue number, issue URL, milestone reference, or asked to work on, implement, fix, build, tackle, pick up, or close a specific issue. Automatically selects the next unblocked issue when given a milestone. Handles the full cycle from reading the issue to merging a passing PR.
argument-hint: '<issue_number | #issue | issue-url | M<milestone> | milestone-url | "Milestone Name">'
---
@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md

# Feature Development Workflow

Your goal is to work on a GitHub issue and deliver a high-quality, well-tested pull request.

## Input Resolution

The input `$ARGUMENTS` can be an issue reference or a milestone reference.

**Issue inputs**: `71`, `#71`, or issue URL - resolve directly to the issue number.

**Milestone inputs**: `M3`, `M#3`, milestone URL, or `"Milestone Name"` - list open issues in the milestone and select the first unblocked one (an issue is blocked if its Dependencies section references open issues). If multiple unblocked issues exist, pick the one with lowest number. If no unblocked issues exist, report which issues are blocked and stop.

### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, the issue needs classification before implementation. Check your project's label vocabulary (defined in `## Label Vocabulary` in CLAUDE.md) for the routing options available. If your project's extension file defines a triage workflow, invoke it now. Otherwise, ask the user whether to proceed directly or reclassify the issue.

### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding. Your project's label vocabulary is defined in `## Label Vocabulary` in CLAUDE.md.

If the issue has any label indicating it is not yet ready for implementation (such as labels requiring design, requirements definition, or feasibility investigation), display the appropriate routing message and **stop execution**.

If the issue has a label indicating it tracks a child artifact whose implementation is underway, stop and direct the user to work on the child artifact instead.

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines the specific label names and routing messages to use.

---

You are assigned to work on the resolved issue. The issue number determined above replaces `<N>` throughout this workflow.

## Workflow Overview

This workflow follows 7 sequential phases. Each phase produces artifacts that enable resumability - if interrupted, check which artifacts exist to determine where to resume.

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Context Injection | Surface design context before work begins | `IMPLEMENTATION_CONTEXT.md` (ephemeral) |
| 1. Setup | Branch creation, baseline establishment | `wip/issue_<N>_baseline.md` |
| 2. Introspection | Validate issue spec is still current | `wip/issue_<N>_introspection.md` (if needed) |
| 3. Analysis | Research, planning, design decisions | `wip/issue_<N>_plan.md` |
| 4. Implementation | Iterative coding with validation | Working code + commits |
| 5. Finalization | Summary, cleanup, verification | `wip/issue_<N>_summary.md` |
| 6. Pull Request | PR creation, CI monitoring | Merged PR with passing CI |

## Resume Logic

Before starting, determine current phase by checking artifacts (files or git commits):

```
if wip/IMPLEMENTATION_CONTEXT.md exists → Resume at Phase 1 (context already extracted)
if cleanup commit exists (wip deleted) → Resume at Phase 6 (PR)
if summary commit exists → Resume at Phase 6
if implementation commits exist after plan → Resume at Phase 4 or 5
if plan commit exists → Resume at Phase 4
if introspection commit exists → Resume at Phase 3
if baseline commit exists → Resume at Phase 2
else → Start at Phase 0
```

To check commits:
```bash
git log --oneline --grep="issue-<N>"
```

Artifacts are preserved in git history even after file deletion. Check both file existence AND commit history for accurate resume detection.

## Execution

If your project's extension file defines a language skill or PR creation skill, invoke those now for project-specific quality and PR requirements. Then execute phases sequentially:

0. **Context Injection**: Surface design context before implementation
   - Purpose: Provide implementer with design rationale, dependencies, integration requirements
   - Instructions: `references/phases/phase-0-context-injection.md`

1. **Setup**: Create feature branch and establish baseline
   - Purpose: Ensure clean starting state and enable comparison of test/coverage changes
   - Instructions: `references/phases/phase-1-setup.md`

2. **Introspection**: Validate issue specification is still current
   - Purpose: Detect if issue spec may be stale and needs review before implementation
   - Instructions: `references/phases/phase-2-introspection.md`

3. **Analysis**: Research codebase and create implementation plan
   - Purpose: Design solution approach before coding, consider alternatives, identify files to modify
   - Instructions: `references/phases/phase-3-analysis.md`

4. **Implementation**: Execute plan with iterative development
   - Purpose: Implement the solution following the plan with continuous validation
   - Instructions: `references/phases/phase-4-implementation.md`

5. **Finalization**: Create summary, clean up artifacts, verify quality
   - Purpose: Document decisions made, remove temporary files, ensure all tests pass
   - Instructions: `references/phases/phase-5-finalization.md`

6. **Pull Request**: Create PR and monitor CI until passing
   - Purpose: Submit work for review and ensure all automated checks pass
   - Instructions: `references/phases/phase-6-pr.md`

## Output

A merged PR with passing CI, referenced back to the source issue.

## Begin

First, resolve the input using the Input Resolution section above. Once you have an issue number, read the issue with `gh issue view <issue-number>`. Check for blocking labels as defined in your project's label vocabulary (CLAUDE.md `## Label Vocabulary`) and stop if any are present. Otherwise, start Phase 0.

If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill proceeds with generic behavior: no language-specific quality checks, no label blocking (blocking label check is skipped if no label vocabulary is defined in CLAUDE.md).
