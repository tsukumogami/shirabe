## Summary

The work-on skill currently writes workflow context (baselines, plans, summaries,
introspection reports) directly to `wip/` in the filesystem. koto now owns workflow
context through a CLI interface (`koto context add/get/exists/list`), and templates
support content-aware gates (`context-exists`, `context-matches`). work-on should
migrate from direct filesystem access to koto's content API.

## What changed in koto

koto PR tsukumogami/koto#84 added:

- `koto context add <session> <key> [--from-file <path>]` — submit content
- `koto context get <session> <key> [--to-file <path>]` — retrieve content
- `koto context exists <session> <key>` — check key presence (exit 0/1)
- `koto context list <session> [--prefix <prefix>]` — list keys as JSON
- Content-aware gate types: `context-exists`, `context-matches`
- `{{SESSION_NAME}}` runtime variable for templates

Content is stored opaquely by koto in `ctx/` with a manifest. Agents don't write
files to the session directory directly.

## Current wip/ artifacts in work-on

| Phase | Artifact | Key mapping |
|-------|----------|-------------|
| Phase 0 | `wip/IMPLEMENTATION_CONTEXT.md` | `context.md` |
| Phase 1 | `wip/issue_<N>_baseline.md` | `baseline.md` |
| Phase 2 | `wip/issue_<N>_introspection.md` | `introspection.md` |
| Phase 3 | `wip/issue_<N>_plan.md` | `plan.md` |
| Phase 5 | `wip/issue_<N>_summary.md` | `summary.md` |

## Migration scope

1. **Phase file updates**: Replace `wip/` file writes with `koto context add`
   and reads with `koto context get --to-file` in each phase reference file
2. **Resume logic**: Replace `if wip/<artifact> exists` checks with
   `koto context exists <session> --key <key>`
3. **Template updates**: If work-on has a koto template with gates, migrate to
   content-aware gate types
4. **Cleanup**: Remove wip/ cleanup steps (koto handles cleanup on terminal state)

## Acceptance criteria

- [ ] All phase files use `koto context add/get/exists` instead of direct wip/ writes
- [ ] Resume logic uses `koto context exists` instead of filesystem checks
- [ ] No remaining `wip/` path references in work-on skill files
- [ ] Skill works end-to-end with koto's content ownership
