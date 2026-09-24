---
schema: design/v1
status: Accepted
problem: |
  The widgets app pins retry behavior in its own HTTP wrapper, duplicating
  logic the widgets-lib client should own.
decision: |
  Add a retry policy to the widgets-lib client, release it, then switch the
  app to the library's policy and delete the wrapper.
rationale: |
  One retry implementation, owned by the library every consumer already uses.
---

# DESIGN: Two-Repo Rollout

## Status

Accepted

## Context and Problem Statement

`acme/widgets` (the app, this repository) wraps the `acme/widgets-lib` HTTP
client in its own retry loop. Other consumers of `widgets-lib` copy the same
loop. The retry policy belongs in the library.

The change spans two repositories: `acme/widgets-lib` gains the policy, and
`acme/widgets` adopts it.

## Decision Drivers

- One retry implementation.
- The app must never build against a library version without the policy.

### Hard Constraint

Cross-repository landing order: `acme/widgets-lib` must merge and publish the
retry policy before `acme/widgets` can bump its dependency and use it. The two
changes cannot land in one pull request because they are in different
repositories.

## Considered Options

### Decision 1: Where the policy lives

Chosen: a `RetryPolicy` option on the `widgets-lib` client. Rejected: a shared
helper package, which adds a third module to version.

## Decision Outcome

Add `RetryPolicy` to `widgets-lib`, publish it, then switch the app to it.

## Solution Architecture

- `acme/widgets-lib`: `client/retry.go` adds `RetryPolicy` (max attempts,
  backoff, retryable status codes) and a `WithRetry` client option, with tests.
- `acme/widgets`: bump `widgets-lib`, replace `internal/http/retry_wrapper.go`
  with `WithRetry`, and delete the wrapper.

## Implementation Approach

1. `acme/widgets-lib`: add `RetryPolicy` and `WithRetry` with tests.
2. `acme/widgets`: bump the dependency and adopt `WithRetry`.
3. `acme/widgets`: delete the old wrapper and its tests.

## Security Considerations

None. Retry limits bound the extra requests.

## Consequences

Consumers share one retry policy. The app's next release depends on the
library release landing first.
