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

- If any `blocking_count > 0`: collect blocking findings, spawn the coder agent with combined feedback, and submit `review_outcome: blocking_retry` using the Retry Loop block below — not a bare `koto next`.
- If all `blocking_count: 0`: write `review_results.json` to koto context and submit `review_outcome: passed`.

```bash
koto context add <WF> review_results.json < /dev/stdin <<EOF
{"passed": true, "round": 1, "blocking_count": 0}
EOF
koto next <WF> --with-data '{"review_outcome": "passed"}'
```

**The `"passed": true` field is the evidence contract, not decoration.** The
`review_results` gate is `context-matches` on
`(?s)^\{.*"passed" *: *true.*\}\s*$`, so the value written above is what the
state machine reads to decide whether this phase may advance. A different shape
produces a legitimate passing artifact the gate rejects.

## Retry Loop

Run this block when you have decided on `blocking_retry`, in place of a bare
`koto next`. **The invalidation is what makes the gate fail on re-entry.** Left
in place, the previous round's artifact still satisfies the gate, and the phase
advances on the verdict the retry existed to supersede.

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
koto next <WF> --with-data '{"review_outcome": "blocking_retry"}'
```

The block is identical in all three panel phases below its final line, and the
reasoning behind each of its four load-bearing properties — all three keys, no
`exists` guard, the read-back rather than the exit status, and stdout for both
diagnostics — is written out once in
[`phase-4a-scrutiny.md`](phase-4a-scrutiny.md). The short version: a retry
re-enters every panel phase at or above the one that raised it, so a retry
raised here leaves `scrutiny`'s verdict stale too.

## Escalation

If a blocking finding cannot be resolved, submit `review_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`.
