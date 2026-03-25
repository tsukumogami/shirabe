# Issue 63: Structured output format for list and status commands

**Reporter:** @devtools-team
**Labels:** needs-design
**Status:** open

We need structured (machine-readable) output from `tsuku list` and `tsuku status`. At minimum
CSV; ideally also JSON. This comes up repeatedly in #14, #27, and #52.

The design question is whether to add a global `--output-format` flag or per-command flags.
A global flag would also benefit other commands that print tabular data.

Marking as `needs-design` — we should decide on the output format API before implementing.

**Success criteria:**
- `tsuku list --csv` produces comma-separated name,version,source per line
- `tsuku list --json` produces a JSON array of objects with at least name and version
- Format is stable across releases (breaking changes require deprecation notice)
