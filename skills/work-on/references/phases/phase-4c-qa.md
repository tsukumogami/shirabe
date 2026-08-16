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

## Retry Loop

When a defect sends the work back, clear the panel verdicts before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=qa_outcome
for KEY in scrutiny_results.json review_results.json qa_results.json; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  if koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY is still in context after koto context remove."
    echo "The stale verdict is in place and the gate will accept it."
    echo "Do NOT submit $OUTCOME_FIELD: passed on the next pass."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}"
```

The `qa_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass and this panel can advance on a test run against code the coder agent has since changed. Removing the key makes the gate demand this round's artifact.

All three keys go, not only this panel's. A retry raised here is the widest case: the run returns to `implementation` and walks forward through `scrutiny` and `review` before reaching this phase again, so both of those panels are re-entered holding verdicts about code that no longer exists.

The check after each removal is not optional: a failed removal leaves the key present and the gate satisfied, which looks exactly like success at the point it matters. Do not add a `koto context exists` guard *before* removing; `remove` is idempotent, and `exists` reports absent for an unreadable store as well as a missing key, so a guard would skip a key whose verdict is really still there.

## Escalation

If a defect cannot be resolved (after 2+ retry cycles), submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
