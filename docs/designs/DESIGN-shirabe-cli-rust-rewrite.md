---
status: Proposed
upstream: tsukumogami/vision:docs/roadmaps/ROADMAP-shirabe-rust-consolidation.md
problem: |
  shirabe's deterministic surface (`shirabe validate` CLI, the line-number-aware
  YAML frontmatter parser, the seven validation rules, the GHA annotation
  emitter) is implemented in Go. The parent strategy commits to consolidating
  the deterministic surface in Rust so that future downstream consumers (koto
  template-script-calling, bunki crate-bundling) can link against a Rust crate
  rather than shell out across a Go-Rust seam. SR1 is the foundation block of
  ROADMAP-shirabe-rust-consolidation and must translate `cmd/shirabe/` +
  `internal/validate/` from Go to Rust while preserving the public contract
  byte-for-byte.
decision: |
  Translate the 1,417 LOC of Go (cmd/shirabe + internal/validate +
  internal/annotation) to Rust as a Cargo workspace with two crates from day
  one (a `shirabe-validate` library crate carrying the validate logic and a
  thin `shirabe` binary crate carrying the clap CLI), using saphyr for
  line-number-aware YAML parsing, clap for the cobra-equivalent CLI surface,
  and a golden-output test fixture that runs the captured Go binary and the
  new Rust binary against every committed VISION/ROADMAP/STRATEGY/PRD/DESIGN/PLAN
  artifact in the four workspace repos that consume validate-docs.yml and
  asserts byte-for-byte equality on stdout/stderr/exit-code.
rationale: |
  The workspace-from-day-one crate layout costs almost nothing now (one
  Cargo.toml split) and prevents an SR4-driven repository restructuring of
  every import path later. saphyr is the parser successor to yaml-rust2 with
  active maintenance and explicit `Span`/`marker` support on every node, so
  the field→line map shirabe needs falls out of the parse tree directly
  rather than requiring a hand-rolled second pass. clap with derive macros
  maps the cobra subcommand tree mechanically with no behavior change. The
  golden-output fixture is the operational shape of strategy Block 4
  (output-contract-preservation discipline): rather than aspirationally
  preserving the GHA annotation byte format, every PR runs both binaries
  against the workspace's real artifact corpus and diffs the output.
---

# DESIGN: shirabe CLI Rust rewrite

## Status

Proposed

## Upstream Design Reference

