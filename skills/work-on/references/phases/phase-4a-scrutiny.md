# Phase 4a: Scrutiny

Run three parallel scrutiny reviewers before code review. Each reviewer checks the implementation from a different angle. All three must pass for the workflow to advance to the review panel.

## Reviewers

### Seat commissioning

Each seat is declared per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`:

| Seat | Subagent type | Model | Turn cap | Tools |
|---|---|---|---|---|
| Completeness, Justification, Intent | `general-purpose` | `sonnet` | 15 | Read, Grep, Glob, Bash |

Pass `model: "sonnet"` on each spawn; a seat with no model inherits the parent's. Bash is for read-only git and the `mktemp` detail file. Before spawning, assemble the round's packet once:

```bash
PACKET=$("${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" code --session <WF> --issue <N>)
```

A plan-backed child whose criteria come from the PLAN outline passes `--criteria <file>` with the outline's acceptance criteria instead of `--issue`. A free-form run has no issue either: it writes the task description to a `mktemp` file and passes that as `--criteria`. The same substitutions apply in `phase-4b-review.md`, `phase-4c-qa.md` and the implementation agent review. If the script exits 64, no base resolved: record `impl_base` as `analysis`'s fallback says (the parent of this run's first commit) and run it again. Don't spawn a seat without a packet; a seat with nothing to read is the unbounded exploration the packet exists to prevent. Every prompt opens with the seat preamble from the commissioning reference, filled with `$PACKET` and the cap; don't paste the diff or the issue into the prompt. Remove `$PACKET` after aggregation, with the detail files.

Spawn all three simultaneously using the Task tool:

- **Completeness reviewer**: Does every acceptance criterion have a corresponding implementation? Are evidence claims verifiable from the diff?
- **Justification reviewer**: Are deviations genuinely explained? Do reasons reflect real trade-offs, not shortcuts?
- **Intent reviewer**: Does the implementation match the design doc's described behavior, not just the literal AC text? Does it provide a sufficient foundation for downstream issues?

## Evidence Format

Each reviewer writes full findings to a `mktemp`-produced file outside the repository and returns a compact JSON summary:

```json
{
  "focus": "completeness",
  "blocking_count": 0,
  "advisory_count": 1,
  "summary": "<1-3 paragraphs>",
  "detail_file": "<the reviewer's mktemp path>"
}
```

Delete the detail files once the round is aggregated; anything worth keeping goes into `scrutiny_results.json`.

## Aggregation

After all three return:

- If any `blocking_count > 0`: collect blocking findings and submit `scrutiny_outcome: blocking_retry` via the Retry Loop below. That routes to `implementation`, where the coder agent takes the combined feedback; the run then walks forward and re-enters this phase. It does not self-loop.
- If all `blocking_count: 0`: write `scrutiny_results.json` to koto context and submit `scrutiny_outcome: passed`.

```bash
koto context add <WF> scrutiny_results.json <<EOF
{"passed": true, "round": <N>, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"scrutiny_outcome": "passed"}' --no-cleanup
```

`<N>` is the number of the scrutiny round that just ran: 1 the first time through, incremented on each pass through the retry loop below.

## Retry Loop

When a blocking finding sends the work back, clear every artifact the return trip invalidates before submitting the retry. Run this instead of a bare `koto next`:

```bash
OUTCOME_FIELD=scrutiny_outcome
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

Why removal rather than leaving the old verdict to be overwritten: the `scrutiny_results` gate is `context-exists`, so it asks whether the key is present and nothing else. A verdict left in context satisfies it on the next pass, and the panel can advance on a review of code the coder agent has since changed. Removing the key makes the gate demand this round's artifact — the refusal is the state machine's, not a matter of remembering to submit the right outcome.

All four keys go, not only this panel's. A `blocking_retry` returns to `implementation` and the run walks forward from there through every panel, `verification` and `finalization`, so the fixes invalidate the verdicts the other panels recorded even though they passed and raised nothing.

`summary.md` is in the list as belt and braces rather than because a panel retry normally finds one: the only route from `finalization` back to a panel is the `issues_found` edge, which clears it there. It stays because removal is idempotent and costs nothing, and because it catches the case where the finalization step was skipped. `plan.md` is deliberately NOT in the list — a code change does not invalidate the plan, and clearing it would strand a run that later re-enters `analysis`.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

The run then returns to `implementation`, and when it walks forward into this phase again, spawn all three reviewers for a fresh round. When that round comes back with every `blocking_count: 0`, run the Aggregation command above with `<N>` set to this round's number. If it still finds blocking findings, run this block again, or escalate as described below.

## Escalation

If a blocking finding cannot be resolved, or the retry cap in the state's directive is spent, submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
