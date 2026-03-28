# Summary

## What Was Implemented
Added retry logic for all `gh` CLI calls across shell scripts to handle transient GitHub API failures. A shared utility library provides exponential backoff with jitter.

## Changes Made
- `scripts/lib/retry.sh`: New shared retry utility with configurable max attempts and exponential backoff
- `scripts/lib/retry_test.sh`: Unit tests for the retry function (6 test cases)
- `skills/plan/scripts/create-issue.sh`: Wrapped `gh issue create` with retry
- `skills/plan/scripts/create-issues-batch.sh`: Wrapped `gh repo view`, `gh api`, `gh issue edit`, and `gh issue view` calls with retry
- `skills/plan/scripts/apply-complexity-label.sh`: Wrapped `gh issue edit` and `gh label create` with retry
- `skills/work-on/references/scripts/extract-context.sh`: Wrapped `gh issue view` with retry

## Key Decisions
- Shared library over inline retry: Keeps logic DRY and consistent across all scripts
- Exponential backoff with jitter: Prevents thundering herd on concurrent retries
- Default 3 retries: Balances resilience with feedback latency
- Double-source guard: Prevents issues when retry.sh is sourced multiple times

## Test Coverage
- New tests added: 6 (retry_test.sh)
- Existing tests: 12 (create-issues-batch_test.sh) - all passing

## Known Limitations
- Retry applies to all failure modes, not just transient network errors. The gh CLI does not expose granular exit codes to distinguish transient from permanent failures.

## Requirements Mapping

| AC | Status | Evidence |
|----|--------|----------|
| Retry logic for flaky API calls | Implemented | scripts/lib/retry.sh |
| All gh CLI calls covered | Implemented | 4 scripts updated |
| No regressions | Verified | All 18 tests pass |
