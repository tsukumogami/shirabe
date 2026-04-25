# Agent Instructions: Phase 3 Analysis

You are executing Phase 3 (Analysis) of the `/work-on` workflow. Your goal is to research the codebase and create a detailed implementation plan.

## Your Inputs

You will receive:
- Issue details (JSON from `gh issue view <N>`)
- Baseline content: retrieved via `koto context get <WF> baseline.md`
- Issue type classification: `full-plan` or `simplified-plan`
- Project skill (conditional): Language skill from the project extension file, if defined

## Your Output

Pipe the plan content directly into koto context — `koto context add`
reads from stdin, so no on-disk artifact is required:

```bash
{ printf '%s\n' "# Issue <N> Implementation Plan" ""; \
  ...assemble content... } \
  | koto context add <WF> plan.md
```

If you assemble the plan via the Write tool first, write to a transient
location under `wip/` (the workspace's non-koto scratch convention;
auto-cleaned by koto at workflow termination) and pipe via
`--from-file`:

```bash
koto context add <WF> plan.md --from-file wip/plan.md
```

Do not write to `/tmp/`. koto-managed content belongs in koto context;
`wip/` is the only legitimate intermediate.

Use the appropriate template based on issue type.

### Full Plan Template (bug, enhancement, refactor)

```markdown
# Issue <N> Implementation Plan

## Summary
<1-2 sentence description of chosen approach>

## Approach
<Brief explanation of why this approach was chosen>

### Alternatives Considered
- <Alternative 1>: <why not chosen>
- <Alternative 2>: <why not chosen>

## Files to Modify
- `path/to/file1` - <what changes>
- `path/to/file2` - <what changes>

## Files to Create
- `path/to/new_file` - <purpose>

## Implementation Steps
- [ ] <First logical unit of work>
- [ ] <Second logical unit of work>
- [ ] ...

## Testing Strategy
- Unit tests: <what to test>
- Integration tests: <if applicable>
- Manual verification: <if applicable>

## Risks and Mitigations
- <Risk 1>: <Mitigation>
- <Risk 2>: <Mitigation>

## Success Criteria
- [ ] <Specific, verifiable criterion>
- [ ] <Specific, verifiable criterion>

## Open Questions
<List any questions - if blocking, include in your summary for main chat>
```

### Simplified Plan Template (docs, config, chore)

```markdown
# Issue <N> Implementation Plan

## Summary
<1-2 sentence description>

## Approach
<Brief explanation>

## Files to Modify
- `path/to/file1.md` - <what changes>

## Files to Create
- `path/to/new_file.md` - <purpose>

## Implementation Steps
- [ ] <Step 1>
- [ ] <Step 2>

## Success Criteria
- [ ] <Verification step 1>
- [ ] <Verification step 2>

## Open Questions
<Any blocking questions>
```

## Your Tasks

### 1. Check for Already-Complete

Before investing in analysis, check whether the issue goal is already satisfied by
current code. Read the acceptance criteria from the issue (or plan outline context.md)
and verify each one against current code.

If every criterion is already met, **stop here** and return `plan_outcome: already_complete`
to the main agent. No plan file needed. This is a clean exit, not a failure.

This check is especially important for plan-backed children where a sibling may have
already implemented the needed changes.

### 2. Understand the Issue

Read the issue details and baseline to understand:
- What problem is being solved
- What acceptance criteria must be met
- What the baseline test/build status is

### 2. Read Design Context

**IMPORTANT**: Check if design context exists in koto: `koto context exists <WF> context.md`. If it does, retrieve and read it BEFORE planning: `koto context get <WF> context.md`.

This content contains design rationale, integration requirements, and constraints extracted from the design document. Use this context to ensure your implementation plan:
- Aligns with the broader design intent
- Considers stated integration points
- Respects documented constraints
- Addresses the "why" behind the issue, not just the "what"

If the key doesn't exist, the issue is likely standalone (no upstream design).

### 3. Explore the Codebase

Use Glob, Grep, and Read tools to find:
- Existing patterns relevant to this issue
- Files that will likely need modification
- Similar implementations as references
- Dependencies and integration points

### 4. Design Solution

For non-trivial issues:
- Consider at least 2 approaches
- Evaluate trade-offs (complexity, maintainability, performance)
- Select the approach that best fits project conventions

### 5. Create Plan

Write the implementation plan using the appropriate template for the issue type.

Ensure:
- All sections appropriate for issue type are present
- Files to modify/create are identified with specific changes
- Implementation steps are ordered logically
- Testing strategy included (full plan only)
- Design context is reflected in the approach (if context.md exists in koto context)
- No blocking questions remain unanswered

### 6. Classify Issue Type

Confirm the issue type for the main agent to include in evidence:
- `code` — changes to executable source, tests, CI configs; full scrutiny/review/QA
- `docs` — markdown, design docs, skills, spec files; skips code review panels
- `task` — operational work (run scripts, commands) with no review artifact

If the plan context supplied an `ISSUE_TYPE` hint, use it unless your assessment
clearly differs. Note any override in your summary.

### 7. Return Summary

Return to main chat with a brief summary (2-3 sentences):
- How many files identified for modification/creation
- Which approach was chosen and why
- Confirmed issue type (`code`, `docs`, or `task`)
- Any blocking questions

**Do NOT return the full plan content** - it's in the file.

## Success Criteria

Your plan is complete when:
- [ ] Plan has all appropriate sections for issue type
- [ ] At least 2 alternatives considered (if non-trivial)
- [ ] Files to modify/create identified with specific changes
- [ ] Implementation steps are ordered and actionable
- [ ] Testing strategy present (full plan only)
- [ ] No blocking questions remain
