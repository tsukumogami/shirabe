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

- If `scenarios_failed > 0`: submit `qa_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent fixes the failing scenarios; the run then walks forward through `scrutiny` and `review` before re-entering this phase. It does not self-loop, which is why the retry clears those two panels' verdicts as well as this one's.
- If all scenarios pass: write `qa_results.json` to koto context and submit `qa_outcome: passed`.

```bash
koto context add <WF> qa_results.json < /dev/stdin <<EOF
{"passed": true, "scenarios_run": 3, "scenarios_passed": 3}
EOF
koto next <WF> --with-data '{"qa_outcome": "passed"}'
```

## Retry Loop

When a defect sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=qa_outcome
for KEY in scrutiny_results.json review_results.json qa_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit $OUTCOME_FIELD: passed on the next pass."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}"
```

The `qa_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass and this panel can advance on a test run against code the coder agent has since changed. Removing the key makes the gate demand this round's artifact.

All four keys go, not only this panel's. A retry raised here is the widest case: the run returns to `implementation` and walks forward through `scrutiny` and `review` before reaching this phase again, so both of those panels are re-entered holding verdicts about code that no longer exists. `summary.md` goes too, since the traversal continues through `verification` into `finalization`.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

## Escalation

If a defect cannot be resolved (after 2+ retry cycles), submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
