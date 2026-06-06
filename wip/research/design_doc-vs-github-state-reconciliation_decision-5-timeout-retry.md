# Decision 5: Timeout, retry, and back-off values

## Question

PRD R8 binds single-retry-on-rate-limit-then-self-disable. PRD R15 binds "every external operation has an explicit timeout and at most a single retry on recoverable failure" but does not fix the timeout duration, the back-off interval, or what counts as a recoverable failure outside rate-limit. The sub-DESIGN settles the numbers.

## Chosen

| Knob | Value | Reason |
|---|---|---|
| Per-request timeout | 5 seconds | Covers typical `gh api` latency (median ~200ms, p99 ~2s on healthy GitHub) with headroom; well under the GitHub Actions per-job 6-hour budget; well under a developer's "feels stalled" threshold. The validator runs per-file, and the typical worst-case row count per doc is ~20, so even a fully-fanned-out file has a wall-clock ceiling of 20 * 5s = 100s on the timeout path before the rate-limit retry; in practice the timeout never fires (the cold-start of `gh` itself takes <1s). |
| Retry policy | Exactly one retry, only on `RateLimit` errors | PRD R8 mandates exactly this. The retry does not fire on `Network`, `Forbidden`, `NotFound`, or `Malformed` -- those map directly to their per-defect or self-disable outcomes (R9, R15) and do not benefit from a retry. |
| Back-off before retry | Fixed 2 seconds | GitHub's primary rate-limit window is hour-aligned; a short back-off (1-3 seconds) is enough to clear the brief secondary-rate-limit shape (>30/min on REST), but a long back-off (60s+) would block the validator. The 2s value matches the lower bound of `gh api`'s own built-in retry-on-secondary-rate-limit (which uses `Retry-After` when present, otherwise a default 60s). FC09 fixes the value at 2s to keep the per-request budget bounded. |
| Rate-limit detection signal | `gh api`'s nonzero exit code combined with a stderr substring match (`API rate limit exceeded` or `secondary rate limit`) | These are the strings `gh` itself uses. Pinning them in the subprocess client is brittle to upstream rewording; the design adds a unit test that pins the exact strings against an out-of-tree-recorded sample, and a defensive fallback that treats every nonzero-exit-with-no-other-recognized-pattern as `Network` rather than `RateLimit` (so a future `gh` change downgrades the impact -- no false rate-limit-self-disable). |
| Network-error detection | Subprocess spawn failure, subprocess timeout, or nonzero exit with a stderr that does not match the rate-limit, forbidden, or not-found patterns | Maps to `ClientError::Network`. PRD R14 says these contribute no FC09 notice for that row; the check proceeds. |
| Per-invocation request ceiling | None imposed by FC09; bounded implicitly by the corpus | PRD R15 bounds the iteration. The validator processes one doc at a time; each doc emits at most O(entity-rows) issue-state requests plus one PR-body request. The committed plan-and-roadmap corpus is on the order of 20-30 docs * ~10-20 rows each = 200-600 issue-state requests per `shirabe validate` run. The GitHub default authenticated rate limit is 5000/hour, so a full-corpus run is well within budget; the rate-limit-exhausted path is reachable only in pathological CI orchestrations or against tokens shared across many runs. |

## Alternatives considered

- **Exponential back-off (e.g., 1s, 2s, 4s, 8s).** Rejected.
  - PRD R8 mandates a single retry. Exponential implies multiple. The PRD's posture is "one retry, then self-disable so the rest of the validator continues" -- not "back off until success."

- **Read `Retry-After` from the GitHub response and obey it.** Rejected for v1.
  - `gh api` does not expose the response headers in a guaranteed-stable form to stdout. Parsing them from stderr requires regex against unstable text. Pinning the value at 2s keeps the contract simple; if a future increment wants to honor `Retry-After`, the sub-DESIGN's transport choice (Decision 1) can be revisited.

- **Per-request timeout 30s or 60s (matching `gh api`'s default).** Rejected.
  - `gh api`'s 30s default is for interactive CLI use against slow networks. The validator runs in CI on healthy networks; a 30s ceiling per request would let 20 stalled requests turn into a 10-minute wait, well beyond the "good signal for a CI check" threshold. 5s is the sub-DESIGN's call; a future tuning increment can shift it.

- **No timeout, rely on the subprocess `gh` binary's own timeout.** Rejected.
  - `gh api` has no built-in per-request timeout; it relies on the underlying HTTP library defaults (~30s connect, no read timeout). PRD R15 binds an explicit timeout per external operation; the wrapper must enforce it. The implementation uses `std::process::Command` with a wall-clock guard (spawn, sleep-or-poll, kill if the timeout elapses).

- **A configurable timeout via env var.** Rejected for v1.
  - Adds environment surface FC09 does not need. PRD R5 binds three env vars; adding a fourth (`SHIRABE_FC09_TIMEOUT`) for tuning purposes is YAGNI. If a future increment needs the knob, it can be added without breaking the contract.

## Implementation surface

The `GhSubprocessClient::fetch_issue_state` method's flow:

```
1. Spawn `gh api repos/<owner>/<repo>/issues/<n>` with stdout piped.
2. Poll completion for up to 5 seconds.
3. If timeout elapses: kill the child, return Err(Network).
4. If exit == 0: parse stdout as JSON, extract the "state" field, return Ok(Open) or Ok(Closed).
   If parse fails: return Err(Malformed(<details>)).
5. If exit != 0: read stderr; match against rate-limit patterns, then 403, then 404,
   else return Err(Network).
6. On RateLimit: caller (check_fc09) sleeps 2s and re-spawns once.
   On second RateLimit: caller emits the rate-limit skip notice and stops processing
   further rows.
```

The "caller does the retry" shape keeps `GhSubprocessClient` stateless and lets the higher-level `check_fc09` orchestrate the partial-engagement contract.

## Citation

- PRD R8 (single retry on rate-limit then self-disable), R14 (5xx and malformed inputs contribute no per-row notice), R15 (explicit timeout, at most one retry, no unbounded loops).
- Workspace handoff document Phase B ("Single retry + back-off on 429; on exhausted retries the check self-disables with the appropriate notice rather than failing").
