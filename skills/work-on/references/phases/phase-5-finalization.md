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

Pipe the summary directly into koto context — `koto context add` reads
from stdin, so no on-disk artifact is required:

```bash
{ printf '%s\n' "# Summary" ""; \
  ...assemble content... } \
  | koto context add <WF> summary.md
```

If you assemble the summary via the Write tool first, write to a
transient location under `wip/` and pipe via `--from-file`:

```bash
koto context add <WF> summary.md --from-file wip/summary.md
```

Same convention as phase-1 baseline and phase-3 plan artifacts:
koto-managed content belongs in koto context; `wip/` is the only
legitimate intermediate. Do not write to `/tmp/`.

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

Artifact cleanup is handled automatically by koto when the workflow reaches
a terminal state. No manual `rm -rf wip/` needed.

### Consider Manual Testing

Recommend `/try-it` if changes affect user-facing behavior, complex logic, or
integration between components. Skip for docs-only or config changes.

## Evidence

- `finalization_status: ready_for_pr` — clean and ready
- `finalization_status: deferred_items_noted` — proceeding with documented limitations
- `finalization_status: issues_found` — returning to implementation
