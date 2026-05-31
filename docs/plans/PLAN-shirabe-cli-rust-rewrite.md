---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: 7
issue_count: 5
upstream: docs/designs/DESIGN-shirabe-cli-rust-rewrite.md
---

# PLAN: shirabe CLI Rust rewrite

## Status

Active

This plan decomposes the rewrite into five outline-shaped work units corresponding
to the five sequencing phases in the upstream design's Implementation Approach.
The build-up outlines O1 (Cargo workspace) and O2 (frontmatter parser + types)
merged on their own as the Rust binary grew alongside the Go one with no
integration risk. O3–O5 ship together in **one cohesive replacement PR** per
the design's commitment ("There is no cargo feature flag. The two languages
coexist as distinct build targets during outlines 1–4; outline 5 is the cut."):
O5 is the non-revertible cut, so it cannot land separately from the checks (O3)
and CLI (O4) it deletes the Go equivalents of.

Multi-pr mode here means issue-tracked, not forced into five separate merges:
each outline is filed as a GitHub issue under milestone "Shirabe CLI Rust
Rewrite" (#7) for sub-task tracking. The issues exist so progress is visible
and reviewable at the outline granularity.

## Scope Summary

Translate shirabe's `validate` CLI and the underlying validation engine from
~1,350 LOC of Go (`cmd/shirabe/` + `internal/validate/` + `internal/annotation/`,
including the `table.go` issues-table engine added by PR #134)
to Rust as a Cargo workspace (`crates/shirabe-validate` library + `crates/shirabe`
binary), preserving the public output contract byte-for-byte, and atomically
deleting the Go source tree when the rewrite reaches parity.

## Decomposition Strategy

**Horizontal**, layer-by-layer. The design describes five components with stable
interfaces between them (workspace scaffold → frontmatter parser → checks +
annotations → CLI binary → fixtures + release). Each outline builds one layer
fully before the next starts. Walking skeleton was rejected because the design's
sequencing already constrains coexistence: outlines 1–4 build the Rust binary
alongside the Go one without integration risk (parity fixture runs against
the immutable captured baseline, not a live Go binary), and outline 5 is the
non-revertible cut.

## Issue Outlines

### Outline 1 — Cargo workspace skeleton

**Complexity:** simple
**Goal:** establish the Rust build surface alongside the existing Go build.

**Work:**
- Add `Cargo.toml` at repo root with workspace declaration.
- Create `crates/shirabe-validate/` and `crates/shirabe/` with their own
  `Cargo.toml` and empty `src/lib.rs` / `src/main.rs`.
- Add `rust-toolchain.toml` pinning a specific stable Rust version (1.81 or
  newer at implementation time per Decision 6).
- Add a CI step running `cargo build --release` and `cargo test --workspace`
  alongside the existing `go test ./...`. The Rust binary builds as
  `target/release/shirabe-rs` (non-default name) to avoid colliding with the
  Go binary at `./shirabe` during coexistence.

**Acceptance criteria:**
- [ ] `cargo build --workspace` succeeds locally and in CI.
- [ ] `cargo test --workspace` runs (passes trivially — no tests yet).
- [ ] Existing `go test ./...` continues to pass; Go binary still builds.

**Dependencies:** none.

### Outline 2 — Frontmatter parser and Doc/FormatSpec types

**Complexity:** testable
**Goal:** port the YAML frontmatter parser with per-key line-number support,
plus the Doc/FormatSpec type system.

**Work:**
- Port `internal/validate/doc.go` (types) to `crates/shirabe-validate/src/doc.rs`.
- Port `internal/validate/formats.go` (FORMATS map + `detect_format`) to
  `crates/shirabe-validate/src/formats.rs`.
- Implement `parse_doc` using `saphyr` per Decision 1, including the field→line
  reconstruction via per-key `MarkedYamlOwned` markers.
- Port `splitFrontmatter`, `parseYAMLFields`, `bodyAfterLine`, `scanBody` from
  `internal/validate/frontmatter.go`.
- Port every Go table test in `frontmatter_test.go` to `#[test]` cases. All
  must pass.
- Document the saphyr-parser `SpannedEventReceiver` backstop in module-level
  comments per Decision 1's risk-distribution framing.

**Acceptance criteria:**
- [ ] Every Go `frontmatter_test.go` case has a passing Rust equivalent.
- [ ] Per-key `Span` markers correctly populate the field→line map for FC02 and R6
  (the only checks that need them).

**Dependencies:** Outline 1.

### Outline 3 — Validation checks, issues-table engine, and annotation emitter

**Complexity:** critical
**Goal:** port the ten validation rules, the issues-table parser engine, and
the byte-precise GHA annotation emitter — the core public contract of
`shirabe validate`. This outline grew when the parity baseline moved off
`v0.6.1` to the current `main` tree (DESIGN Decision 7): PR #134 added the
FC05/FC06 issues-table checks and the `table.go` engine after the last tag,
and the Strategy/Brief formats and R8 also landed post-tag, so the port must
cover them or the Outline 5 Go-tree deletion would silently drop that surface.

**Work:**
- Port `internal/validate/checks.go` (SCHEMA, FC01–FC04, FC05, FC06, R6, R7,
  R8) to `crates/shirabe-validate/src/checks.rs`. Each check follows the
  `fn check_<name>(&Doc, &FormatSpec, &Config) -> Vec<ValidationError>` signature
  documented in §Solution Architecture. FC05/FC06 are the issues-table checks
  (header-profile conformance with a legacy-plan-table migration hint, row
  shape, and document-local dependency existence); R8 (`check_strategy_public`)
  mirrors R7 for STRATEGY docs.
- Port `internal/validate/table.go` (the issues-table parser and row
  classifier — `RowKind`, `Row`, `Table`, `parse_issues_table`, and the GFM
  pipe-table helpers) to `crates/shirabe-validate/src/table.rs`. The parser is
  total over arbitrary line input (never panics on ragged rows, unterminated
  sections, or missing separators).
- Add the `issues_table_columns` field to the Rust `FormatSpec` and populate it
  in the formats map for `roadmap/v1` (`Feature | Issues | Dependencies |
  Status`) and `plan/v1` (`Issue | Dependencies | Complexity`) — the only two
  formats with an issues table; empty for the rest. (The `FormatSpec` type and
  formats map were ported in Outline 2; this outline extends them.)
- Port `internal/validate/validate.go` (the `validate_file` entry point and
  the format-dispatch switch, including the Plan/Roadmap dispatch to FC05/FC06
  and the Strategy dispatch to R8) to `crates/shirabe-validate/src/validate.rs`.
- Port `internal/annotation/annotation.go` (`format_error`, `format_notice`,
  the GHA byte format) to `crates/shirabe-validate/src/annotation.rs`.
- Implement R6 (`check_plan_upstream`) using `std::process::Command::new("git")`
  with `ls-files --error-unmatch --` — same semantic as the Go `exec.Command`.
- Implement the hand-written `impl std::error::Error` per Decision 4's rationale
  (avoid thiserror leaking through the future-published crate boundary).
- Port every Go test in `checks_test.go` and `table_test.go` to passing Rust
  equivalents.

**Acceptance criteria:**
- [ ] Every Go `checks_test.go` and `table_test.go` case has a passing Rust
  equivalent.
- [ ] Annotation output matches Go output byte-for-byte for the unit-test corpus.
- [ ] Each check function's signature matches the §Solution Architecture
  documented convention.
- [ ] `issues_table_columns` is populated for `roadmap/v1` and `plan/v1` and
  empty for every other format, matching the Go `IssuesTableColumns` profiles.

**Dependencies:** Outline 2.

### Outline 4 — Binary crate and CLI surface

**Complexity:** testable
**Goal:** wire the clap CLI binary that drives the validate engine and
preserves the public CLI contract byte-for-byte.

**Work:**
- Implement `crates/shirabe/src/main.rs` with the clap `Cli` struct, `Commands`
  enum, and the `run` function per Decision 2's cobra → clap mapping.
- Implement `--version` with the format-matching template (must match Go's
  output byte-for-byte; consumed by the tsuku recipe).
- Implement the `--custom-statuses` 64 KiB cap (mirror the Go guard in
  `main.go`).
- Implement the exit-code contract: 1 on any error annotation; 0 otherwise;
  skip-on-unrecognized-format matches Go's `continue` behavior.
- Add a `build.rs` runtime verification check (per Decision 6) that the
  toolchain matches `rust-toolchain.toml`.
- The binary still builds as `target/release/shirabe-rs` until Outline 5.

**Acceptance criteria:**
- [ ] `shirabe-rs validate <file>` produces identical stdout/stderr/exit-code
  to `shirabe validate <file>` (Go) on the unit-test corpus.
- [ ] `shirabe-rs --version` output matches Go's byte-for-byte.
- [ ] `--custom-statuses` rejects payloads >64 KiB with the same error message
  the Go binary uses.

**Dependencies:** Outline 3.

### Outline 5 — Golden-output fixture, reusable parity workflow, and release pipeline cut

**Complexity:** critical
**Goal:** lock the byte-for-byte preservation contract via the two-layer parity
mechanism, swap the release pipeline to Cargo, and atomically delete the Go
source tree.

**Work:**
- Curate `tests/fixtures/golden/corpus/`: include shirabe's own committed
  artifacts under `docs/` (DESIGN-, PRD-, etc.); build `synthetic/` with edge
  cases enumerated in Decision 3 (sanitize coverage, FC01–FC04 failure paths,
  FC05/FC06 issues-table paths for the Roadmap and Plan profiles plus the
  legacy plan-table migration hint, R6, R7, and R8 paths, parser stress-test
  inputs, multi-line scalars, missing-frontmatter, unrecognized format,
  mismatched body status).
- Commit `tests/fixtures/capture_go_baseline.sh` (the reproducibility script).
- Run the capture script against the Go binary built locally from Decision 7's
  pinned commit (the rewrite branch's merge-base with `main`, currently
  `20fb8ed`) — not a downloaded tag — to populate
  `tests/fixtures/golden/expected/`. Commit `corpus/` and `expected/` to the
  repo.
- Implement `tests/parity_test.rs` asserting byte equality on stdout/stderr/
  exit-code per file.
- Add `.github/workflows/parity-check.yml` as a reusable workflow
  (`on: workflow_call:`) with inputs for `go-baseline-ref` and
  `corpus-glob`. The workflow builds the Go baseline from `go-baseline-ref`
  (checkout + `go build`, defaulting to the pinned commit `20fb8ed`) rather
  than downloading a release, downloads the Rust release binary, and asserts
  byte equality on caller corpora.
- Document the workflow's inputs table and failure modes per
  maintainer-reviewer's polish finding.
- Update `.github/workflows/release-binaries.yml` to use Cargo. Verify
  `cargo build --release` produces binaries that pass parity and that the
  release workflow produces matching asset names (per the existing
  `shirabe-<version>-<os>-<arch>` pattern).
- Update `.github/workflows/validate-docs.yml` build step from
  `go build ./cmd/shirabe` to `cargo build --release --bin shirabe`.
- Rename the Rust binary from `shirabe-rs` to `shirabe` in `crates/shirabe/
  Cargo.toml`.
- **Atomic deletion commit:** delete `cmd/`, `internal/`, `go.mod`, `go.sum`
  in the same commit as the binary rename. The deletion is reviewable as
  deletes-plus-one-workflow-line-change in `git log -p`.

**Acceptance criteria:**
- [ ] Every file in `tests/fixtures/golden/corpus/` produces byte-identical
  stdout/stderr/exit-code from the Rust binary as captured in `expected/`.
- [ ] `parity-check.yml` runs successfully as a reusable workflow invoked from
  a test caller workflow.
- [ ] Release pipeline produces `shirabe-<version>-<os>-<arch>` assets
  matching the Go-side asset names byte-for-asset-name.
- [ ] After the deletion commit, no `*.go`, `go.mod`, or `go.sum` files
  remain in the repo.
- [ ] `validate-docs.yml` build step uses `cargo build --release --bin shirabe`.

**Dependencies:** Outline 4.

## Implementation Issues

### Milestone: [Shirabe CLI Rust Rewrite](https://github.com/tsukumogami/shirabe/milestone/7)

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#129: [O1] Cargo workspace skeleton](https://github.com/tsukumogami/shirabe/issues/129) | None | simple |
| _Establish the Rust build surface (Cargo workspace with `shirabe-validate` library + `shirabe` binary crates, `rust-toolchain.toml`, CI step) alongside the existing Go build._ | | |
| [#130: [O2] Frontmatter parser and Doc/FormatSpec types](https://github.com/tsukumogami/shirabe/issues/130) | [#129](https://github.com/tsukumogami/shirabe/issues/129) | testable |
| _Port the YAML frontmatter parser with per-key line-number support via `saphyr`'s `MarkedYamlOwned`, plus the Doc/FormatSpec types and format-detection logic._ | | |
| [#131: [O3] Validation checks, issues-table engine, and annotation emitter](https://github.com/tsukumogami/shirabe/issues/131) | [#130](https://github.com/tsukumogami/shirabe/issues/130) | critical |
| _Port the ten validation rules (SCHEMA, FC01–FC06, R6, R7, R8), the `table.go` issues-table parser engine, and the byte-precise GHA annotation emitter; add `issues_table_columns` to the Rust FormatSpec and formats map for roadmap/v1 and plan/v1. The core public contract of `shirabe validate`._ | | |
| [#132: [O4] Binary crate and CLI surface](https://github.com/tsukumogami/shirabe/issues/132) | [#131](https://github.com/tsukumogami/shirabe/issues/131) | testable |
| _Wire the clap CLI binary, `--version` template, `--custom-statuses` 64 KiB cap, and the exit-code contract. Builds as `shirabe-rs` until O5._ | | |
| [#133: [O5] Golden-output fixture, reusable parity workflow, and release pipeline cut](https://github.com/tsukumogami/shirabe/issues/133) | [#132](https://github.com/tsukumogami/shirabe/issues/132) | critical |
| _Lock the byte-for-byte preservation contract via the two-layer parity mechanism, swap the release pipeline to Cargo, rename `shirabe-rs` → `shirabe`, and atomically delete the Go source tree._ | | |

## Dependency Graph

```mermaid
graph TD
    O1["Outline 1: Cargo workspace skeleton"]
    O2["Outline 2: Frontmatter parser + types"]
    O3["Outline 3: Checks + table engine + annotation emitter"]
    O4["Outline 4: clap CLI binary"]
    O5["Outline 5: Parity fixture + release cut"]

    O1 --> O2 --> O3 --> O4 --> O5

    classDef simple fill:#e1f5ff,stroke:#0066cc
    classDef testable fill:#fff4e1,stroke:#cc7700
    classDef critical fill:#ffe1e1,stroke:#cc0000
    class O1 simple
    class O2,O4 testable
    class O3,O5 critical
```

Strictly linear. Each outline builds on the previous. Outline 5 is the
non-revertible cut — atomic deletion of the Go source tree, release pipeline
swap, and binary rename land together.

## Implementation Sequence

**Critical path:** O1 → O2 → O3 → O4 → O5. All five outlines are on the
critical path; none can parallelize because each ports a layer the next
consumes.

**Estimated effort distribution** (per design's Defensibility Thesis Claim 3
"~1 engineer-week for the CLI proper"):

| Outline | Surface | Effort estimate |
|---------|---------|-----------------|
| O1 | Workspace scaffold | <1 day |
| O2 | Frontmatter + types (~290 LOC + tests, saphyr risk distributed) | 1–2 days |
| O3 | 10 checks + issues-table engine + annotation emitter (~1,100 LOC + tests; roughly doubled by the #134 issues-table surface) | 4–6 days |
| O4 | clap CLI + main glue (~150 LOC + tests) | 1 day |
| O5 | Fixture curation + parity workflow + release cut | 2–3 days |

**Total:** roughly 1.5 engineer-weeks of focused work. The upstream design's
"~1 engineer-week" framing predates PR #134; porting the issues-table engine
and the FC05/FC06 checks adds roughly half a week to O3 (see DESIGN Decision 7
for why the baseline moved off `v0.6.1`).

**Parallelization opportunities:** none within the plan — the chain is
strictly linear. Cross-cutting concerns the implementer can work on in
parallel with any outline:

- Updating `install.sh` to fetch the Rust release asset (no contract change;
  asset names preserved).
- Drafting release-notes wording for the eventual Go → Rust cutover release.

**Single-PR commit structure** (suggested, not prescribed):

```
1. feat(rust): bootstrap Cargo workspace with shirabe-validate + shirabe crates
2. feat(rust): port frontmatter parser and Doc/FormatSpec types
3. feat(rust): port validation checks, issues-table engine, and annotation emitter
4. feat(rust): wire clap CLI binary with --version and --custom-statuses
5. test(rust): commit golden corpus + capture baseline + parity_test
6. ci: add reusable parity-check.yml workflow
7. ci: swap release-binaries.yml and validate-docs.yml to cargo
8. chore: delete Go source tree, rename shirabe-rs to shirabe (the cut)
```

Reviewers see eight commits but one logical replacement. The cut commit
(#8) is small and obvious by design.
