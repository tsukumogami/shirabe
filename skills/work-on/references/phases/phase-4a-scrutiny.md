# Phase 4a: Scrutiny

Run three parallel scrutiny reviewers before code review. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to the review panel.

## Reviewers

Spawn all three simultaneously using the Task tool:

- **Completeness reviewer**: Does every acceptance criterion have a corresponding implementation? Are evidence claims verifiable from the diff?
- **Justification reviewer**: Are deviations genuinely explained? Do reasons reflect real trade-offs, not shortcuts?
- **Intent reviewer**: Does the implementation match the design doc's described behavior, not just the literal AC text? Does it provide a sufficient foundation for downstream issues?

## Evidence Format

Each reviewer writes full findings to `wip/research/work-on_scrutiny_<focus>_<WF>.md` and returns a compact JSON summary:

```json
{
  "focus": "completeness",
  "blocking_count": 0,
  "advisory_count": 1,
  "summary": "<1-3 paragraphs>",
  "detail_file": "wip/research/work-on_scrutiny_completeness_<WF>.md"
}
```

## Aggregation

After all three return:

- If any `blocking_count > 0`: collect blocking findings, spawn the coder agent with combined feedback (see implementation phase), and re-enter this phase.
- If all `blocking_count: 0`: write `scrutiny_results.json` to koto context and submit `scrutiny_outcome: passed`.

```bash
koto context add <WF> scrutiny_results.json <<EOF
{"passed": true, "round": <N>, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"scrutiny_outcome": "passed"}'
```

`<N>` is the number of the scrutiny round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

When re-entering after a blocking finding:

1. Ignore whatever `scrutiny_results.json` is already in context. It describes the round that failed and says nothing about the fixes the coder agent has since made.
2. Do not try to delete it. `koto context` advertises `add`, `get`, `exists`, and `list` — koto has no verb that removes a key. A stale value is cleared by being overwritten, not by being deleted.
3. Spawn all three reviewers again. The coder agent's fixes should resolve the blocking findings.
4. When the fresh round comes back with every `blocking_count: 0`, run the Aggregation command above again with `<N>` set to this round's number. `koto context add` on a key that already exists replaces its content in place, so the key ends up holding this round's result and no earlier round's JSON survives.

If the fresh round still finds blocking findings, write nothing to context: submit `scrutiny_outcome: blocking_retry`, or escalate as described below, and leave the key as it stands. The `scrutiny_results` gate is `context-exists` — it checks that the key is present, not which round wrote it — so what keeps an earlier pass from advancing the workflow is the `scrutiny_outcome` you submit, which must always describe the round that just ran.

## Escalation

If a blocking finding cannot be resolved (after 2+ retry cycles), submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
