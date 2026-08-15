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

- If any `blocking_count > 0`: collect blocking findings, spawn the coder agent with combined feedback (see implementation phase), and submit `scrutiny_outcome: blocking_retry` using the Retry Loop block below — not a bare `koto next`.
- If all `blocking_count: 0`: write `scrutiny_results.json` to koto context and submit `scrutiny_outcome: passed`.

```bash
koto context add <WF> scrutiny_results.json < /dev/stdin <<EOF
{"passed": true, "round": 1, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"scrutiny_outcome": "passed"}'
```

**The `"passed": true` field is the evidence contract, not decoration.** The
`scrutiny_results` gate is `context-matches` on
`(?s)^\{.*"passed" *: *true.*\}\s*$`, so the value written above is what the
state machine reads to decide whether this phase may advance. Improvising a
different shape — in particular writing a reviewer's own return JSON instead of
this payload — produces a legitimate passing artifact the gate rejects, and koto
names the gate without naming the pattern, so the operator is left guessing.

## Retry Loop

Run this block when you have decided on `blocking_retry`, in place of a bare
`koto next`. **The invalidation is what makes the gate fail on re-entry** — that
is the whole mechanism, not tidy-up before it. Left in place, the previous
round's artifact still satisfies the gate, and the phase advances on the verdict
the retry existed to supersede.

```bash
CLEARED='{"cleared": true, "superseded_by": "blocking_retry"}'
for KEY in scrutiny_results.json review_results.json qa_results.json; do
  printf '%s' "$CLEARED" | koto context add <WF> "$KEY" 2>/dev/null
  BACK=$(koto context get <WF> "$KEY" 2>/dev/null)
  if [ "$BACK" != "$CLEARED" ]; then
    echo "$KEY NOT cleared: read back [$BACK]"
    echo "do NOT submit a passed outcome on the next pass -- the previous round's verdict is still in place"
    exit 1
  fi
done
koto next <WF> --with-data '{"scrutiny_outcome": "blocking_retry"}'
```

Four things in that block are load-bearing.

**All three keys, not just this phase's.** A `blocking_retry` targets
`implementation`, and `implementation` routes forward into `scrutiny`, so the
run re-enters every panel phase at or above the one that raised the retry. The
code is about to change, so every panel verdict standing at this moment is
stale — including those of phases that passed this round and will not submit
anything themselves.

**No `exists` guard.** Skipping keys a phase has not written yet looks tidy and
reopens the defect: `koto context exists` cannot distinguish *absent* from
*store unreadable right now*, so a transient failure would silently skip a key
whose real verdict is still there. It buys nothing either way — `context-matches`
reports `matches: false` for an absent key and for the sentinel alike, and
`koto context add` creates a key on demand, so the loop exits 0 on a
`scrutiny`-raised retry before the other phases have run.

**The read-back is the check, not the exit status.** `koto context add`
overwriting an existing key writes the value in place and can still exit 3 on
the bookkeeping that follows, so branching on the exit code would report failure
on a write that landed. Comparing the value answers the question the contract
asks.

**Both diagnostics go to stdout.** koto floods stderr with `migration skipped`
lines, so `2>/dev/null` is the routine operator reflex — and it is what hid the
original defect here, when this step named a removal subcommand koto's context
group does not have and failed silently on every run.

Then spawn all three reviewers again. The coder agent's fixes should resolve the
blocking findings, and this round's `scrutiny_results.json` replaces the
sentinel.

## Escalation

If a blocking finding cannot be resolved (after 2+ retry cycles), submit `scrutiny_outcome: blocking_escalate` with a clear `failure_reason`. The workflow routes to `done_blocked`.
