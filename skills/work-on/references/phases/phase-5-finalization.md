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

A caveat or hedge ("experimental", "not yet handled", "known limitation") in the
issue's shipped artifacts is legitimate only where it records a human-approved deferral.
If you find yourself writing one, the matching acceptance criterion is unmet: submit
`deferral_requested` and take it through the `deferral_approval` gate rather than
shipping the caveat unapproved.
