# Design Summary: shirabe-cli-rust-rewrite

## Input Context (Phase 0)

**Source:** Freeform topic; upstream is GitHub issue
[tsukumogami/vision#506](https://github.com/tsukumogami/vision/issues/506) —
SR1 of `ROADMAP-shirabe-rust-consolidation` and Building Block 1 of
`STRATEGY-shirabe-rust-consolidation`.

**Problem:** Translate shirabe's deterministic surface (the `validate`
CLI, 1,417 LOC across `cmd/shirabe/` + `internal/validate/` +
`internal/annotation/`) from Go to Rust while preserving every byte of
the public output contract on every committed artifact in the workspace
repos consuming `validate-docs.yml`.

**Constraints:**
- Byte-for-byte preservation of GHA annotations, exit codes,
  `--version` template, install.sh URL contract, release asset names.
- Per-field line numbers in FC02/FC03/R6 annotations (today provided
  by `yaml.v3`'s `Node.Line`; the Rust parser must give the same).
- No v2 break window; the rewrite is a substrate swap, not a feature
  release.
- Workspace-from-day-one crate layout so SR4 (library-crate boundary)
  does not require an import-path reorganization.
- Eval suite passes unchanged; existing Go test logic ports to Rust.

## Decisions Locked in Phase 0 Skeleton

The team-lead brief, the strategy, the roadmap, and the issue body
together pre-specified the four substantive technical decisions plus
the timing question for Block 6:

1. **YAML parser** — saphyr (line-aware Rust YAML parser, successor
   to yaml-rust2). Resolves the strategy's 80%-of-risk item.
2. **CLI framework** — clap v4 with derive macros. Mechanical mapping
   from cobra.
3. **Output-contract preservation** — golden-output test fixture
   committed at `tests/fixtures/golden/`, asserts byte equality of
   stdout/stderr/exit against a captured `shirabe-go-v0.6.1` baseline
   on every workspace artifact.
4. **Crate layout** — Cargo workspace with `crates/shirabe-validate`
   (library, internal-shaped public) and `crates/shirabe` (binary)
   from day one.
5. **Block 6 metrics subcommand** — follow-on PR (matches roadmap
   default).

## Security Review (Phase 5)

**Outcome:** Option 2 — Document considerations.
**Summary:** Design's posture is preservation; the Go binary's
sanitization, subprocess invocation pattern, and minimal data
exposure all carry over. Three refinements added to Security
Considerations: supply-chain note on saphyr 0.0.x pinning, explicit
documentation of FC03's body-echo behavior, and explicit panic-to-
stderr framing. No design changes required.

## Current Status

**Phase:** 5 — Security — complete; moving to Phase 6 (Final Review)
**Last Updated:** 2026-05-30

## Phase 1 Plan

The four substantive decisions are pre-resolved by the strategy's
specification of the problem. Phase 1 will document them as the
decomposition (one decision question per item), Phase 2 will run the
decision skill on each to validate the chosen answer holds up under
the framework, and Phase 3 will cross-validate (e.g., saphyr +
workspace layout + clap interact cleanly; no parser choice forces a
different CLI surface).

## Peer Review Plan

- **vision-maintainer** — already messaged about the STRATEGY
  Accepted→Active transition. Awaiting ack.
- **pragmatic-reviewer** — consult on Decision 1 (parser choice) and
  Decision 4 (workspace layout) once Phase 2 wraps.
- **architect-reviewer** — consult after Phase 4 (Solution
  Architecture).
- **maintainer-reviewer** — consult in Phase 6 before finalizing.
- **team-lead** — message at Phase 6 completion before opening the PR.
