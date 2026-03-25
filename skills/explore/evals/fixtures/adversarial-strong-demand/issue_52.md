# Issue 52: Machine-readable output for tsuku list

**Reporter:** @priya-s
**Labels:** enhancement
**Status:** open

Picking up on the CSV idea from #27 and #14 — I'd extend this to support JSON too
(`tsuku list --json`). CSV for spreadsheets and JSON for programmatic use.

I work on developer tooling and need to pull tsuku inventory into our internal dashboard.
Currently I parse the human-readable output with regexes, which breaks whenever the
column widths change.

Machine-readable output would also enable scripting like:
```bash
tsuku list --json | jq '.[] | select(.version | startswith("14"))'
```
