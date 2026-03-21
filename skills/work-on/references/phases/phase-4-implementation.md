# Phase 4: Implementation

Execute the implementation plan with iterative development and validation.

## Resume Check

If implementation commits exist after the plan commit:
1. Open `wip/issue_<N>_plan.md`
2. Find the first unchecked step (`- [ ]`)
3. Continue from that step

## Design Context Reference

**Before starting implementation**, review `wip/IMPLEMENTATION_CONTEXT.md` if it exists. This file contains:
- Design rationale and constraints
- Integration points and dependencies
- Exit criteria from design perspective

Refer back to this context when making implementation decisions to ensure alignment with the broader design intent. This helps prevent drift where the code technically satisfies the issue AC but misses the design purpose.

## Implementation Cycle

For each step in the implementation plan, follow the cycle below. Complete all steps before committing:

### A. Write Code

- Implement one logical unit at a time
- Follow project conventions and patterns
- Include appropriate error handling
- Keep changes focused and atomic

### B. Immediate Validation

Run the project's validation commands (from project CLAUDE.md or relevant skill):
- Linting/formatting
- Type checking (if applicable)
- Unit tests

Check your project's language skill (defined in the extension file) or CLAUDE.md for the specific commands.

**If tests fail:**
- **Simple fix**: Code bug → fix and re-run
- **Test bug**: Test expectation wrong → update test
- **Design issue**: Failure reveals flaw in approach → update plan, possibly revisit Phase 3
- **Unclear cause**: Launch testing agent to analyze failure pattern

Fix issues before proceeding. If a failure suggests the plan needs revision, update `wip/issue_<N>_plan.md` before continuing.

### C. Functional Testing

- Verify the change works as intended
- Test edge cases
- Check for regressions in related functionality

### D. Write/Update Tests

- Add tests for new functionality
- Update existing tests if behavior changed
- Ensure test coverage is maintained

### Commit

After completing A-B-C-D for a logical unit:

1. Mark the step complete in `wip/issue_<N>_plan.md`: `- [x] <step>`
2. Commit all changes including the updated plan

Commit format: `<type>(scope): <description>` with optional bullet list of accomplishments.

Commit types: `feat`, `fix`, `refactor`, `test`, `docs`

## Coverage Tracking

If the project tracks coverage:
- Check coverage after each commit
- Overall coverage drop: max 1%
- Per-function coverage drop: max 10%
- Add tests if coverage drops below threshold

## Quality Gates

Before moving to next implementation step:
- [ ] Code compiles/builds
- [ ] All tests pass
- [ ] No new linting errors
- [ ] Coverage maintained (if tracked)

## Handling Blockers

If blocked during implementation:
1. Document the blocker in `wip/issue_<N>_plan.md`
2. Ask for clarification if needed
3. Do not proceed with workarounds without confirmation

## Implementation Review

After completing all implementation steps, review the changes. The scope of review should match the complexity of the implementation.

**Self-review (always):** Review changes with `git diff main...HEAD`

**Requirements cross-reference (always):** After reviewing the diff, re-read the issue's acceptance criteria. For each AC item, verify your implementation satisfies it by identifying the specific file and function. If you deviated from any AC, note what you did instead and why. This cross-reference catches cases where the diff looks complete but a criterion was missed or weakened.

This is a self-check only -- no structured output at this stage. The structured mapping comes in Phase 5.

**Agent review (for non-trivial implementations):**

As implementation grows in complexity, the need for external review increases. Launch specialized agents based on what was implemented:

- **Security agent**: If auth, input handling, or data access was modified
- **Performance agent**: If database queries, algorithms, or hot paths were changed
- **Testing agent**: If test coverage is uncertain or edge cases are complex
- **Architecture agent**: If new patterns were introduced or structure changed significantly

Err on the side of more reviews. A 10-minute agent review can prevent hours of debugging or security incidents.

When the optional agent review triggers, the reviewing agent should also check the requirements mapping (from the Phase 5 summary) against the diff. Apply these scrutiny perspectives:
- **Scope shrinkage**: Did the implementation narrow any AC's scope? Look for tests that skip, validation that accepts everything, or features with reduced functionality.
- **Design intent**: Does the implementation match what the design doc describes, not just the AC's literal text? ACs are intentionally simple; interpret them in context of the full design.

Address feedback before proceeding. If feedback requires significant changes, return to the A-B-C-D cycle.

## Success Criteria

- [ ] All implementation steps from plan completed
- [ ] Each step follows A-B-C-D cycle
- [ ] All tests pass
- [ ] Build succeeds
- [ ] No unresolved blockers

## Next Phase

Proceed to Phase 5: Finalization (`phase-5-finalization.md`)
