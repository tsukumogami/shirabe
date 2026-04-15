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
koto context add <WF> scrutiny_results.json < /dev/stdin <<EOF
{"passed": true, "round": 1, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"scrutiny_outcome": "passed"}'
```

## Retry Loop

When re-entering after a blocking finding:
1. The `scrutiny_results.json` artifact may be stale — the gate will fail, prompting a fresh run.
2. Delete the stale artifact from context before re-running: `koto context remove <WF> scrutiny_results.json`
3. Spawn all three reviewers again. The coder agent's fixes should resolve the blocking findings.

## Escalation

If a blocking finding cannot be resolved (after 2+ retry cycles), submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
