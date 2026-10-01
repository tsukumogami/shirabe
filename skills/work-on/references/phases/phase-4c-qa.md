# Phase 4c: QA Validation

Run QA validation after code review passes. The tester agent validates that the implementation functions correctly from a user perspective, not just that unit tests pass.

## Tester Agent

### Seat commissioning

Declared per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`:

| Seat | Subagent type | Model | Turn cap | Tools |
|---|---|---|---|---|
| Tester | `general-purpose` | `sonnet` | 30 | Read, Grep, Glob, Bash |

Pass `model: "sonnet"` on the spawn. The tester is the one code seat that executes what it reviews, so Bash runs the implementation as well as git, and its cap is the largest. Before spawning, assemble the packet:

```bash
PACKET=$("${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N>)
```

(`--criteria <file>` in place of `--issue` for a PLAN-outline child.) The prompt opens with the seat preamble from the commissioning reference, filled with `$PACKET` and the cap. Remove `$PACKET` after aggregation, with the detail file.

Spawn the tester agent using the Task tool. The tester:
1. Reads the implementation's acceptance criteria from the packet
2. Reads any project test plan
3. Exercises the implementation against the acceptance criteria
4. Reports pass/fail per AC with evidence

## Evidence Format

The tester writes full results to a `mktemp`-produced file outside the repository and returns:

```json
{
  "scenarios_run": 3,
  "scenarios_passed": 3,
  "scenarios_failed": 0,
  "detail_file": "<the tester's mktemp path>"
}
```

Delete the detail file once the round is aggregated; anything worth keeping goes into `qa_results.json`.

## Aggregation

After the tester returns:

- If `scenarios_failed > 0`: submit `qa_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent fixes the failing scenarios; the run then walks forward through `scrutiny` and `review` before re-entering this phase. It does not self-loop, which is why the retry clears those two panels' verdicts as well as this one's.
- If all scenarios pass: write `qa_results.json` to koto context and submit `qa_outcome: passed`.

```bash
koto context add <WF> qa_results.json < /dev/stdin <<EOF
{"passed": true, "round": <N>, "scenarios_run": 3, "scenarios_passed": 3}
EOF
koto next <WF> --with-data '{"qa_outcome": "passed"}' --no-cleanup
```

`<N>` is the number of the QA round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

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
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup
```

The `qa_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass and this panel can advance on a test run against code the coder agent has since changed. Removing the key makes the gate demand this round's artifact.

All four keys go, not only this panel's. A retry raised here is the widest case: the run returns to `implementation` and walks forward through `scrutiny` and `review` before reaching this phase again, so both of those panels are re-entered holding verdicts about code that no longer exists. `summary.md` goes too, since the traversal continues through `verification` into `finalization`. Why the block checks both signals is in `phase-4a-scrutiny.md`.

## Escalation

If a defect cannot be resolved, or the retry cap in the state's directive is spent, submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
