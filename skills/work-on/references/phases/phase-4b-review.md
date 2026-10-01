# Phase 4b: Code Review

Run three parallel code reviewers after scrutiny passes. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to QA validation.

## Reviewers

Spawn all three simultaneously using the Task tool:

- **Pragmatic reviewer**: Is the implementation simple? Does it avoid over-engineering, dead code, and scope creep?
- **Architect reviewer**: Does the implementation fit the design structure? Are interface contracts and dependency directions correct?
- **Maintainer reviewer**: Can the next developer understand and modify this code? Are naming, implicit contracts, and context clear? Where a non-obvious decision was made — an approach rejected, a constraint forcing a shape, a load-bearing ordering — does a comment record *why*, and is it still true of the code beside it? A stale why-comment is worse than none.

## Which Seats Run

On entering `review`, koto runs `scripts/panel-scope.sh --plan review` and writes `review_scope.json`, one decision per seat: `full`, `recheck`, `rerun` or `keep`. Spawn only the seats that aren't `keep`, whatever the Reviewers section above says about spawning all three (a kept seat counts as passed at aggregation), and give a `recheck` seat only its `findings` and the fix diff (`git diff <fix_diff_from> HEAD`). When every seat is `keep`, koto writes a carried `review_results.json` and moves on to `qa_validation` without stopping here. `phase-4a-scrutiny.md` explains each decision and why the scope is the script's to set.

```bash
koto context get <WF> review_scope.json
```

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "pragmatic",
  "blocking_count": 0,
  "advisory_count": 2,
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"summary": "<one line>", "path": "src/a.sh", "lines": "12"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` and `findings` mean what they mean in `phase-4a-scrutiny.md`: what the verdict rests on, which decides whether a later fix re-runs this seat, and each blocking finding with its location.

Delete the detail files once the round is aggregated; anything worth keeping goes into `review_results.json`.

## Aggregation

After every spawned seat returns, record the round, passed and blocking seats alike, exactly as `phase-4a-scrutiny.md` describes, with `review` as the panel:

```bash
ROUND=$(mktemp)
# write the JSON array of spawned seats to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record review <WF> "$ROUND" && rm -f "$ROUND"
```

If `--record` fails, fix it and run it again before submitting anything; if it can't be fixed, submit `review_outcome: blocking_escalate`.

Then:

- If any `blocking_count > 0`: collect blocking findings and submit `review_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- If all `blocking_count: 0`: write `review_results.json` to koto context and submit `review_outcome: passed`.

```bash
koto context add <WF> review_results.json < /dev/stdin <<EOF
{"passed": true, "round": <N>, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"review_outcome": "passed"}' --no-cleanup
```

`<N>` is the number of the review round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

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
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup
```

The `review_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass and this panel can advance on a review of code the coder agent has since changed. Removing the key makes the gate demand this round's artifact.

All four keys go, not only this panel's — see `phase-4a-scrutiny.md` for why a retry raised anywhere invalidates every panel's verdict, and `summary.md` with them. The verdict ledger stays, so clearing a verdict doesn't mean re-running its seats: on the way back, scrutiny re-runs only seats whose cited scope the fix touched, and on re-entering this phase the seat that raised the finding re-checks it.

## Escalation

If a blocking finding cannot be resolved, or the retry cap in the state's directive is spent, submit `review_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
