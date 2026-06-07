# CLI Version Preflight

Workspace `shirabe` binary version preflight guidance for chain
authoring. Used when a skill invokes a `shirabe` subcommand whose
flag surface may have shifted between releases (e.g. `shirabe
transition` accepted different flags before v0.6.1).

This file is dereferenced on-demand by chain skills (`/scope`,
`/charter`) at the points where they invoke the CLI. Lazy-load:
the chain skill body does not contain the preflight prose, only a
pointer here when the failure surfaces.

## Why preflight matters

The workspace `shirabe` binary may not match the skill version
shipped in the active marketplace bundle. The mismatch surfaces
during chain transitions: a skill written against v0.9 calls
`shirabe transition <doc> Accepted` and the v0.6.1 binary rejects
the second positional arg because it expected `--status=Accepted`.

Two failure shapes:

1. **Unknown flag.** The binary returns `error: unexpected argument
   '<arg>'` or `unknown flag --<name>`.
2. **Silent semantic shift.** The binary accepts the invocation but
   does something subtly different (e.g. an older binary's
   transition writes to a different directory).

Preflight detects both shapes before the skill commits.

## The per-subcommand `--help` probe

Before invoking any state-changing subcommand, the skill probes
`shirabe <subcommand> --help` and greps for the flag(s) it intends
to use:

```bash
if shirabe transition --help 2>&1 | grep -qE -- '--superseded-by'; then
  # v0.7+ surface: use the flag form
  shirabe transition "$DOC" Superseded --superseded-by "$NEW"
else
  # v0.6.1 surface: fall back to manual edit
  echo "WARN: shirabe transition lacks --superseded-by; falling back to manual edit"
  # ... documented sed-edit fallback
fi
```

The probe runs once per skill invocation and caches the result.

## Workspace-binary version detection

The simplest preflight is `shirabe --version`. The output is a
single line: `shirabe <version>` (or `shirabe-unknown` for
locally-built binaries).

```bash
SHIRABE_VERSION=$(shirabe --version 2>/dev/null | awk '{print $2}')
if [ -z "$SHIRABE_VERSION" ] || [ "$SHIRABE_VERSION" = "shirabe-unknown" ]; then
  echo "WARN: shirabe binary version not detectable; falling back to per-subcommand probe"
fi
```

The version string is informational; the per-subcommand `--help`
probe is the authoritative check because shirabe releases sometimes
ship partial surface changes (e.g. one subcommand gains a flag
before the binary's minor version bumps).

## Documented manual sed-edit fallback

When the workspace binary is older than the skill's expected
surface, the skill falls back to manual file edits rather than
calling the binary. The fallback is documented per known-affected
subcommand:

### `shirabe transition` (v0.6.1 case)

For docs that need a status transition:

```bash
# Read current status from frontmatter
CURRENT=$(grep -m1 '^status:' "$DOC" | sed 's/^status:[[:space:]]*//')

# Edit frontmatter status line (line 2 is conventional)
sed -i.bak "s/^status:.*/status: $TARGET/" "$DOC"

# Edit body Status section first non-blank line
# (preserves FC03 contract; see brief-format.md FC03 contract)
# ... section-aware sed; rely on the bare-word-on-first-line shape
```

The fallback is intentionally narrow (single-doc, single-status
transitions). Workflows requiring directory moves or multi-doc
cascades require the newer binary; the fallback emits a hard error
in that case rather than silently doing the wrong thing.

### Other subcommands

For other subcommands whose surface has shifted across releases:
consult the per-release upgrade notes in `docs/guides/` or the
release-notes directory the repo's `CLAUDE.md` declares.

## Preflight order summary

1. Detect binary version (`shirabe --version`).
2. Probe target subcommand flags (`shirabe <sub> --help`).
3. If the probe matches the expected surface, invoke the binary.
4. Otherwise, fall back to the documented per-subcommand manual
   edit, or hard-error if no fallback exists.
