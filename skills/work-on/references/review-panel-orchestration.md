# Review Panel Orchestration

After implementation completes, the workflow passes through three panel states before
finalization:

1. **scrutiny** — three parallel reviewers (completeness, justification, intent). Reference:
   `references/phases/phase-4a-scrutiny.md`. Output: `scrutiny_results.json`.
2. **review** — three parallel reviewers (pragmatic, architect, maintainer). Reference:
   `references/phases/phase-4b-review.md`. Output: `review_results.json`.
3. **qa_validation** — QA validation panel. Reference: `references/phases/phase-4c-qa.md`.
   Output: `qa_results.json`.

Each panel state accepts `passed`, `blocking_retry`, or `blocking_escalate`. A `blocking_retry`
returns to `implementation`; `blocking_escalate` routes to `done_blocked` with `failure_reason`
written to context. The retry loop is capped at 2 cycles — after 2 blocking_retry outcomes,
the next panel pass must emit `blocking_escalate`. `blocking_escalate` requires a `failure_reason`
field.

## What a blocking_retry does to the three artifacts

**A `blocking_retry` invalidates all three panel artifacts, not only the raising
phase's.** Each phase gates its `passed` transition on a `context-matches` gate
over its own results key, and the invalidation is what makes that gate fail on
re-entry — so the block that submits `blocking_retry` overwrites
`scrutiny_results.json`, `review_results.json` and `qa_results.json` with a
cleared sentinel first, reads each back, and refuses to proceed if any did not
take.

The all-three scope follows from the traversal rather than from tidiness. Every
`blocking_retry` targets `implementation`, and `implementation` routes forward
into `scrutiny` for `issue_type: code`, so a retry re-enters every panel phase
at or above the one that raised it. A retry raised in `qa_validation` walks back
through `scrutiny` and `review`, and both of those recorded their verdicts
before the code changed. Clearing only the raising phase's artifact leaves the
other gates satisfied by verdicts about code that no longer exists.

The shipped block and the reasoning behind each of its properties live in
`references/phases/phase-4a-scrutiny.md`; `phase-4b-review.md` and
`phase-4c-qa.md` carry the same block, identical below its final line.

**Panel states do not declare `override_default`.** An earlier version of this
file claimed they did, and that skipping was auditable because of it. Both
halves were wrong: koto's `built_in_default` already supplies the value for
every gate type — `{matches: true, error: ""}` for `context-matches` — and the
override resolution order is `--with-data` → `override_default` →
`built_in_default`, so `koto overrides record` and `koto overrides list` work
whether or not the block is present. The blocks were removed as redundant, and
overrides remain auditable exactly as before.
