# Capturing the external parity baselines

The `expected/<case>/external_rules` files for the design-document checks are
**real captures** of the external CI checks' verdicts, not hand-authored
stand-ins. They are produced ahead of time by a developer and committed; the
parity harness (`crates/shirabe/tests/absorption_parity.rs`) and CI read the
committed captures and never run the external checks.

The captured payload is only a list of rule identifiers (one per line) -- no
external script body, path, or other content is committed here.

## What is captured

Three current-model checks are captured, because each validates something a
design document still carries:

| Case prefix          | External check        | Emits   | Engine code(s)  |
|----------------------|-----------------------|---------|-----------------|
| `frontmatter-*`      | frontmatter check     | FM01-03 | FC01/FC02/FC03  |
| `sections-*`         | sections check        | SC01-03 | FC04/FC15       |
| `status-directory-*` | status-directory check| SD01-02 | L07 (lifecycle) |

`SC03` (empty Security Considerations) has no engine equivalent and is recorded
as an `external_only` divergence. `status-directory` maps to L07, a whole-tree
lifecycle check, so its case runs in `lifecycle` mode (see `cases.tsv`).

The legacy design-doc-issues checks (implementation-issues, issue-status,
cross-document strikethrough) are NOT captured: they validate a retired pattern
(the design-doc Implementation Issues table) and retire as legacy, their intent
already covered by the engine's FC05/FC06/FC09 on the PLAN/ROADMAP documents
that own issues tables today.

## Regenerating the captures

The external checks ship with a capture driver and a manifest that maps each
parity case to the check that produces its baseline. From a checkout of that
toolchain, point the driver at this directory:

```bash
capture-absorption-baseline.sh --manifest <capture-manifest> \
  <path-to-shirabe>/crates/shirabe/tests/fixtures/absorption-golden
```

The driver runs each manifested check over its corpus document and rewrites the
matching `expected/<case>/external_rules`. Re-run the parity harness afterward:

```bash
cargo test -p shirabe --test absorption_parity
```
