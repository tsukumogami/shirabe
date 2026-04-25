# Phase 3 Analysis Instructions

Phase 3 of the `/work-on` workflow produces an implementation plan
from the issue and baseline. These instructions are followed by:

- A general-purpose subagent dispatched by the main agent for the
  full-plan flow (issues labeled `bug`, `enhancement`, or `refactor`).
- The main agent itself, inline, for the simplified-plan flow (issues
  labeled `docs`, `config`, `chore`, or `validation:simple`).

The work and outputs are the same in both flows; only the dispatch
mechanism differs. Any reference to "the agent" below applies to
whichever entity is running these instructions.

## Inputs Needed

The plan needs:

- Issue details (from `gh issue view <N>`)
- Baseline content (read via `koto context get <WF> baseline.md`)
- Issue type classification: `full-plan` or `simplified-plan`
- Design context (read via `koto context get <WF> context.md` if it
  exists)
- Project's language skill (full-plan only, if defined in the
  extension file)

For full-plan delegation, the main agent passes this context to the
subagent in the dispatch prompt. For simplified-plan inline, the main
agent already has it from earlier phases.

## Output

Pipe the assembled plan into koto context under the key `plan.md`.
See [`../koto-context-conventions.md`](../koto-context-conventions.md)
for the canonical ingestion pattern (stdin pipe; ephemeral
`mktemp`+`rm` alternative).

Use the appropriate template based on issue type:

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
<List any questions; flag blocking ones in the closing summary>
```

### Simplified Plan Template (docs, config, chore, validation:simple)

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

## Tasks

### 1. Check for Already-Complete

Before investing in analysis, check whether the issue goal is already
satisfied by current code. Read the acceptance criteria from the issue
(or plan outline `context.md`) and verify each one against current code.

If every criterion is already met, **stop here** and signal
`plan_outcome: already_complete`. No plan content is written. This is
a clean exit, not a failure. (Full-plan subagent: return that signal
to the main agent. Simplified-plan inline: submit it as the next koto
evidence.)

This check is especially important for plan-backed children where a
sibling may have already implemented the needed changes.

### 2. Understand the Issue

Read the issue details and baseline to understand:
- What problem is being solved
- What acceptance criteria must be met
- What the baseline test/build status is

### 3. Read Design Context

Check whether design context exists in koto:
`koto context exists <WF> context.md`. If it does, retrieve and read it
before planning: `koto context get <WF> context.md`.

This content carries design rationale, integration requirements, and
constraints extracted from the upstream design document. Use it to
ensure the plan:

- Aligns with the broader design intent
- Considers stated integration points
- Respects documented constraints
- Addresses the "why" behind the issue, not just the "what"

If the key doesn't exist, the issue is standalone (no upstream design).

### 4. Explore the Codebase

Use Glob, Grep, and Read to find:
- Existing patterns relevant to this issue
- Files that will likely need modification
- Similar implementations as references
- Dependencies and integration points

### 5. Design the Solution

For non-trivial issues:
- Consider at least 2 approaches
- Evaluate trade-offs (complexity, maintainability, performance)
- Select the approach that best fits project conventions

### 6. Write the Plan

Use the appropriate template above. Ensure:

- All sections appropriate for the issue type are present
- Files to modify/create are identified with specific changes
- Implementation steps are ordered logically
- Testing strategy included (full plan only)
- Design context is reflected in the approach (when `context.md`
  existed)
- No blocking questions remain unanswered

### 7. Classify Issue Type

Confirm the issue type to be included in the next evidence submission:

- `code` — changes to executable source, tests, or CI configs; runs
  through scrutiny / review / QA
- `docs` — markdown, design docs, skills, or spec files; skips code
  review panels
- `task` — operational work (run scripts, commands) with no review
  artifact; skips code review panels

If the plan context supplied an `ISSUE_TYPE` hint, use it unless the
assessment clearly differs. Note any override in the closing summary.

### 8. Closing Summary

Produce a brief summary (2-3 sentences) covering:

- How many files identified for modification/creation
- Which approach was chosen and why
- Confirmed `issue_type` (`code`, `docs`, or `task`)
- Any blocking questions

**Do not include the full plan content** — that's in koto context.

For full-plan delegation: return this summary to the main agent.
For simplified-plan inline: this becomes the rationale on the next
`koto next` evidence submission.

## Success Criteria

The plan is complete when:

- [ ] Plan has all appropriate sections for the issue type
- [ ] At least 2 alternatives considered (full plan, non-trivial issues)
- [ ] Files to modify/create identified with specific changes
- [ ] Implementation steps are ordered and actionable
- [ ] Testing strategy present (full plan only)
- [ ] No blocking questions remain
