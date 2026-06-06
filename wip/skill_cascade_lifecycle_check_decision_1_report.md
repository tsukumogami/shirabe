# Decision Report: chain-targeted lifecycle CLI shape

## Question

What CLI shape should the chain-targeted lifecycle check take on `shirabe
validate`, given the existing whole-tree `--lifecycle <ROOT>` mode and the
need for the work-on cascade script to invoke a chain-targeted check
deterministically from a known PLAN doc path?

## Complexity

standard (Tier 3, fast path)

## Chosen Option

**A — new `--lifecycle-chain <DOC-PATH>` flag alongside existing `--lifecycle <ROOT>`.**

## Confidence

high

## Rationale

Matches three established codebase patterns:

1. **Mirrors the existing `--lifecycle` flag's shape.** The new flag is the
   chain-targeted dual of the whole-tree mode. Same verb (`validate`), same
   noun (`lifecycle`), explicit scope qualifier (`-chain`). A reader who
   knows one flag understands the other immediately.
2. **Mirrors the `--strict` flag pattern landed in issue #117.** That
   decision (DECISION-lifecycle-strict-mode-interface) chose "new flag,
   default off, surfaces in `--help`" over an env-var or combined-flag
   alternative for the same reasons that apply here: discoverability via
   `--help`, no precedence rules to remember, parallel to the existing
   flags pattern.
3. **Keeps the CI workflow's `--lifecycle .` contract unchanged.** The
   reusable workflow in `.github/workflows/lifecycle.yml` continues to
   invoke whole-tree mode without modification. The new mode is purely
   additive.

The two alternatives have meaningful downsides:

- **Option B (overload `--lifecycle` to accept directory or doc-path).**
  Saves one flag at the cost of behavioral ambiguity. The flag's name
  ("lifecycle") describes neither scope unambiguously. A user pointing the
  flag at a doc-path expects whole-tree behavior gets chain-only silently;
  this is exactly the kind of subtle behavior shift that destroys agent
  reproducibility. Error messages also become hard to write —
  "expected a directory or a doc-path" is less actionable than
  "use `--lifecycle <ROOT>` or `--lifecycle-chain <DOC>`".
- **Option C (new `validate-chain` subcommand).** The new verb misleads:
  `validate-chain` still does lifecycle validation; it does not validate
  the chain in any other sense (not against the schema, not against the
  format spec — only the lifecycle posture). The subcommand also doubles
  the top-level help surface and requires more wiring (new clap struct,
  new dispatch arm) than a flag does.

The script-side parsing the cascade does is identical under all three
options — exit code plus stderr or JSON. The shape choice is purely about
the CLI surface presented to humans and agents.

## Assumptions

- The chain-targeted mode reuses the existing `discover_chains` walker
  (which currently iterates all PLAN/ROADMAP roots in the index) by
  filtering to the chain containing the input doc-path. No new chain-
  walking logic is added; the chain-targeted mode is a filter applied
  after the index is built.
- The strict-mode behavior of the chain-targeted mode mirrors strict-
  mode of whole-tree mode: `--lifecycle-chain <DOC> --strict` re-targets
  single-pr-mid-PR to single-pr-at-merge for the matched chain only.
  Multi-pr postures are unchanged.
- The chain-targeted mode rejects non-doc-path inputs with a clear error
  (the flag's value must resolve to a file inside one of the indexed
  doc directories).

## Rejected Alternatives

- **Option B: overload `--lifecycle`.** Rejected because the runtime
  argument-shape detection introduces ambiguity in the flag's behavior
  contract, makes error messages harder to write, and silently shifts
  behavior on a typo (doc-path vs directory).
- **Option C: new `validate-chain` subcommand.** Rejected because the
  verb name misleads (the subcommand validates the chain's lifecycle, not
  the chain in some other sense), and a new subcommand requires more
  wiring than a new flag for an equivalent surface.

## Consequences

**Positive:**
- The CLI's whole-tree mode contract is unchanged. The reusable CI
  workflow and any external caller of `--lifecycle .` is unaffected.
- The cascade script's invocation is explicit: `shirabe validate
  --lifecycle-chain <plan-doc> --strict`. No mode-detection logic
  on the script side.
- `--help` surfaces both modes clearly.
- The pattern is consistent with the existing codebase idiom for
  validate-subcommand modes (per DECISION-lifecycle-strict-mode-interface).

**Negative:**
- The validate subcommand grows from one mode flag (`--lifecycle`) to
  two (`--lifecycle` and `--lifecycle-chain`). Mitigated by the new
  flag being mutually exclusive with the old one and by both being
  documented in the same `--help` section.

## Decision Record

This decision lands as a permanent ADR alongside the design's other
chosen options. See
`docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`.
