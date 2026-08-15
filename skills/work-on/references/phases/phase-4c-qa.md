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

- If `scenarios_failed > 0`: spawn the coder agent with the failing scenarios, fix them, and submit `qa_outcome: blocking_retry` using the Retry Loop block below — not a bare `koto next`.
- If all scenarios pass: write `qa_results.json` to koto context and submit `qa_outcome: passed`.

```bash
koto context add <WF> qa_results.json < /dev/stdin <<EOF
{"passed": true, "scenarios_run": 3, "scenarios_passed": 3}
EOF
koto next <WF> --with-data '{"qa_outcome": "passed"}'
```

**This payload is not the tester's return format, and the difference matters.**
The tester returns the shape shown under Evidence Format above, which has no
`passed` key. The value written to context is the one in this block, which does.
The `qa_results` gate is `context-matches` on
`(?s)^\{.*"passed" *: *true.*\}\s*$`, so writing the tester's return JSON
straight through produces a legitimate passing artifact the gate rejects — and
koto names the failing gate without naming the pattern, so the failure reads as
mysterious. Write the payload above, carrying the tester's counts.

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
koto next <WF> --with-data '{"qa_outcome": "blocking_retry"}'
```

The block is identical in all three panel phases below its final line, and the
reasoning behind each of its four load-bearing properties — all three keys, no
`exists` guard, the read-back rather than the exit status, and stdout for both
diagnostics — is written out once in
[`phase-4a-scrutiny.md`](phase-4a-scrutiny.md). A retry raised here is the case
that makes the all-three scope obvious: the run returns to `implementation` and
walks forward through `scrutiny` and `review` before it reaches this phase
again, and both of those passed before the code changed.

## Escalation

If a defect cannot be resolved (after 2+ retry cycles), submit `qa_outcome: blocking_escalate` with `failure_reason`. The workflow routes to `done_blocked`. Include a `failure_reason` string — without it, the context_assignments block cannot propagate the reason to koto context.
