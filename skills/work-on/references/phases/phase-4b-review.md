# Phase 4b: Code Review

Run three parallel code reviewers after scrutiny passes. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to QA validation.

## Reviewers

Spawn all three simultaneously using the Task tool:

- **Pragmatic reviewer**: Is the implementation simple? Does it avoid over-engineering, dead code, and scope creep?
- **Architect reviewer**: Does the implementation fit the design structure? Are interface contracts and dependency directions correct?
- **Maintainer reviewer**: Can the next developer understand and modify this code? Are naming, implicit contracts, and context clear? Where a non-obvious decision was made — an approach rejected, a constraint forcing a shape, a load-bearing ordering — does a comment record *why*, and is it still true of the code beside it? A stale why-comment is worse than none.

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

- If any `blocking_count > 0`: collect blocking findings and submit `review_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- If all `blocking_count: 0`: write `review_results.json` to koto context and submit `review_outcome: passed`.

```bash
koto context add <WF> review_results.json < /dev/stdin <<EOF
{"passed": true, "round": 1, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"review_outcome": "passed"}'
```

## Retry Loop

When a blocking finding sends the work back, clear the panel verdicts before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=review_outcome
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

The `review_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass and this panel can advance on a review of code the coder agent has since changed. Removing the key makes the gate demand this round's artifact.

All four keys go, not only this panel's — see `review-panel-orchestration.md` for why a retry raised anywhere invalidates every panel's verdict, and `summary.md` with them.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

## Escalation

If a blocking finding cannot be resolved, submit `review_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
