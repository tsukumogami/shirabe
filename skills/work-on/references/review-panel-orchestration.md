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
written to context. Panel states carry `override_default` so skipping is auditable via
`koto overrides list`. The retry loop is capped at 2 cycles — after 2 blocking_retry outcomes,
the next panel pass must emit `blocking_escalate`. `blocking_escalate` requires a `failure_reason`
field; omitting it prevents koto context_assignments from propagating the reason downstream.

## A retry invalidates all three verdicts

A `blocking_retry` from any panel clears `scrutiny_results.json`, `review_results.json` and
`qa_results.json` — every panel's key, not only the raising panel's. Each phase file carries the
clearing block on its own retry path; see `references/phases/phase-4a-scrutiny.md` for the
canonical copy.

All three because of where the retry goes. It returns to `implementation`, and the run walks
forward from there through `scrutiny` and `review` before reaching `qa_validation` again, so a
retry raised at any panel re-enters every panel at or above the raiser. The coder agent's fixes
change the code all three reviewed, which makes a verdict recorded by a panel that passed and
raised nothing just as stale as the one from the panel that sent the work back.

The clearing matters because each panel's gate is `context-exists`. It asks whether the key is
present, not which round wrote it, so a verdict left in context satisfies the gate on the next
pass and the panel advances without a fresh review having happened. Removing the key is what
makes the state machine refuse, rather than leaving the guarantee to the agent submitting an
outcome that describes the round that just ran.
