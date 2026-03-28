# Issue 10 Implementation Plan

## Summary
Add a shared retry utility function for shell scripts that wrap `gh` CLI calls, then integrate it into the existing scripts that make GitHub API calls.

## Approach
Create a reusable `retry` function in a shared shell library that scripts can source. This keeps the retry logic DRY and consistent across all scripts. The function will use exponential backoff with jitter to avoid thundering herd problems.

### Alternatives Considered
- **Inline retry loops in each script**: Simpler but leads to duplicated logic across `create-issue.sh`, `create-issues-batch.sh`, `apply-complexity-label.sh`, and `extract-context.sh`. Not chosen due to maintenance burden.
- **Wrapper script around gh**: A `gh-retry` wrapper binary. Not chosen because it adds PATH complexity and is harder to customize per-call.

## Files to Create
- `scripts/lib/retry.sh` - Shared retry utility function with exponential backoff

## Files to Modify
- `skills/plan/scripts/create-issue.sh` - Wrap `gh issue create` call with retry
- `skills/plan/scripts/create-issues-batch.sh` - Wrap `gh repo view`, `gh api`, and `gh issue edit` calls with retry
- `skills/plan/scripts/apply-complexity-label.sh` - Wrap `gh issue edit` and `gh label create` calls with retry
- `skills/work-on/references/scripts/extract-context.sh` - Wrap `gh issue view` call with retry

## Implementation Steps
- [ ] Create `scripts/lib/retry.sh` with configurable retry function (max retries, backoff base, jitter)
- [ ] Add unit tests for the retry function
- [ ] Integrate retry into `create-issue.sh` for the `gh issue create` call
- [ ] Integrate retry into `create-issues-batch.sh` for `gh repo view`, `gh api`, and `gh issue edit` calls
- [ ] Integrate retry into `apply-complexity-label.sh` for `gh issue edit` and `gh label create` calls
- [ ] Integrate retry into `extract-context.sh` for `gh issue view` call
- [ ] Verify all scripts still function correctly after integration

## Testing Strategy
- Unit tests: Test retry function with mock commands that fail N times then succeed
- Unit tests: Test retry function respects max retries and exits after exhaustion
- Manual verification: Run scripts in dry-run mode to confirm retry sourcing works
- Existing test suite: Run `create-issues-batch_test.sh` to verify no regressions

## Risks and Mitigations
- **Excessive retries delaying feedback**: Mitigate with sensible defaults (3 retries, short backoff)
- **Masking permanent failures**: Mitigate by only retrying on transient-looking exit codes (network errors), not auth failures
- **Breaking existing error handling**: Mitigate by preserving original exit codes on final failure

## Success Criteria
- [ ] All `gh` CLI calls in shell scripts are wrapped with retry logic
- [ ] Retry function supports configurable max attempts and backoff
- [ ] Existing tests pass without modification
- [ ] Transient failures are retried; permanent failures fail fast

## Open Questions
None - the scope is well-defined.
