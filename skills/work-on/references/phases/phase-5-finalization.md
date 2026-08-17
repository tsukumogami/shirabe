# Finalization

Verify changes, create summary, clean up artifacts.

## Auto-Skip

Check CLAUDE.md label vocabulary for summary-skippable labels. Default: skip
for `docs`, `config`, `chore`, `validation:simple`; generate for `bug`,
`enhancement`, `refactor`, `security`.

## Steps

### Code Cleanup

Remove: debug statements, commented-out code, addressed TODOs, unused imports.

### Final Verification

Run complete test suite, build, linting. All must pass.

### Create Summary (if not skipped)

Pipe the summary into koto context under the key `summary.md`. See
[`../koto-context-conventions.md`](../koto-context-conventions.md)
for the canonical ingestion pattern (stdin pipe; ephemeral
`mktemp`+`rm` alternative).

Summary format:

```markdown
# Summary

## What Was Implemented
<Brief description>

## Changes Made
- `path/to/file`: <what changed>

## Key Decisions
- <Decision>: <rationale>

## Test Coverage
- New tests added: <count>
- Coverage change: <before> -> <after>

## Known Limitations
- <Limitation>

## Requirements Mapping

| AC | Status | Evidence |
|----|--------|----------|
| <criterion> | Implemented | <file:function> |
| <criterion> | Deviated | <what and why> |
```

### Commit

Commit summary: `docs: add implementation summary`

### Consider Manual Testing

Recommend `/try-it` if changes affect user-facing behavior, complex logic, or
integration between components. Skip for docs-only or config changes.

## Evidence

- `finalization_status: ready_for_pr` — every acceptance criterion is met and the
  summary exists. Reaching finalization at all means verification ran and passed, so
  this is backed by run verification evidence.
- `finalization_status: deferral_requested` — an acceptance criterion is unmet and you
  want to defer it. This does NOT finalize the issue; it routes to the
  `deferral_approval` human gate. A deferral is only legitimate once a human approves it
  — there is no self-reported clean deferral terminal.
- `finalization_status: issues_found` — returning to implementation.

## Retry Loop: issues_found

Returning to implementation invalidates the summary. Clear it before submitting:

```bash
OUTCOME_FIELD=finalization_status
for KEY in scrutiny_results.json review_results.json qa_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit finalization_status: ready_for_pr on the next pass."
    echo "To stop the run, submit finalization_status: deferral_requested."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"issues_found\"}"
```

Two states gate on `summary.md`, and both are covered by clearing it here. This phase is the obvious one. `deferral_approval` is the one worth naming, because it looks safe and is not: exactly one transition targets it and nothing routes back into it, so the state is entered once — but `finalization` upstream of it sits on a cycle, so that single entry can happen carrying a summary written before the fixes. What makes presence gating sound is that the key cannot survive from one evaluation of the gate into another, by any path; counting entries into the state is the wrong test.

The diagnostic names `deferral_requested` rather than an escalate outcome because `finalization` has no escalate edge. Its exits are `ready_for_pr`, `issues_found`, and `deferral_requested`, and the last is the one that still moves the run forward when the summary cannot be cleared.

The block stops if **either** signal fires — `koto context remove` reporting failure, or `koto context exists` still reporting the key present — because neither alone is enough. `exists` catches a removal that returns success without the key going away, which `remove`'s status cannot: it deletes the content file, then the lock, then the manifest, so it can report failure after the gate-relevant effect already landed. `remove`'s status catches the reverse: `ctx_exists` reports absent for a store it cannot READ as well as for a key that is not there, so on an unreadable store `exists` says the key is gone while it is still on disk.

That second case is why this is not caution for its own sake. The gate makes the same blind read, so the advancing outcome is refused when you submit it — but koto re-evaluates that buffered evidence, and the moment the permission problem clears the run advances on the surviving artifact with no further submission. The gate agreeing with `exists` is a delay, not a defence.

The rule that falls out, and the reason there is no `exists` guard *before* the removal: `koto context exists` may be used to detect a key that is present, never to conclude one is absent.

A caveat or hedge ("experimental", "not yet handled", "known limitation") in the
issue's shipped artifacts is legitimate only where it records a human-approved deferral.
If you find yourself writing one, the matching acceptance criterion is unmet: submit
`deferral_requested` and take it through the `deferral_approval` gate rather than
shipping the caveat unapproved.
