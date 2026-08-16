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
koto context remove <WF> summary.md >/dev/null 2>&1
if koto context exists <WF> summary.md >/dev/null 2>&1; then
  echo "summary.md is still in context after koto context remove."
  echo "The pre-fix summary is in place and the summary gates will accept it."
  echo "Do NOT submit finalization_status: ready_for_pr on the next pass."
  echo "To route to the human gate instead, submit finalization_status: deferral_requested."
  exit 1
fi
koto next <WF> --with-data '{"finalization_status": "issues_found"}'
```

Two states gate on `summary.md`, and both are covered by clearing it here. This phase is the obvious one. `deferral_approval` is the one worth naming, because it looks safe and is not: exactly one transition targets it and nothing routes back into it, so the state is entered once — but `finalization` upstream of it sits on a cycle, so that single entry can happen carrying a summary written before the fixes. What makes presence gating sound is that the key cannot survive from one evaluation of the gate into another, by any path; counting entries into the state is the wrong test.

The diagnostic names `deferral_requested` rather than an escalate outcome because `finalization` has no escalate edge. Its exits are `ready_for_pr`, `issues_found`, and `deferral_requested`, and the last is the one that still moves the run forward when the summary cannot be cleared.

The check after the removal is not optional: a failed removal leaves the key present and both gates satisfied, which is indistinguishable from success. Do not guard the removal with `koto context exists` first — `remove` is idempotent, and `exists` reports absent for an unreadable store as well as a missing key.

A caveat or hedge ("experimental", "not yet handled", "known limitation") in the
issue's shipped artifacts is legitimate only where it records a human-approved deferral.
If you find yourself writing one, the matching acceptance criterion is unmet: submit
`deferral_requested` and take it through the `deferral_approval` gate rather than
shipping the caveat unapproved.
