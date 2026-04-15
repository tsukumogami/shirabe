# Phase 4b: Code Review

Run three parallel code reviewers after scrutiny passes. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to QA validation.

## Reviewers

Spawn all three simultaneously using the Task tool:

- **Pragmatic reviewer**: Is the implementation simple? Does it avoid over-engineering, dead code, and scope creep?
- **Architect reviewer**: Does the implementation fit the design structure? Are interface contracts and dependency directions correct?
- **Maintainer reviewer**: Can the next developer understand and modify this code? Are naming, implicit contracts, and context clear?

## Evidence Format

Each reviewer writes full findings to `wip/research/work-on_review_<focus>_<WF>.md` and returns a compact JSON summary:

```json
{
  "focus": "pragmatic",
  "blocking_count": 0,
  "advisory_count": 2,
  "summary": "<1-3 paragraphs>",
  "detail_file": "wip/research/work-on_review_pragmatic_<WF>.md"
}
```

## Aggregation

After all three return:

- If any `blocking_count > 0`: collect blocking findings, spawn the coder agent with combined feedback, and re-enter this phase.
- If all `blocking_count: 0`: write `review_results.json` to koto context and submit `review_outcome: passed`.

```bash
koto context add <WF> review_results.json < /dev/stdin <<EOF
{"passed": true, "round": 1, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"review_outcome": "passed"}'
```

## Escalation

If a blocking finding cannot be resolved, submit `review_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
