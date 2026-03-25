# Implementation

Execute the plan from `wip/{{ARTIFACT_PREFIX}}_plan.md`.

## Design Context

If `wip/IMPLEMENTATION_CONTEXT.md` exists, review it before starting. Refer
back when making decisions to stay aligned with design intent.

## Implementation Cycle

For each step in the plan:

### A. Write Code

- One logical unit at a time
- Follow project conventions
- Keep changes focused and atomic

### B. Validate

Run the project's validation commands (from CLAUDE.md or language skill):
- Linting/formatting, type checking, unit tests

If tests fail:
- **Simple fix**: fix and re-run
- **Test bug**: update test
- **Design issue**: update plan, possibly return to analysis
- **Unclear**: launch testing agent

### C. Functional Testing

- Verify the change works as intended
- Test edge cases
- Check for regressions

### D. Write/Update Tests

- Add tests for new functionality
- Update existing tests if behavior changed

### Commit

Mark step complete in the plan: `- [x] <step>`. Commit format:
`<type>(scope): <description>`

## Coverage Tracking

If the project tracks coverage:
- Overall coverage drop: max 1%
- Per-function coverage drop: max 10%

## Implementation Review

**Self-review (always):** `git diff main...HEAD`, then re-read acceptance
criteria and verify each is satisfied.

**Agent review (non-trivial implementations):** Launch specialized agents as
needed: security, performance, testing, architecture. Check for scope shrinkage
and design intent drift.

## Evidence

- `implementation_status: complete` — all steps done, tests pass
- `implementation_status: partial_tests_failing_retry` — fixing failures (up to 3)
- `implementation_status: partial_tests_failing_escalate` — cannot fix
- `implementation_status: blocked` — external blocker
