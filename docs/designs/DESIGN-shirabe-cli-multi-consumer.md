---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-shirabe-cli-multi-consumer.md
problem: |
  The `validate` command emits GitHub Actions annotations only, runs every
  applicable check as one monolithic pass, and returns a 0/1 exit code.
  Three consumers (CI, the workflow skills, local hooks) need a wider,
  stable surface, and the annotation output CI depends on must not change.
decision: |
  Add an output-mode selector (annotation default, plus json and human),
  a versioned JSON result schema, per-check selection over the existing
  check codes, a validate exit-code contract aligned with the
  transition/finalize-chain scheme, and an install-hooks subcommand --
  layered over the existing engine without touching the annotation bytes.
rationale: |
  Reusing the existing check registry and the established exit-code scheme
  keeps the change additive and coherent across commands; defaulting to
  annotation output and holding it to a byte-parity bar preserves the live
  CI consumer while the other two consumers gain the surface they need.
---

# DESIGN: Multi-consumer CLI contract and UX

## Status

Proposed

## Context and Problem Statement

The `validate` command in `crates/shirabe` is a thin wrapper over the
`shirabe-validate` engine crate. Today it collects a `Vec<ValidationError>`
from `validate_file` (and the lifecycle modes), formats each into a GitHub
Actions annotation (`::error file=...,line=...::message` /
`::notice ...`), prints them to stdout, and returns `ExitCode::SUCCESS` or
`ExitCode::FAILURE` -- a 0/1 result driven by whether any error-level
annotation was emitted.

That single shape is the technical obstacle to the command serving more
than CI. Three callers want the same checks but cannot use this surface:

- The workflow skills shell out and read the exit code as a verdict, but
  have no structured result to parse (only annotation text) and cannot
  distinguish "found violations" from "the tool could not run" because the
  exit code is 0/1.
- Local pre-commit hooks have nothing to scaffold them.
- Ad-hoc local runs cannot select one check and get annotation syntax in
  the terminal instead of human-readable output.

The raw material is already present. The engine emits results carrying a
named check code, a severity, a message, and a file/line. The check codes
(the FC-, R-, L-families, SCHEMA, FC-CONVENTIONS) are addressable strings.
The sibling commands `transition` and `finalize-chain` already return a
multi-level exit code (0 success, 1 tool-error, 2 lifecycle-violation, 3
I/O). The CI workflow already computes the changed-file set and passes
paths in; the CLI does not own git-diff. The technical problem is to layer
output modes, per-check selection, a richer exit-code contract, and a hook
installer over this existing engine without disturbing the annotation
bytes CI consumes.

## Decision Drivers

- **Annotation parity is non-negotiable.** CI consumes the current
  annotation bytes; the annotation mode must stay byte-for-byte identical
  (PRD R3, R10), held to a parity corpus.
- **Coherence with existing commands.** The validate exit-code scheme
  should match `transition`/`finalize-chain` so a consumer learns one
  contract (PRD R6).
- **Additive over rewrite.** The engine's check dispatch and result types
  already exist; the change should layer on top rather than restructure
  the engine.
- **Parseable without scraping.** The machine-readable mode must be
  consumable by a skill without parsing annotation text, and versioned so
  consumers can pin it (PRD R1, R11).
- **Orchestrator owns paths.** The CLI keeps taking explicit paths; it
  never reads git history to discover files (PRD R9).
- **Safe-by-default hook install.** The install-hooks command must not
  clobber an existing hook without an explicit opt-in (PRD R7).
- **Public visibility.** No private references in the artifact.
