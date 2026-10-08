# Phase 4b: Code Review

Run three parallel code reviewers after scrutiny passes. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance: to QA validation at the `full` review level, to verification at `standard`.

## Reviewers

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Pragmatic, Architect and Maintainer run on `model: "sonnet"` with a 15-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N>`, with `--criteria <file>` in place of `--issue <N>` when the run has no GitHub issue: a plan-outline child, whose `<N>` numbers an item in its PLAN, writes its outline's acceptance criteria to the file. A seat the scope marks `recheck` gets its own packet instead, built from its findings and the fix diff: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" recheck --session <WF> --panel review --seat <seat>`.

Spawn all three simultaneously using the Task tool:

- **Pragmatic reviewer**: Is the implementation simple? Does it avoid over-engineering, dead code, and scope creep?
- **Architect reviewer**: Does the implementation fit the design structure? Are interface contracts and dependency directions correct?
- **Maintainer reviewer**: Can the next developer understand and modify this code? Are naming, implicit contracts, and context clear? Where a non-obvious decision was made — an approach rejected, a constraint forcing a shape, a load-bearing ordering — does a comment record *why*, and is it still true of the code beside it? A stale why-comment is worse than none.

## Which Seats Run

On entering `review`, koto runs `scripts/panel-scope.sh --plan review` and writes `review_scope.json`, one decision per seat: `full`, `recheck`, `rerun` or `keep`. Spawn only the seats that aren't `keep`, whatever the Reviewers section above says about spawning all three (a kept seat counts as passed at aggregation), and give a `recheck` seat the `recheck` packet on the commissioning line above, which holds only its `findings` and the fix diff (`git diff <fix_diff_from> HEAD`), and the re-check prompt in `review-seat-commissioning.md` in place of its role's prompt. When every seat is `keep`, koto writes a carried `review_results.json` and moves on (to `qa_validation`, or to `verification` at `standard`) without stopping here. `phase-4a-scrutiny.md` explains each decision and why the scope is the script's to set.

```bash
koto context get <WF> review_scope.json
```

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "pragmatic",
  "summary": "<1-3 paragraphs>",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"severity": "advisory", "summary": "<one line>", "path": "src/a.sh", "lines": "12"}],
  "detail_file": "<the reviewer's mktemp path>"
}
```

`cited` and `findings` mean what they mean in `phase-4a-scrutiny.md`: what the verdict rests on, which decides whether a later fix re-runs this seat, and every finding with its location and a `severity` of `blocking` or `advisory`. The severity is the verdict: a seat with one `blocking` finding is blocking, and a finding without a severity makes `--record` refuse the round.

Delete the detail files once the round is aggregated; anything worth keeping goes into `review_results.json`.

## Aggregation

After every spawned seat returns, record the round, passed and blocking seats alike, exactly as `phase-4a-scrutiny.md` describes, with `review` as the panel:

```bash
ROUND=$(mktemp)
# write the JSON array of spawned seats to "$ROUND"
"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/panel-scope.sh" --record review <WF> "$ROUND" && rm -f "$ROUND"
```

If `--record` fails, fix it and run it again before submitting anything; if it can't be fixed, submit `review_outcome: blocking_escalate`.

Then tick koto with nothing submitted. The `review_verdict` gate reads the ledger (`panel-scope.sh --verdict review`) and decides, as at scrutiny:

- Exit 0, every seat recorded and none blocking: koto advances (to `qa_validation`, or to `verification` at `standard`). Optionally write `review_results.json` first, as the round's summary for a reader; no gate reads it.
- Exit 1, a seat is blocking: the gate prints one `panel/blocking-finding` finding per blocking finding. Collect them and submit `review_outcome: blocking_retry` via the Retry Loop below, once the retry budget in the state's directive grants it (otherwise escalate). That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- Exit 2, the round isn't fully recorded or the ledger can't be read: record the round and tick again.

```bash
koto context add <WF> review_results.json < /dev/stdin <<EOF
{"round": <N>, "summary": "<one line per seat>"}
EOF
koto next <WF> --no-cleanup
```

`<N>` is the number of the review round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

Run this only once the retry budget in the state's directive has granted the retry. When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=review_outcome
for KEY in scrutiny_results.json review_results.json qa_results.json light_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and a later gate may accept it."
    echo "Do NOT submit $OUTCOME_FIELD: blocking_retry by hand."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup
```

No gate reads `review_results.json` for the pass any more, but a summary left in context would read as this round's on the next pass, and `finalization`'s `summary_exists` gate would accept a `summary.md` written before the fix.

Every key in the list goes, not only this panel's — see `phase-4a-scrutiny.md` for why a retry raised anywhere invalidates every panel's summary, and `summary.md` with them. The verdict ledger stays, so clearing a verdict doesn't mean re-running its seats: on the way back, scrutiny re-runs only seats whose cited scope the fix touched, and on re-entering this phase the seat that raised the finding re-checks it.

## Escalation

If a blocking finding cannot be resolved, or the retry budget in the state's directive refuses the retry, submit `review_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
