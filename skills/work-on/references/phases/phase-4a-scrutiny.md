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

When a blocking finding sends the work back, clear the panel verdicts before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=scrutiny_outcome
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

Why removal rather than leaving the old verdict to be overwritten: the `scrutiny_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass, and the panel can advance on a review of code the coder agent has since changed. Removing the key makes the gate demand this round's artifact — the refusal is the state machine's, not a matter of remembering to submit the right outcome.

All three keys go, not only this panel's. A `blocking_retry` returns to `implementation` and the run walks forward from there into every panel at or above this one, so the fixes invalidate the verdicts the other panels recorded even though they passed and raised nothing.

Do not guard the removals with `koto context exists`. `koto context remove` is idempotent — removing a key no phase has written yet exits 0 — so there is nothing for a guard to protect against, and `exists` reports absent for a store it cannot read as well as for a key that is not there. A guard would skip a key whose verdict is really still in place, which is the failure this block exists to prevent.

The check after each removal is the part that must not be dropped. A removal that fails leaves the key present and the gate satisfied, which is indistinguishable from a successful one at the point it matters. `koto context exists` and the `context-exists` gate evaluator call the same function, so "exists reports absent" is the gate's own condition rather than a proxy for it.

Then spawn all three reviewers again. When the fresh round comes back with every `blocking_count: 0`, run the Aggregation command above with `<N>` set to this round's number. If it still finds blocking findings, run this block again, or escalate as described below.

## Escalation

If a blocking finding cannot be resolved (after 2+ retry cycles), submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
