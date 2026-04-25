# Koto Context Ingestion Conventions

This file is the single authoritative description of how the
`/work-on` phases (and other koto-driven shirabe skills) move
artifacts into koto context. The underlying rule lives in shirabe's
`CLAUDE.md` § "Intermediate Storage"; this file is the operational
pattern.

## Preferred: pipe via stdin

`koto context add` reads from stdin. Assemble content in the same
shell invocation:

```bash
{ printf '%s\n' "# <Title>" ""; \
  ...assemble content... } \
  | koto context add <WF> <key>
```

This is the canonical pattern (per koto's `cli-usage.md` guide). No
on-disk artifact exists at any point.

## Alternative: ephemeral disk path with cleanup

If the agent prefers to assemble content via the Write tool first,
write to a `mktemp`-produced ephemeral path, ingest via `--from-file`,
then delete:

```bash
TMP=$(mktemp); ...write content to "$TMP"...
koto context add <WF> <key> --from-file "$TMP"
rm "$TMP"
```

The invariant from `CLAUDE.md`: no persistent on-disk shadow of
koto-managed content. Either rely on an auto-wiped location (`/tmp/`,
`$TMPDIR`, `mktemp`) or delete explicitly after ingestion.

## What not to do

- **Do not stage artifacts in `wip/`.** `wip/` is git-tracked and
  reserved for non-koto workflows. koto-driven workflows store
  reviewable artifacts in koto context (cloud-backed) instead.
- **Do not write to a persistent path under `/tmp/` without cleanup**
  (e.g., `/tmp/koto-<WF>/baseline.md`). Even though `/tmp/` is
  auto-wiped on reboot, persistent per-session subdirectories create
  collision-prone shadows during the workflow's lifetime.

See also: `CLAUDE.md` § "Intermediate Storage" for the underlying rule.