This design implements **SR1** of
[ROADMAP-shirabe-rust-consolidation](https://github.com/tsukumogami/vision/blob/main/docs/roadmaps/ROADMAP-shirabe-rust-consolidation.md).
The parent strategy is
[STRATEGY-shirabe-rust-consolidation](https://github.com/tsukumogami/vision/blob/main/docs/strategies/STRATEGY-shirabe-rust-consolidation.md)
(Building Block 1). The planning issue is
[tsukumogami/vision#506](https://github.com/tsukumogami/vision/issues/506).

The upstream artifacts already resolved:

- **Decision to rewrite in Rust** — locked by the strategy's Defensibility Thesis.
  This design picks *how*, not *whether*.
- **Block 4 acceptance discipline** — folded into this design's acceptance
  criteria per the roadmap's framing of SR1.
- **Block 6 metrics subcommand timing** — defaults to a follow-on PR; this
  design confirms.

This design does not duplicate strategic justification; it locks the four
technical decisions the strategy named as substantive.

## Context and Problem Statement

shirabe's deterministic surface is a small Go CLI (`shirabe`) with one
subcommand today (`validate`), backed by:

- 1,417 LOC of Go across `cmd/shirabe/main.go` (104 LOC), `internal/validate/`
  (557 LOC across `validate.go`, `checks.go`, `formats.go`, `frontmatter.go`,
  `doc.go`), `internal/annotation/annotation.go` (35 LOC), and Go-side tests
  (690 LOC across `checks_test.go` and `frontmatter_test.go`).
- Two external dependencies: `github.com/spf13/cobra` (CLI framework) and
  `gopkg.in/yaml.v3` (frontmatter parsing).
- One callable contract: GitHub Actions annotation lines on stdout
  (`::error file=<path>,line=<N>::[CODE] message` and
  `::notice file=<path>::message`), exit code 1 if any error annotation was
  emitted, zero otherwise.

The validation logic encodes five doc formats (Design, PRD, VISION, Roadmap,
Plan) and seven check rules (SCHEMA gate, FC01–FC04 frontmatter checks, R6
Plan upstream check, R7 VISION public-visibility check). Five rules need
no special handling. Two rules (FC02, FC03) and one absence-of-FC01-on-a-
specific-field path require **per-field line numbers** in the GHA annotation
so the rendered error points at the offending YAML key rather than the top
of the file. The Go implementation gets these from `yaml.v3`'s
`yaml.Node.Line` field, which is populated during decoding.

The strategy commits to consolidating shirabe's runtime substrate in Rust.
SR1 is the load-bearing piece: every other feature (SR2 transition subcommand,
SR3 cross-repo resolver, SR4 library crate, SR5 metrics) extends the Rust
binary SR1 creates. The design must answer four technical questions before
implementation can start:

1. **What Rust YAML parser provides per-key line numbers?** `serde_yaml`
   deserializes into Rust structs but discards source positions. The Go
   implementation depends on `yaml.v3`'s `Node.Line` for FC02/FC03/R6
   annotations. The strategy names this as 80% of the technical risk.
2. **How does the cobra subcommand tree translate to clap?** Mechanical, but
   the design should document the mapping so SR2/SR3/SR5 inherit a
   conventional shape.
3. **How is output-contract preservation enforced as a test?** The strategy
   commits to byte-for-byte preservation as an acceptance criterion, not
   aspiration; this design names the fixture mechanism.
4. **Single binary crate vs. Cargo workspace?** SR4 publishes a library
   crate. Anticipating SR4 from day one avoids a structural re-port at SR4
   land time.

A fifth question the roadmap surfaces — does the Block 6 `shirabe metrics`
subcommand ship inside SR1 or as a follow-on — is resolved in
**Decision 5** below.

## Decision Drivers

- **Byte-for-byte output preservation is mandatory.** Strategy Decision 3:
  no v2 break window. Every GHA annotation, every exit code, every
  `--version` byte must match the Go binary on identical inputs. The roadmap
  scopes the preservation test to "every existing committed artifact in
  workspace repos that consume `validate-docs.yml`."
- **Per-field line numbers are non-negotiable for FC02, FC03, R6.** Today's
  Go output points GHA annotations at specific frontmatter keys; the Rust
  binary must do the same on the same files. Falling back to line 1 for
  these errors would be a behavior regression.
- **The rewrite must be a non-event for the two internal pinning callers.**
  shirabe's own `.github/workflows/validate-docs.yml` and the private
  `vision` repo's caller both consume the published binary on tagged
  releases. Both must continue to pass on the day the Rust binary ships.
- **The Cargo crate must be ready for SR4 without restructuring.** The
  strategy stages library-as-amplifier (Decision 1), but Phase 5 of SR4
  shouldn't require renaming every import path. A workspace from day one
  with the validation logic in a separate crate is the cheap shape.
- **Test-suite parity, not test-suite migration.** The existing Go test
  suite (`checks_test.go`, `frontmatter_test.go`, ~690 LOC) covers all
  seven rules and the schema gate. The Rust implementation must hit the
  same logical assertions; whether it ports test-by-test or restructures
  is a tactical call inside the implementation.
- **Eval suite passes unchanged.** Strategy Decision 2 keeps
  `scripts/run-evals.sh` and per-skill JSON fixtures in their current
  substrate. The Rust binary must satisfy the existing evals as a baseline
  acceptance criterion.
- **No new runtime dependencies on the host CI environment.** The Go binary
  needs only `git` on PATH (for R6's `git ls-files`). The Rust binary
  inherits the same minimum.
- **install.sh contract preservation.** The shell installer's URL pattern
  (`shirabe-<os>-<arch>` release asset names), install path
  (`~/.shirabe/bin/shirabe`), and PATH guidance are part of the public
  contract. Cargo-built binaries must match the same asset naming convention.

## Considered Options

### Decision 1: YAML parser with per-key line numbers

**Question.** Which Rust YAML library provides per-key line/column markers
on the parsed mapping so FC02/FC03/R6 annotations can point at the
offending frontmatter field?

**Key assumptions.**
- Per-field line numbers must be accurate after the parse, with no
  separate text-scan pass over the frontmatter.
- The parser supports YAML 1.1 (which `yaml.v3` parses as a permissive
  superset today; the workspace's committed artifacts are 1.1-compatible).
- The parser is actively maintained: an unmaintained library is a future
  cost-of-delay tripwire.

**Chosen: `saphyr` (workspace-from-day-one)**.

`saphyr` is a YAML 1.2 parser that exposes per-node `Span` markers (line,
column, byte offset) on its `Marker` type, returned alongside every
key/value node. The frontmatter walker reads the mapping at the document
root, iterates `(key_node, value_node)` pairs, and produces a
`HashMap<String, FieldValue { value, line }>` — directly analogous to the
Go implementation's `parseYAMLFields`. The field→line reconstruction the
strategy named as 80% of the technical risk is a 30-line function in this
approach, not a custom parser.

**Considered and rejected.**

- *`serde_yaml` + a hand-rolled second-pass line scanner.* serde_yaml is
  the de-facto Rust YAML library and pairs cleanly with serde derive, but
  it discards source positions entirely. Recovering per-key lines would
  require a second `bufio`-style scan of the frontmatter bytes, matching
  each key string to its first occurrence. **Rejected** because matching
  keys to lines correctly across multi-line scalars, anchor/alias
  expansion, and quoted-key edge cases is exactly the kind of subtle work
  the strategy flagged as the rewrite's single non-trivial risk. Putting
  the risk in a hand-rolled scanner concentrates it; pushing it onto a
  parser that already tracks positions distributes it across the
  parser's existing test surface.
- *`yaml-rust2` (the saphyr ancestor).* yaml-rust2 also tracks per-node
  markers and would work for the line-number problem. **Rejected**
  because yaml-rust2's maintainer transitioned active development to
  saphyr (saphyr is the explicit successor crate, not a fork); picking
  yaml-rust2 today buys a known-deprecated dependency.
- *`unsafe-libyaml` (libyaml C library bindings).* libyaml is the parser
  yaml.v3 itself wraps in Go, and its emitter has bullet-proof position
  tracking. **Rejected** because the `unsafe-libyaml` binding's
  ergonomic surface is built around emitter use, not low-level token-by-
  token parsing for a small consumer; the integration cost is higher
  than saphyr's for the same line-number guarantee, and the `unsafe-`
  prefix is a non-trivial review surface for a small CLI.

**Why this isn't a strawman:** the rejected serde_yaml + hand-rolled scan
approach is the path most Rust CLI authors reach for first, and it would
plausibly work. The rejection is not because it cannot succeed — it is
because saphyr makes the same outcome free, and the strategy explicitly
warned about concentrating risk in a hand-rolled YAML reconstruction.

### Decision 2: CLI framework — cobra → clap mapping

**Question.** How does the cobra subcommand tree (`shirabe`, `shirabe
validate`, `--visibility`, `--custom-statuses`, `--version`) translate to a
clap idiom that future subcommands (SR2 `transition`, SR3
`resolve-upstream`, SR5 `metrics`) inherit cleanly?

**Key assumptions.**
- clap's `derive` macros are stable in clap v4 and are the conventional
  Rust shape (matching how cobra's struct-based config is the Go
  conventional shape).
- The subcommand surface today is tiny (one subcommand, two flags); the
  forthcoming subcommands add roughly the same shape (one subcommand each,
  a few flags each).

**Chosen: clap v4 with `derive` macros, one struct per subcommand.**

Top-level `Cli` struct with `#[derive(Parser)]`, `Commands` enum carrying
one variant per subcommand. Each variant carries a struct with the
subcommand's flags. `--version` handled via clap's built-in
`#[command(version = "...")]` attribute, with the version string injected
at build time through `build.rs` reading `CARGO_PKG_VERSION` (mirrors the
Go `-ldflags "-X main.version=…"` pattern). Custom version template
matches today's `"shirabe {{.Version}}\n"` output exactly via
`#[command(version, override_help_subcommand = false)]` and a
`format!`-based version string built in `main()` before `parse()`.

**Considered and rejected.**

- *clap v4 `builder` (procedural) API.* Same library, more imperative.
  **Rejected** because derive macros give the same surface with less
  boilerplate and they're the Rust-conventional shape for subcommand
  CLIs of this size — picking builder would surprise future maintainers
  without buying anything.
- *Hand-rolled argument parser.* Smallest possible dependency footprint.
  **Rejected** because shirabe already commits to one external dependency
  for YAML parsing (saphyr) and would gain nothing by avoiding clap; the
  cobra → clap translation is the strategy's "mechanical" item and
  picking a non-conventional approach turns mechanical work into
  exploratory work.

This decision is mechanical per the strategy. The design records the
chosen idiom so SR2/SR3/SR5 inherit a consistent pattern.

### Decision 3: Output-contract preservation mechanism

**Question.** How does the rewrite enforce byte-for-byte output
preservation against the Go binary's behavior on every committed artifact
in the workspace?

**Key assumptions.**
- The workspace repos that consume `validate-docs.yml` today are
  `tsukumogami/shirabe` itself (self-validating via
  `validate-shirabe-docs.yml`) and `tsukumogami/vision` (private,
  validated via its own `.github/workflows/validate-docs.yml`).
  Verified by `grep -l validate-docs.yml */.github/workflows/*` across
  the workspace; `koto`, `tsuku`, `niwa`, and `tools` do not pin the
  workflow today. The fixture's coverage of "real artifacts" is
  scoped to the documents under `docs/` in these two repos with a
  recognizable shirabe format prefix (DESIGN-, PRD-, VISION-,
  ROADMAP-, PLAN-, STRATEGY-). The strategy's Block 4 framing
  ("every committed artifact in workspace repos consuming
  `validate-docs.yml`") binds the scope to these two repos, not the
  full workspace; the corpus tracks the strategy's framing exactly.
- A captured Go binary at a frozen version (`v0.6.1`, the most recent
  tagged release) is the immutable reference; once captured, the fixture
  asserts against it rather than rebuilding Go each run.

**Chosen: golden-output fixture committed to the Rust repo, asserted in
CI.**

The fixture lives at `tests/fixtures/golden/` and contains:

1. `corpus/` — a snapshot of every committed artifact (frontmatter +
   body, no other content) from the two workspace repos that consume
   `validate-docs.yml` today, with their original paths preserved as
   a relative subtree (`corpus/shirabe/...`, `corpus/vision/...`).
2. `expected/` — for each corpus file, the captured stdout, stderr, and
   exit code produced by `shirabe-go-v0.6.1 validate <path>` running
   against the corpus file. The capture is regenerated by a one-shot
   script (`tests/fixtures/capture_go_baseline.sh`) committed alongside
   the fixture so the baseline is reproducible.
3. `parity_test.rs` — a `#[test]` per corpus file that runs the Rust
   binary, captures its three outputs, and asserts equality. Any
   divergence fails the test with a side-by-side diff.

The fixture is the operational implementation of strategy Block 4. Every
PR in the Rust rewrite must pass it; merging is gated on parity.

**Considered and rejected.**

- *Property-based testing against a synthesized artifact generator.*
  Generate random valid/invalid frontmatter, compare Go vs Rust output.
  **Rejected** because the realistic distribution of artifacts in the
  workspace is the surface the strategy cares about preserving — not
  every theoretically-valid YAML mapping. Property testing would surface
  the wrong failure mode (parser edge cases on synthesized inputs)
  rather than the actual failure mode (real-artifact divergence).
- *Eval-suite-only parity (rely on the existing `scripts/run-evals.sh`
  fixtures).* The eval suite already exercises the CLI on per-skill JSON
  scenarios. **Rejected** because evals exercise the CLI from the
  caller-skill perspective on synthesized fixtures, not on the
  workspace's actual document corpus. The roadmap explicitly names the
  preservation scope as "every existing committed artifact in workspace
  repos that consume `validate-docs.yml`"; evals do not cover that
  corpus.
- *Snapshot testing with `insta`.* `insta` is the Rust de-facto snapshot
  library; using it would surface diffs cleanly. **Rejected** because
  `insta` is designed for the "I changed code, accept the new snapshot"
  workflow, and the contract here is "the Go output is the snapshot;
  Rust output must never deviate." Using `insta` would conflate the two
  directions of update. A plain assertion with side-by-side diff output
  matches the actual contract.

### Decision 4: Cargo crate layout

**Question.** Is the rewrite a single binary crate (one `Cargo.toml`,
everything in `src/`) or a Cargo workspace with a separate library crate
anticipating SR4?

**Key assumptions.**
- SR4 publishes a library crate that exposes the validate API to koto and
  bunki. The API surface is "internal-shaped, public for distribution"
  until a downstream consumer locks the contract (per strategy
  Decision 1).
- Restructuring a single binary crate into a workspace later means
  changing every import path that crosses the new crate boundary; a
  workspace from day one bypasses this.

**Chosen: Cargo workspace with two crates from day one.**

```
shirabe/                         (workspace root)
├── Cargo.toml                   (workspace manifest)
├── crates/
│   ├── shirabe-validate/        (library crate)
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs           (re-exports public API)
│   │       ├── doc.rs           (Doc, FieldValue, Section, ValidationError)
│   │       ├── formats.rs       (FormatSpec, Formats map, detect_format)
│   │       ├── frontmatter.rs   (parse_doc, parse_yaml_fields via saphyr)
│   │       ├── checks.rs        (check_schema, check_fc01..04, check_plan_upstream, check_vision_public)
│   │       ├── validate.rs      (Config, validate_file, is_notice)
│   │       └── annotation.rs    (format_error, format_notice, sanitize)
│   └── shirabe/                 (binary crate)
│       ├── Cargo.toml
│       └── src/
│           └── main.rs          (clap Cli, validate_cmd, --version handling)
```

The `shirabe-validate` crate is internal-shaped (public visibility for
distribution but no API stability guarantee across versions). Its public
surface during SR1 mirrors the Go `internal/validate` exports plus
`internal/annotation`. SR4 will publish this crate to crates.io with the
same code; the publishing decision shifts, the layout does not.

**Considered and rejected.**

- *Single binary crate, restructure during SR4.* Simplest now; pushes
  the workspace decision to the moment SR4 lands. **Rejected** because
  SR4's design will then need to negotiate every import path change at
  the same time it's negotiating the library API. The strategy stages
  library-as-amplifier *publishing*, not library-as-amplifier *code
  shape*. Workspace-from-day-one separates those two questions.
- *Single binary crate with `pub mod validate`.* Use Rust's module
  system in place of a separate crate; pull `validate` into a library
  crate at SR4 land time. **Rejected** because Cargo's
  `[[bin]]`/`[lib]` distinction at SR4 still requires moving the module
  source into a new crate directory and updating every `mod`/`use`
  path. The diff is small in absolute terms but lands at exactly the
  moment SR4 needs cognitive bandwidth for the library API decisions.
- *Three crates from day one (`shirabe-validate`, `shirabe-cli`,
  `shirabe-bin`).* Pre-anticipate SR2/SR3/SR5 subcommand crates.
  **Rejected** because YAGNI: SR2/SR3/SR5 designs haven't picked
  whether they want separate crates, and the three-crate split adds
  workspace complexity for zero current benefit. Two crates is the
  minimum that bypasses the SR4 import-path churn; more is speculation.

### Decision 5: Block 6 `shirabe metrics` subcommand timing

**Question.** Does Block 6 (the cost-of-delay tripwire `shirabe metrics`
subcommand) ship inside SR1's PR, or as a follow-on once SR1 lands?

**Key assumptions.**
- The roadmap defaults to "follow-on" but allows SR1's design to confirm.
- The metrics subcommand has no behavioral overlap with `validate`; its
  output is a small JSON or text report read by a scheduled GHA, not by
  the validate-docs reusable workflow.
- The byte-for-byte preservation fixture (Decision 3) is the load-bearing
  acceptance work in SR1's PR; coupling Block 6 to that PR would either
  delay it or force a partial-completion shape.

**Chosen: follow-on PR. Block 6 ships as a separate small PR after SR1
lands.**

SR1's PR ships the workspace, the validate logic, the parity fixture, and
the install/release plumbing. The metrics subcommand lands afterward as a
SR5-tracked piece of work (the roadmap already names SR5 as the metrics
feature; it does not need to ride SR1).

The strategy and roadmap both default to this shape. The design confirms it
because conflating Block 6 with SR1 would put preservation-fixture review
attention against a feature that has no validation contract to preserve.

**Considered and rejected.**

- *Ship the metrics subcommand inside SR1's PR as a near-trivial
  addition.* The subcommand is small (the strategy estimates "a follow-
  on PR" sizing). **Rejected** because trivial-in-LOC and trivial-in-
  review-attention are different. SR1's PR reviewers are looking at the
  parity fixture; metrics would split that attention, and the metrics
  subcommand has its own design considerations (tripwire detection logic,
  output format for CI parsing) that deserve their own PR-level
  discussion.

## Decision Outcome

The rewrite ships as one PR that:

1. Adds a Cargo workspace at the repo root with two crates
   (`shirabe-validate` library, `shirabe` binary).
2. Implements the seven validation rules and the GHA annotation emitter
   in `shirabe-validate` using `saphyr` for line-aware YAML parsing.
3. Wires the clap derive-based CLI in `shirabe` to mirror the cobra
   surface exactly (one `validate` subcommand, `--visibility`,
   `--custom-statuses`, `--version` with the same template).
4. Commits the golden-output fixture under `tests/fixtures/golden/`
   covering every relevant artifact across the two workspace repos
   that consume `validate-docs.yml` today (shirabe + vision).
5. Replaces the Go release/install pipeline targets with Rust ones,
   preserving asset naming (`shirabe-<os>-<arch>`) and the install.sh
   URL/path contract.
6. Removes the Go source tree (`cmd/`, `internal/`, `go.mod`, `go.sum`)
   atomically with the Rust addition. There is no Go-Rust coexistence
   window. The release tag flips from a Go binary to a Rust binary in
   one cut.

What this PR explicitly does not do:

- Publish `shirabe-validate` to crates.io. The crate exists for the
  workspace shape; publication is SR4's call.
- Add the `transition`, `resolve-upstream`, or `metrics` subcommands.
  Those are SR2, SR3, SR5.
- Change the GHA annotation byte format, exit codes, install path,
  release asset naming, or `--version` template. All are preserved by
  the fixture.

The strategy's Block 4 discipline is operationalized as the
golden-output fixture (Decision 3). Every PR in the rewrite (this one
and any follow-ups) runs the fixture; merging is gated on parity.

## Solution Architecture

### Crate boundary

```
┌─────────────────────────────────────────────────┐
│  crates/shirabe  (binary)                       │
│                                                 │
│  main.rs                                        │
│    Cli (clap Parser)                            │
│    Commands::Validate { paths, visibility,      │
│                         custom_statuses }       │
│    fn run() -> ExitCode                         │
│                                                 │
│  Depends on: shirabe-validate (path = "...")    │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  crates/shirabe-validate  (library)             │
│                                                 │
│  pub use doc::{Doc, FieldValue, Section,        │
│                ValidationError};                │
│  pub use formats::{FormatSpec, FORMATS,         │
│                    detect_format};              │
│  pub use frontmatter::parse_doc;                │
│  pub use validate::{Config, validate_file,      │
│                     is_notice};                 │
│  pub use annotation::{format_error,             │
│                       format_notice};           │
│                                                 │
│  Depends on: saphyr                             │
└─────────────────────────────────────────────────┘
```

The binary crate carries no validation logic. Every check, the
frontmatter parser, the format registry, and the annotation emitter
live in `shirabe-validate`. This boundary is the same one SR4 will
publish; SR1 just doesn't push the library crate to crates.io.

### Data flow

The Rust runtime mirrors the Go runtime so each control-flow step in
the existing code has a directly corresponding step in the new code:

```
   user invokes: shirabe validate <path>...
                         │
                         ▼
   main.rs::run()
     │
     ├─ Cli::parse()    (clap derive — mirrors cobra Args parsing)
     │
     ├─ parse --custom-statuses YAML to HashMap<String, Vec<String>>
     │  (mirrors yaml.Unmarshal in current main.go)
     │
     ├─ Config { custom_statuses, visibility }
     │
     ▼
   for path in paths:
     │
     ├─ detect_format(basename) -> Option<FormatSpec>
     │  (mirrors validate.DetectFormat; same longest-prefix rule)
     │
     ├─ parse_doc(path) -> Result<Doc>
     │  │
     │  ├─ read file bytes
     │  ├─ split_frontmatter -> (yaml_bytes, fm_start_line, body_start_line)
     │  ├─ parse_yaml_fields via saphyr:
     │  │    ├─ saphyr::Loader::load_from_str(yaml_str)
     │  │    ├─ walk mapping; for each (key_node, val_node):
     │  │    │    fields[key] = FieldValue { value, line: key_node.span().start.line }
     │  │    └─ return HashMap
     │  ├─ scan_body for ## headings + body lines
     │  └─ build Doc
     │
     ├─ validate_file(&doc, &spec, &cfg) -> Vec<ValidationError>
     │  │
     │  ├─ check_schema -> early-return SCHEMA notice on mismatch
     │  ├─ check_fc01 (required fields)
     │  ├─ check_fc02 (status enum; reads custom_statuses[schema_version])
     │  ├─ check_fc03 (frontmatter ↔ ## Status body match)
     │  ├─ check_fc04 (required sections)
     │  └─ format-specific:
     │       Plan  -> check_plan_upstream (R6: file exists + git ls-files)
     │       VISION -> check_vision_public (R7: prohibited sections in public)
     │
     ▼
   for err in errors:
     ├─ if is_notice(err):  emit format_notice(file, msg) to stdout
     ├─ else:               emit format_error(err) to stdout; has_errors = true
     │
     ▼
   exit code: 1 if has_errors else 0
```

### YAML field→line reconstruction (the strategy's flagged risk)

saphyr exposes per-node source positions through its `MarkedYaml`
(and `MarkedYamlOwned`) types, which carry a `Span` on every node
pointing at the start of that node in the original input. The
`Mapping` (borrowing) and `MappingOwned` (owned) type aliases hold
the parsed mapping; insertion order is preserved (saphyr uses
`hashlink` under the hood). This is the structural shape the
field→line reconstruction needs.

The core function mirrors Go's `parseYAMLFields`. The exact import
paths and method names below are sketched against saphyr's published
0.0.x API as of v0.0.6 (June 2025); the implementation will pin a
specific patch version in `Cargo.toml` and bind the imports to that
version's actual surface:

```rust
use saphyr::{MarkedYamlOwned, LoadableYamlNode};

fn parse_yaml_fields(yaml_str: &str, fm_start_line: usize)
    -> Result<HashMap<String, FieldValue>, ParseError>
{
    let docs = MarkedYamlOwned::load_from_str(yaml_str)?;
    let mut fields = HashMap::new();
    let Some(doc) = docs.into_iter().next() else { return Ok(fields); };

    // Reject anything other than a mapping at the document root; this
    // matches the Go implementation's behavior of returning an empty
    // map for non-mapping roots.
    let Some(mapping) = doc.as_mapping_get() else { return Ok(fields); };

    // saphyr Span.start.line is 1-indexed within the YAML input string.
    // fm_start_line is the 1-indexed absolute line of the YAML input's
    // first line in the source file.
    let offset = fm_start_line.saturating_sub(1);

    for (key_node, val_node) in mapping.iter() {
        let Some(key) = key_node.data.as_str() else { continue; };
        let absolute_line = key_node.span.start.line() + offset;
        let value = val_node.data.as_str()
            .map(|s| s.trim_end_matches('\n').to_string())
            .unwrap_or_default();
        fields.insert(
            key.to_string(),
            FieldValue { value, line: absolute_line },
        );
    }
    Ok(fields)
}
```

The structural contract — "saphyr's marked-node API exposes
`{key_node.span.start.line, val_node.data}` for every mapping entry,
preserves insertion order, and works on owned data" — is verified
by saphyr's documented `MarkedYaml{Owned}`, `Span`, `Marker`,
`Mapping{Owned}`, and `hashlink` dependencies. Field name and method
naming will lock to the pinned patch version at implementation time;
the API class is what the validator needs, and saphyr provides it.

Backstop: if the pinned saphyr version's API surface differs more
than cosmetically from this sketch (a possibility given the 0.0.x
version line), implementation drops to the lower-level
`saphyr-parser` crate's `SpannedEventReceiver` and walks events with
`StreamStart`/`MappingStart`/`Scalar` directly, recovering the same
per-key positions from event markers. This is a slightly larger
function (~70 LOC instead of ~30) but uses only stable parser-level
primitives and is the documented fallback the saphyr project
recommends for consumers that need precise event-level control.

### GHA annotation byte format (preservation target)

```
::error file=<sanitized_path>,line=<N>::<sanitized_message>\n
::error file=<sanitized_path>::<sanitized_message>\n               (when line == 0)
::notice file=<sanitized_path>::<sanitized_message>\n
```

Where `sanitize` strips `\n` and `\r` from the string (matching the
Go implementation in `internal/annotation/annotation.go`). The newline
at the end is `\n` regardless of host platform — matches Go's
`fmt.Println` writing to stdout in shirabe's CI context.

### `--version` output (preservation target)

Today: `shirabe <version>\n` where `<version>` is the value injected
via `-ldflags "-X main.version=<value>"` at build time, defaulting to
"dev".

Rust equivalent: clap's `version` attribute with a custom template
matching `"shirabe {version}\n"`. The version string is sourced from
`CARGO_PKG_VERSION` (set in the binary crate's `Cargo.toml`) at compile
time, with override capability via a `SHIRABE_VERSION` environment
variable for the release pipeline (mirroring the Go ldflags injection).

### Test surface

Two test layers:

1. **Unit tests** in each module of `shirabe-validate` (`#[cfg(test)] mod
   tests`), mirroring the Go test suite's coverage of each check and the
   frontmatter parser. The Go suite (`checks_test.go`,
   `frontmatter_test.go`) is the logical reference; tests port table-by-
   table. The Rust idiom uses `#[test]` per case rather than Go's
   `t.Run` subtest pattern.

2. **Golden-output parity tests** in `crates/shirabe/tests/parity.rs`,
   one `#[test]` per corpus file. Each test:
   - reads `tests/fixtures/golden/corpus/<path>`,
   - runs the binary with `assert_cmd` or equivalent against that file,
   - reads `tests/fixtures/golden/expected/<path>.{stdout,stderr,exit}`,
   - asserts byte equality on stdout, stderr, and exit code, emitting a
     diff on failure.

The eval suite (`scripts/run-evals.sh`) runs unchanged in CI as a
third layer — it exercises the binary at the skill-CLI seam, which is
its existing purpose.

### Release and install pipeline

- The existing `.github/workflows/release-binaries.yml` swaps the Go
  build matrix for a `cargo build --release` matrix (the same
  `linux-amd64`, `linux-arm64`, `darwin-amd64`, `darwin-arm64` targets).
- The release asset names (`shirabe-<os>-<arch>`) stay identical;
  install.sh reads them unchanged.
- Checksums file (`checksums.txt`) generation moves from goreleaser to a
  Cargo-based step (the existing `release.yml` workflow already runs
  the checksum step as bash after binary builds; that step is
  unchanged).
- `install.sh` itself does not change — it only references release asset
  URLs, which preserve their names.
- The tsuku recipe entry for shirabe is unchanged (it depends on the
  release asset name pattern, not the build language).

### What gets deleted

The Rust addition is paired with the Go deletion in the same PR:

```
DELETE   cmd/shirabe/
DELETE   internal/annotation/
DELETE   internal/validate/
DELETE   go.mod
DELETE   go.sum
```

The `.github/workflows/validate-docs.yml` workflow's "Build binary" step
(currently `go build ./cmd/shirabe`) swaps to `cargo build --release
--bin shirabe` and the `actions/cache` keys flip from Go module cache
to Cargo registry + target cache.

The build-from-source path the existing workflow uses (per the upstream
design DESIGN-gha-doc-validation.md) is preserved as a contract — the
caller workflow still produces the binary at runtime via the same
mechanism; only the language changes.

## Implementation Approach

The work decomposes into five phases, each landable as a separable PR
but all expected to ship as one cohesive replacement. The phases are
sequencing inside the rewrite PR, not separate PRs.

**Phase 1 — Cargo workspace skeleton.**
Add `Cargo.toml` at the repo root with the workspace declaration. Create
`crates/shirabe-validate/` and `crates/shirabe/` with `Cargo.toml` and
empty `src/lib.rs` / `src/main.rs`. Add `rust-toolchain.toml` pinning
the stable Rust version (1.81 or newer at implementation time). Verify
`cargo build` succeeds. Add a CI step running `cargo build --release`
and `cargo test --workspace` alongside the existing `go test ./...`.

**Phase 2 — Frontmatter parser and Doc/FormatSpec types.**
Port `internal/validate/doc.go` (types) and `internal/validate/formats.go`
(the FORMATS map and detect_format) to `shirabe-validate`. Implement
`parse_doc` using saphyr; port `splitFrontmatter`, `parseYAMLFields`,
`bodyAfterLine`, `scanBody` from `internal/validate/frontmatter.go`.
Port `frontmatter_test.go` table tests to `#[test]` cases in
`crates/shirabe-validate/src/frontmatter.rs`. Verify every existing
frontmatter test case passes on the Rust side.

**Phase 3 — Validation checks and annotation emitter.**
Port `internal/validate/checks.go` and `internal/validate/validate.go`
to `shirabe-validate` (`checks.rs`, `validate.rs`). Port `internal/
annotation/annotation.go` to `shirabe-validate::annotation`. Port
`checks_test.go` cases. R6 (`check_plan_upstream`) calls `std::process::
Command::new("git")` with `ls-files --error-unmatch --` — same
semantic as the Go `exec.Command`. Verify the Go unit-test corpus
passes on the Rust side.

**Phase 4 — Binary crate and CLI surface.**
Wire `crates/shirabe/src/main.rs` with the clap Cli, Commands, and
the `run` function. Implement `--version` with the format-matching
template. Implement `--custom-statuses` 64 KiB cap (matching the Go
guard in main.go). Implement the exit-code contract (1 on any error
annotation; 0 otherwise; skip-on-unrecognized-format matching Go's
`continue` behavior).

**Phase 5 — Golden-output fixture and release plumbing.**
Run `tests/fixtures/capture_go_baseline.sh` to capture stdout/stderr/
exit for every corpus file against the captured Go binary
(`shirabe-go-v0.6.1`, built from this PR's parent commit). Commit
`corpus/` and `expected/` to the repo. Write `parity_test.rs`. Verify
every parity test passes. Update `.github/workflows/release-
binaries.yml` to use cargo. Verify `cargo build --release` produces
binaries that pass parity and that the release workflow produces
matching asset names. Delete `cmd/`, `internal/`, `go.mod`, `go.sum`
in the same commit.

### Sequencing inside the PR

Phases 1–4 produce a working Rust binary that's hidden behind a feature
flag (`cargo --features rust-bin` or similar) running alongside the Go
binary in CI; Phase 5 deletes the Go side and flips the
`.github/workflows/validate-docs.yml` build step. This sequencing
keeps every phase's CI green and isolates the Go-removal to one commit
for easy review.

### Out of scope for SR1

- The library crate's API stability (SR4).
- `shirabe transition` subcommand (SR2).
- `shirabe resolve-upstream` subcommand and the underlying cross-repo
  resolver (SR3).
- `shirabe metrics` subcommand (SR5 / Decision 5).
- crates.io publication of `shirabe-validate` (SR4 + a separate
  decision).
- Any v2 break to the GHA annotation format, CLI surface, or install
  contract (strategy Decision 3 forbids).

## Security Considerations

The Rust rewrite inherits the same security surface as the Go binary:
processing untrusted (PR-authored) markdown files and emitting strings
that GitHub Actions interprets as workflow commands.

### Annotation injection

The Go implementation strips `\n` and `\r` from every field value
embedded in a GHA annotation (`internal/annotation/annotation.go::sanitize`)
to prevent a PR author from crafting frontmatter that injects extra
annotation lines or breaks out of the annotation context. The Rust
implementation preserves this: `sanitize` lives in
`shirabe-validate::annotation` with the same two-character strip
(`\n` → "", `\r` → ""), and `format_error` / `format_notice` call it
on `file` and `message` before formatting. The parity fixture's
corpus includes a synthetic case with newlines in field values to
exercise the path on every test run.

### YAML parser safety

`saphyr` is a pure-Rust YAML 1.2 parser with no `unsafe` blocks in its
public API and no foreign code. The frontmatter limit comes from the
file size (the validate workflow loads files from disk; large files
just take longer to parse). The `--custom-statuses` flag carries a
64 KiB cap (matching the Go implementation); saphyr's parse of that
input is bounded by the cap.

YAML aliases, anchors, and explicit !!tag directives are not
exploited by any check in shirabe today; the validator reads scalar
key/value pairs at the top level of the mapping and treats nested
structures as opaque. saphyr's behavior on alias expansion is the
parser's own concern — the validator does not introspect the expanded
structure. (The strategy already named YAML parser choice as the
single non-trivial portability risk; the security framing here is
deliberately narrow because the parser's risk profile is correctness,
not exploitation.)

### Git subprocess invocation (R6)

`check_plan_upstream` invokes `git ls-files --error-unmatch -- <path>`
to verify that an `upstream:` field's target is tracked by git. The
Go implementation uses `exec.Command`, which does not invoke a shell;
the Rust port uses `std::process::Command`, which similarly does not
invoke a shell. The `<path>` argument is passed as a separate `arg`
and not interpolated, so PR-authored `upstream:` values cannot
trigger shell expansion or command injection. The `--` separator is
preserved so paths beginning with `-` are not interpreted as flags.

### File system access

The validator only reads files explicitly passed on the command line.
`parse_doc` calls `std::fs::read` on the path; no recursive walk, no
symlink following beyond what the OS does for `open`. The caller
workflow constructs the file list via `git diff` on the PR's changed
files, so the validator never opens files outside the caller's
checkout.

### What changes vs. the Go binary

Nothing. The Rust binary processes the same inputs through the same
checks and emits the same outputs. The security posture is
preservation, not improvement; the strategy's "non-event" framing
extends to security.

### Why this is not N/A

The shirabe binary writes to a stream (GHA annotations) that the host
runner interprets as control-plane instructions. Untrusted input
that flows into that stream without sanitization is the classic
injection risk. The Go implementation closed this through
`sanitize`; the Rust port must close it the same way. The parity
fixture catches regressions; this section names the contract
explicitly so future maintainers understand the constraint isn't
arbitrary.

## Consequences

### Positive

- **Single-language deterministic substrate.** Once SR1 lands, the
  validate CLI is Rust, the future subcommands (SR2–SR5) land in the
  same crate, and the path to SR4's library publication is a Cargo
  manifest change rather than a code reorganization.
- **Per-field line numbers without a hand-rolled scanner.** The
  strategy named field→line reconstruction as 80% of the risk; saphyr
  reduces that risk to choosing the right parser, which is now
  reduced further by saphyr being the actively-maintained successor
  to yaml-rust2.
- **The byte-for-byte preservation contract becomes testable code.**
  Block 4's "discipline applied across PRs" gets a concrete
  acceptance gate. Future Rust changes to shirabe cannot accidentally
  regress GHA annotation output without the parity tests catching it.
- **SR4 doesn't pay a restructuring cost.** The workspace + library
  crate exist already; SR4 just decides API stability and
  publication.

### Negative

- **Two-crate workspace adds a small upfront complexity.** A single
  binary crate would be marginally simpler today. The trade is
  intentional (see Decision 4) but real.
- **Captured Go binary in CI artifacts is a one-time cost.** The
  baseline capture script needs the v0.6.1 Go binary built once and
  the outputs committed. Refreshing the baseline (if v0.6.x ships a
  preserved fix that we want to mirror) requires re-running the
  capture and updating `expected/`.
- **Rust toolchain in CI.** The validate-docs workflow now installs
  Rust instead of (or in addition to) Go for the build-from-source
  path. The `actions/cache` key for Rust target+registry is larger
  than the Go module cache; cache misses cost more.

### Mitigations

- *Workspace complexity:* documented in this design and locked to two
  crates; further splits require an SR-level design.
- *Baseline refresh cost:* the capture script is committed and idempotent;
  the recovery path is "rerun capture_go_baseline.sh against a freshly
  built v0.6.x." The baseline is intentionally tied to a tagged Go
  release so it doesn't drift on Go-side commits.
- *CI cache size:* the existing `actions/cache` step in
  `validate-docs.yml` already caches Go modules; the swap is to cache
  the Cargo registry + `target/` directory under a Cargo-specific
  cache key. Cache size is bounded by the Cargo build artifacts for
  saphyr + clap + their transitive dependencies (small).

### Risks the strategy already named

- *Reconstruction breaks byte-for-byte preservation in subtle ways.*
  The strategy's Block 1 invalidation signal — extend Block 4's
  fixture to include real artifacts if synthesized tests pass but
  real artifacts diverge. This design's Decision 3 fixture already
  uses real artifacts; the synthesized direction would be the
  fallback if the real-corpus fixture catches divergence we cannot
  diagnose with synthesized tests alone.
- *Toolchain pinning surprises.* `rust-toolchain.toml` pins the
  channel; downstream Rust-version policy is downstream of this PR.
  Pinning to stable (not nightly) avoids the most obvious foot-gun.
