# Phase 4c: QA Validation

Run QA validation after code review passes. The tester agent validates that the implementation functions correctly from a user perspective, not just that unit tests pass.

## Tester Agent

Spawn the tester agent using the Task tool. The tester:
1. Reads the implementation's acceptance criteria from the issue or PLAN doc
2. Reads any project test plan
3. Exercises the implementation against the acceptance criteria
4. Reports pass/fail per AC with evidence

## Evidence Format

The tester writes full results to `wip/research/work-on_qa_<WF>.md` and returns:

```json
{
  "scenarios_run": 3,
  "scenarios_passed": 3,
  "scenarios_failed": 0,
  "detail_file": "wip/research/work-on_qa_<WF>.md"
}
```

## Aggregation

After the tester returns:

- If `scenarios_failed > 0`: spawn the coder agent with the failing scenarios, fix them, and re-enter this phase.
- If all scenarios pass: write `qa_results.json` to koto context and submit `qa_outcome: passed`.

```bash
koto context add <WF> qa_results.json < /dev/stdin <<EOF
{"passed": true, "scenarios_run": 3, "scenarios_passed": 3}
EOF
koto next <WF> --with-data '{"qa_outcome": "passed"}'
```

## Escalation

If a defect cannot be resolved (after 2+ retry cycles), submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
