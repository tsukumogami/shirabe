---
status: Proposed
problem: |
  shirabe's deterministic surface (`shirabe validate` CLI, the line-number-aware
  YAML frontmatter parser, the seven validation rules, the GHA annotation
  emitter) is implemented in Go. The parent strategy commits to consolidating
  the deterministic surface in Rust so that future downstream consumers (koto
  template-script-calling, bunki crate-bundling) can link against a Rust crate
  rather than shell out across a Go-Rust seam. This design is the foundation
  step of that initiative: translate `cmd/shirabe/` + `internal/validate/`
  from Go to Rust while preserving the public contract byte-for-byte.
decision: |
  Translate the 1,417 LOC of Go (cmd/shirabe + internal/validate +
  internal/annotation) to Rust as a Cargo workspace with two crates from day
  one (a `shirabe-validate` library crate carrying the validate logic and a
  thin `shirabe` binary crate carrying the clap CLI), using saphyr for
  line-number-aware YAML parsing, clap for the cobra-equivalent CLI surface,
  and a two-layer parity test mechanism — a golden-output fixture in this
  repo that runs both binaries against shirabe's own committed artifacts
  plus a synthetic edge-case corpus, plus a reusable `parity-check.yml`
  workflow that downstream callers can include from their own CI to run
  the same parity assertion against their own artifact corpora.
rationale: |
  The workspace-from-day-one crate layout costs almost nothing now (one
  Cargo.toml split) and prevents a future-publication-driven repository
  restructuring of every import path later. saphyr is the parser successor
  to yaml-rust2 with
  active maintenance and explicit `Span`/`marker` support on every node, so
  the field→line map shirabe needs falls out of the parse tree directly
  rather than requiring a hand-rolled second pass. clap with derive macros
  maps the cobra subcommand tree mechanically with no behavior change. The
  two-layer parity mechanism operationalizes the output-contract-preservation
  discipline: every PR in this repo runs both binaries against the shirabe
  corpus plus synthetic edge cases (Layer 1), and downstream callers consume
  a reusable parity-check workflow to enforce the same byte equality against
  their own corpora (Layer 2).
---

# DESIGN: shirabe CLI Rust rewrite

## Status

Proposed

## Provenance

This design realizes the foundation step of a multi-feature Rust
consolidation initiative whose planning chain lives in a private
companion repo. The design stands alone for the technical
decisions it locks; the planning chain shapes only the scope and
sequencing. Four planned follow-on features are referenced where
their existence shapes a decision in this design:

- a **transition-subcommand follow-on** that collapses the per-skill
  status-transition bash scripts under a `shirabe transition`
  subcommand;
- a **cross-repo-resolver follow-on** that adds a `shirabe
  resolve-upstream` subcommand implementing the `owner/repo:path`
  reference syntax that today is documented but not implemented;
- a **library-crate-publication follow-on** that publishes the
  `shirabe-validate` crate to crates.io with a stabilized public
  API surface, locked against the first downstream consumer's
  call-site requirements;
- a **tripwire-metrics follow-on** that adds a `shirabe metrics`
  subcommand surfacing the cost-of-delay tripwires the parent
  strategy commits to monitoring.

References to these follow-ons appear when they constrain the
present design's decisions (e.g., the library-crate-publication
follow-on motivates the Cargo workspace layout). The follow-ons
themselves are out of scope.

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
Plan upstream check, R7 VISION public-visibility check). Two rules —
**FC02** (`status` enum) and **R6** (Plan upstream existence + git
tracking) — require **per-key line numbers from the YAML frontmatter**
so the rendered GHA annotation points at the offending field rather
than the top of the file. The Go implementation gets these from
`yaml.v3`'s `yaml.Node.Line` field, which is populated during decoding.

The remaining five rules don't consume YAML per-key positions: SCHEMA,
FC01, and FC04 hardcode `line=1`; FC03 (frontmatter `status` ↔ `##
Status` body match) and R7 (prohibited sections in public VISION
docs) read the `## Status` heading's line from a separate Markdown
body scan (`scanBody` in `internal/validate/frontmatter.go`), not
from YAML node positions. This narrows the parser's per-key line-
number contract to two scalar field lookups (`status` and
`upstream`); everything else is independent of the YAML parser's
position-tracking surface.

The parent initiative commits to consolidating shirabe's runtime substrate
in Rust. This design is the load-bearing piece: every planned follow-on
(transition subcommand, cross-repo resolver, library-crate publication,
tripwire metrics) extends the Rust binary this design creates. The
design must answer four technical questions before implementation can
start:

1. **What Rust YAML parser provides per-key line numbers?** `serde_yaml`
   deserializes into Rust structs but discards source positions. The Go
   implementation depends on `yaml.v3`'s `Node.Line` for FC02 (`status`)
   and R6 (`upstream`) annotations — the only two checks that read
   per-key positions from the YAML mapping. The parent initiative names
   this as 80% of the technical risk.
2. **How does the cobra subcommand tree translate to clap?** Mechanical, but
   the design should document the mapping so the planned follow-on
   subcommands inherit a
   conventional shape.
3. **How is output-contract preservation enforced as a test?** The strategy
   commits to byte-for-byte preservation as an acceptance criterion, not
   aspiration; this design names the fixture mechanism.
4. **Single binary crate vs. Cargo workspace?** The library-crate-
   publication follow-on will publish a separate crate. Anticipating
   that shape from day one avoids a structural re-port when
   publication happens.

A fifth question the parent initiative surfaces — does the
`shirabe metrics` tripwire subcommand ship inside this design's PR
or as a separate follow-on — is resolved in **Decision 5** below.

## Decision Drivers

- **Byte-for-byte output preservation is mandatory.** Strategy Decision 3:
  no v2 break window. Every GHA annotation, every exit code, every
  `--version` byte must match the Go binary on identical inputs. The roadmap
  scopes the preservation test to "every existing committed artifact in
  workspace repos that consume `validate-docs.yml`."
- **Per-field line numbers are non-negotiable for FC02 (status) and
  R6 (upstream).** Today's
  Go output points GHA annotations at specific frontmatter keys; the Rust
  binary must do the same on the same files. Falling back to line 1 for
  these errors would be a behavior regression.
- **The rewrite must be a non-event for the two internal pinning callers.**
  shirabe's own `.github/workflows/validate-docs.yml` and the private
  `vision` repo's caller both consume the published binary on tagged
  releases. Both must continue to pass on the day the Rust binary ships.
- **The Cargo crate must be ready for the library-crate-publication
  follow-on without restructuring.** The parent initiative stages
  library-as-amplifier (publish later, after a downstream consumer
  locks the API), but the publication PR shouldn't require renaming
  every import path. A workspace from day one with the validation
  logic in a separate crate is the cheap shape.
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
on the parsed mapping so FC02 (`status`) and R6 (`upstream`) annotations
can point at the offending frontmatter field? (FC03 and R7 read body
section lines from a separate Markdown scan, not from YAML node
positions, and SCHEMA/FC01/FC04 hardcode `line=1`.)

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
  the parent initiative flagged as the rewrite's single non-trivial risk. Putting
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
because saphyr makes the same outcome free, and the parent initiative explicitly
warned about concentrating risk in a hand-rolled YAML reconstruction.

### Decision 2: CLI framework — cobra → clap mapping

**Question.** How does the cobra subcommand tree (`shirabe`, `shirabe
validate`, `--visibility`, `--custom-statuses`, `--version`) translate to a
clap idiom that the planned follow-on subcommands (`transition`,
`resolve-upstream`, `metrics`) inherit cleanly?

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
  cobra → clap translation is the parent initiative's "mechanical" item and
  picking a non-conventional approach turns mechanical work into
  exploratory work.

This decision is mechanical per the parent initiative's framing. The design records the
chosen idiom so the planned follow-on subcommands inherit a
consistent pattern.

### Decision 3: Output-contract preservation mechanism

**Question.** How does the rewrite enforce byte-for-byte output
preservation against the Go binary's behavior on every committed artifact
in the workspace?

**Key assumptions.**
- The shirabe repo's preservation contract is bounded by what the
  shirabe repo itself can verify in its own public CI. Today the
  reusable `validate-docs.yml` workflow has two known internal
  callers — shirabe itself (via `validate-shirabe-docs.yml`) and one
  organization-internal companion repo whose preservation tests run
  in that repo's own CI, not in shirabe's. Other workspace repos
  (`koto`, `tsuku`, `niwa`) do not pin the workflow today.
- The shirabe repo's fixture is what external adopters (and future
  internal callers) see as the preservation contract; it must
  exercise the full validation surface (all five formats, all seven
  rules, edge cases on each).
- A captured Go binary at a frozen version (`v0.6.1`, the most recent
  tagged release) is the immutable reference; once captured, the
  fixture asserts against it rather than rebuilding Go each run.

**Chosen: two-layer fixture mechanism — a public-corpus parity fixture
committed to the shirabe repo, plus a reusable `parity-check.yml`
workflow downstream repos can call against their own corpora.**

Layer 1 — public-corpus fixture in the shirabe repo at
`tests/fixtures/golden/`:

1. `corpus/` — every committed artifact under `docs/` in the shirabe
   repo itself with a recognizable shirabe format prefix (DESIGN-,
   PRD-, VISION-, ROADMAP-, PLAN-, STRATEGY-), plus a `synthetic/`
   subdirectory of crafted edge-case inputs. The synthetic set
   must include **at least one artifact triggering FC02** (a
   `status` value outside the enum, with `status:` at a non-line-1
   position) and **at least one triggering R6** (a `upstream:`
   value pointing at a missing or non-git-tracked path, with
   `upstream:` at a non-line-1 position) so the saphyr per-key
   line-number pathway is actually exercised by parity testing;
   without these, the parity tests pass without ever invoking
   `key_node.span.start.line()`. The remaining synthetic cases
   cover multi-line block scalars, `\n`-bearing field values for
   sanitize-path coverage, unrecognized formats, missing
   frontmatter, mismatched `## Status` body, each of FC01/FC04
   failure paths, R7 success and failure paths, and a small
   set of **parser stress-test inputs** that exercise the
   panic surface (malformed UTF-8 in YAML, deeply nested
   mapping structure, anchor-cycle YAML). The stress-test set
   makes the "Rust panics go to stderr; parity catches
   divergence" argument live-tested rather than just asserted;
   without these inputs, the panic-surface mitigation is
   unfalsified by Layer 1.
2. `expected/` — for each corpus file, the captured stdout, stderr,
   and exit code produced by `shirabe-go-v0.6.1 validate <path>`.
   The capture is regenerated by `tests/fixtures/capture_go_baseline.sh`
   (committed alongside) so the baseline is reproducible.
3. `parity_test.rs` — a `#[test]` per corpus file that runs the Rust
   binary, captures its three outputs, and asserts equality. Any
   divergence fails the test with a side-by-side diff.

Layer 2 — reusable workflow at
`.github/workflows/parity-check.yml` that downstream repos can
include from their own CI to run the same byte-for-byte test against
their own committed corpora:

```yaml
# Example caller (downstream repo)
jobs:
  shirabe-parity:
    uses: tsukumogami/shirabe/.github/workflows/parity-check.yml@v0.7.0
    with:
      go-baseline-version: v0.6.1
      corpus-glob: "docs/**/*.md"
```

The workflow checks out the caller's repo, downloads the captured
Go baseline binary plus the Rust release binary for the requested
shirabe version, runs both against the matched files, and diffs
output. Layer 2 exists because shirabe's "preservation contract"
extends conceptually to every caller of `validate-docs.yml`, but
the shirabe repo cannot embed those callers' artifacts directly.
Giving them a reusable parity workflow lets each caller assert the
preservation contract against their own corpus on their own CI
without leaking content into shirabe.

The fixture is the operational implementation of the byte-for-byte
preservation discipline the parent initiative commits to. Every PR
in the Rust rewrite must pass Layer 1; Layer 2 is the mechanism by
which the contract extends to internal and external adopters.

**Why two layers instead of one fixture directory.** The original
framing of this decision contemplated a single fixture in this repo
covering every committed artifact across every workspace repo that
consumes shirabe's reusable validate workflow. That framing breaks
on the public/private visibility boundary: one of the two known
workspace consumers of the reusable workflow is a private repo,
and embedding its artifact corpus into this public source tree
would leak content the public repo isn't permitted to disclose.
The two-layer mechanism resolves the constraint and generalizes
beyond it: any future external adopter — public or private — gets
the same preservation contract by including `parity-check.yml`,
without needing this repo to embed their artifacts. The
generalization is the design's, not a workaround for the
constraint alone.

**Considered and rejected.**

- *Property-based testing against a synthesized artifact generator.*
  Generate random valid/invalid frontmatter, compare Go vs Rust output.
  **Rejected** because the realistic distribution of artifacts in the
  workspace is the surface the preservation contract actually covers — not
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
anticipating the library-crate-publication follow-on?

**Key assumptions.**
- The library-crate-publication follow-on will publish a library crate
  exposing the validate API to downstream consumers. The API surface
  stays "internal-shaped, public for distribution" until a downstream
  consumer locks the contract — that's the parent initiative's staging
  framing for the publication step.
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
│   │       └── annotation.rs    (format_error, format_notice, sanitize;
│   │                              format_error takes ValidationError,
│   │                              format_notice takes (file, msg))
│   └── shirabe/                 (binary crate)
│       ├── Cargo.toml
│       └── src/
│           └── main.rs          (clap Cli, validate_cmd, --version handling)
```

The `shirabe-validate` crate is internal-shaped (public visibility for
distribution but no API stability guarantee across versions). Its public
surface during this design's PR mirrors the Go `internal/validate`
exports plus `internal/annotation`. The library-crate-publication
follow-on will push this crate to crates.io with the same code; the
publishing decision shifts, the layout does not.

**Considered and rejected.**

- *Single binary crate, restructure when publication lands.* Simplest
  now; pushes the workspace decision to the moment the library-crate-
  publication follow-on lands. **Rejected** because that follow-on's
  design will then need to negotiate every import path change at the
  same time it's negotiating the library API. The parent initiative
  stages library-as-amplifier *publishing*, not library-as-amplifier
  *code shape*. Workspace-from-day-one separates those two questions.
- *Single binary crate with `pub mod validate`.* Use Rust's module
  system in place of a separate crate; pull `validate` into a library
  crate when publication lands. **Rejected** because Cargo's
  `[[bin]]`/`[lib]` distinction at publication time still requires
  moving the module source into a new crate directory and updating
  every `mod`/`use` path. The diff is small in absolute terms but
  lands at exactly the moment the publication design needs cognitive
  bandwidth for library API decisions.
- *Three crates from day one (`shirabe-validate`, `shirabe-cli`,
  `shirabe-bin`).* Pre-anticipate per-subcommand crates for the
  planned follow-ons. **Rejected** because YAGNI: those follow-on
  designs haven't picked whether they want separate crates, and the
  three-crate split adds workspace complexity for zero current
  benefit. Two crates is the minimum that bypasses the publication-
  time import-path churn; more is speculation. Also, Decision 2
  commits the clap subcommand tree to live in the binary crate;
  the planned follow-on subcommands inherit that tree as new
  `Commands` enum variants, not as separate crates, so a three-
  crate split would put subcommand dispatch on the wrong side of
  a crate boundary.

### Decision 5: Tripwire-metrics subcommand timing

**Question.** Does the planned `shirabe metrics` tripwire subcommand
ship inside this design's PR, or as a separate follow-on once this
design's PR lands?

**Key assumptions.**
- The parent initiative defaults to "follow-on" but allows this
  design to confirm.
- The metrics subcommand has no behavioral overlap with `validate`;
  its output is a small JSON or text report read by a scheduled GHA,
  not by the validate-docs reusable workflow.
- The byte-for-byte preservation fixture (Decision 3) is the load-
  bearing acceptance work in this PR; coupling metrics to that PR
  would either delay it or force a partial-completion shape.

**Chosen: follow-on PR. The metrics subcommand ships as a separate
small PR after this design's rewrite lands.**

This design's PR ships the workspace, the validate logic, the parity
fixture, and the install/release plumbing. The metrics subcommand
lands afterward as a tripwire-metrics-follow-on piece of work; the
parent initiative already tracks it as a distinct feature.

The parent initiative's roadmap defaults to this shape. The design
confirms it because conflating metrics with the rewrite would put
preservation-fixture review attention against a feature that has no
validation contract to preserve.

**Considered and rejected.**

- *Ship the metrics subcommand inside this PR as a near-trivial
  addition.* The subcommand is small. **Rejected** because trivial-
  in-LOC and trivial-in-review-attention are different. This PR's
  reviewers are looking at the parity fixture; metrics would split
  that attention, and the metrics subcommand has its own design
  considerations (tripwire detection logic, output format for CI
  parsing) that deserve their own PR-level discussion.

### Decision 6: Rust toolchain channel and pinning

**Question.** Which Rust toolchain does the project pin to, and how?

**Key assumptions.**
- Reproducible builds matter (the binary ships to multiple targets via
  the release workflow; toolchain drift between local and CI causes
  failure modes that are expensive to diagnose).
- The project does not need nightly features (no const generics
  beyond stable, no async at all, no specialization).
- `rust-toolchain.toml` is the conventional shape, supported by
  `rustup` and `cargo` natively.

**Chosen: pin to a specific stable version via `rust-toolchain.toml`.**

A `rust-toolchain.toml` at the repo root pins the channel to a
specific stable version (e.g., `1.81.0` or whatever stable is current
at implementation time; the implementer picks). The file also pins
the components needed (`rustfmt`, `clippy`) and the target triples
the release workflow needs. CI installs the same toolchain via
`actions/setup-rust` or `dtolnay/rust-toolchain` reading the file.

**Considered and rejected.**

- *Pin to the `stable` channel (no version pin).* CI picks up
  whatever stable was current at run time. **Rejected** because the
  parity fixture's `expected/` outputs depend on a deterministic
  build: a toolchain upgrade between captures and run would
  potentially shift a `Debug` representation or a `format!` rounding
  in a way the parity test catches as a regression. Pinning
  decouples the rewrite's stability from upstream Rust releases.
- *Pin to nightly.* No feature need it. **Rejected** for the same
  reproducibility reason plus the additional churn of nightly's
  faster cadence and occasional breakage.

### Decision 7: Captured Go baseline version pinning

**Question.** Which Go binary version is captured as the parity
fixture's `expected/` baseline?

**Key assumptions.**
- The Go binary's behavior is deterministic on a given version
  (`v0.6.1` produces identical output for identical input).
- The current `main` branch may have un-tagged commits between
  `v0.6.1` and the rewrite-merge point that change behavior; the
  rewrite must preserve the *released* contract, not the
  in-progress-on-`main` contract.

**Chosen: pin the baseline to `shirabe-go-v0.6.1` (the most recent
tagged release).**

The `tests/fixtures/capture_go_baseline.sh` script downloads (or
builds locally from the `v0.6.1` git tag) the captured Go binary,
runs it against `corpus/`, and writes the stdout/stderr/exit triple
to `expected/`. The committed `expected/` is the v0.6.1 output. If
v0.6.x ships a bugfix the team explicitly wants to mirror in the
Rust port (e.g., a sanitization improvement), the capture is
re-run against v0.6.x and `expected/` is updated as a separate PR
before the rewrite lands.

**Considered and rejected.**

- *Pin baseline to `main` HEAD at rewrite-PR-open time.* Tracks
  the most recent Go behavior. **Rejected** because un-tagged
  changes on `main` between releases are not part of the public
  contract external adopters consume; the external pin point is
  the tagged release. Capturing `main` would conflate
  in-development Go changes with the contract the rewrite must
  preserve.
- *Pin baseline to multiple Go versions and assert parity against
  all of them.* Maximally robust. **Rejected** as overkill —
  v0.6.x is the current release line, and the parent initiative's framing
  explicitly says the rewrite ships against the current contract,
  not a historical-version sweep.

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
   covering every shirabe-side committed artifact plus a synthetic
   edge-case corpus exercising all seven validation rules.
5. Adds `.github/workflows/parity-check.yml` as a reusable workflow
   downstream callers can include from their own CI to run the same
   parity assertion against their own corpora at a pinned shirabe
   tag. This is how the preservation contract reaches callers whose
   artifacts shirabe cannot embed directly.
6. Replaces the Go release/install pipeline targets with Rust ones,
   preserving asset naming (`shirabe-<os>-<arch>`) and the install.sh
   URL/path contract.
7. Removes the Go source tree (`cmd/`, `internal/`, `go.mod`, `go.sum`)
   atomically with the Rust addition. There is no Go-Rust coexistence
   window. The release tag flips from a Go binary to a Rust binary in
   one cut.

What this PR explicitly does not do:

- Publish `shirabe-validate` to crates.io. The crate exists for the
  workspace shape; publication is the library-crate-publication
  follow-on's call.
- Add the `transition`, `resolve-upstream`, or `metrics` subcommands.
  Those are each their own follow-on.
- Change the GHA annotation byte format, exit codes, install path,
  release asset naming, or `--version` template. All are preserved by
  the fixture.

The byte-for-byte preservation discipline the parent initiative
commits to is operationalized as the two-layer parity mechanism
(Decision 3). Every PR in the rewrite (this one and any follow-ups)
runs Layer 1; merging is gated on parity.

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
live in `shirabe-validate`. This boundary is the same one the
library-crate-publication follow-on will publish; this design just
doesn't push the library crate to crates.io.

**Error types.** `shirabe-validate` exports two error types:
`ValidationError` (the rule-failure struct with `file`, `line`,
`code`, `message` fields — directly mirrors the Go type) and
`ParseError` (the parser's error type, wrapping IO and YAML parse
failures). Both derive `Debug + Clone + PartialEq`. The crate
does not use `thiserror` or `anyhow` — the error surface is small
and explicit enough that a hand-written `impl std::error::Error`
on a plain enum is the simpler shape.

**Asymmetric annotation signatures.** `format_error` takes a
`ValidationError` but `format_notice` takes `(file, msg)` — the
same asymmetry as the Go implementation. Notices come from the
SCHEMA path (which has a `ValidationError` but reports
`line: 1`, so the annotation drops the line position) and from
the IO-error path in `main.go` (which never constructs a
`ValidationError` struct; it formats the file + message directly).
A `format_notice(file, msg)` keeps both call sites natural and
avoids inventing a synthetic `ValidationError` for IO failures.
Preserving the asymmetry preserves the output bytes.

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

### YAML field→line reconstruction (the flagged technical risk)

The contract here is narrow: per-key line numbers are needed only
for **two** scalar lookups in the validate logic — `status` (FC02)
and `upstream` (R6). FC03 and R7 read body section lines from a
separate Markdown scan; SCHEMA, FC01, FC04 hardcode `line=1`. The
parity fixture's corpus must include at least one artifact that
triggers FC02 (wrong-status case) and at least one that triggers
R6 (broken-upstream case), otherwise the saphyr Marker pathway
isn't actually exercised by the parity tests.

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

**Typed-scalar preservation.** Go's `yaml.v3` stores typed scalars
(`42`, `true`) on `yaml.Node` as `Value: "42"` and `Value: "true"`
— the string representation of the typed value. The Go
`parseYAMLFields` reads `valNode.Value` directly. saphyr's
`Scalar` enum distinguishes typed scalars, so `as_str()` may
return `None` on an integer or boolean node. shirabe's corpus
includes at least one typed-integer field (`issue_count: 8` in
plan/v1 frontmatter), so the field-value extraction must coerce
typed scalars back to their string representation rather than
fall through to `unwrap_or_default()`. The implementation calls
saphyr's `Yaml::Value::as_yaml_string()` (or equivalent — the
exact method name pins at implementation time) on each value
node before falling back to empty. The parity fixture catches
divergence on this path: any plan/v1 corpus file exercising
`issue_count` validates the typed-scalar pathway.

Backstop: if the pinned saphyr version's API surface differs more
than cosmetically from this sketch (a possibility given the 0.0.x
version line), implementation drops to the lower-level
`saphyr-parser` crate's `SpannedEventReceiver` and walks events with
`StreamStart`/`MappingStart`/`Scalar` directly, recovering the same
per-key positions from event markers. This is a slightly larger
function (~70 LOC instead of ~30) but uses only stable parser-level
primitives and is the documented fallback the saphyr project
recommends for consumers that need precise event-level control.

If the backstop fires, `Cargo.toml` depends on `saphyr-parser`
directly instead of `saphyr`. The public crate surface of
`shirabe-validate` is unchanged either way — the saphyr ↔
saphyr-parser swap is an implementation detail of
`shirabe-validate::frontmatter` and doesn't leak into the public
API the library-crate-publication follow-on will eventually
stabilize.

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

**Phase 5 — Golden-output fixture, reusable parity workflow, and
release plumbing.**
Curate `tests/fixtures/golden/corpus/`: include shirabe's own
committed artifacts under `docs/` (DESIGN-, PRD-, etc.) and build
out `synthetic/` with the edge cases enumerated in Decision 3
(sanitize coverage, FC01–FC04 failure paths, R6 and R7 paths,
parser stress-test inputs for the panic surface,
multi-line scalars, missing-frontmatter, unrecognized format,
mismatched body status). Run `tests/fixtures/capture_go_baseline.sh`
to populate `expected/` against `shirabe-go-v0.6.1`. Commit
`corpus/` and `expected/` to the repo. Write `parity_test.rs`.
Verify every parity test passes.

Add `.github/workflows/parity-check.yml` as a reusable workflow
(`on: workflow_call:`) with inputs for `go-baseline-version` and
`corpus-glob`. The workflow downloads the matching Go and Rust
binaries from shirabe's GitHub releases, runs both against the
caller's matched files, and asserts byte equality on stdout,
stderr, and exit code per file. The workflow is documented in
the design doc and ships as part of this design's deliverable.

Update `.github/workflows/release-binaries.yml` to use cargo.
Verify `cargo build --release` produces binaries that pass parity
and that the release workflow produces matching asset names.
Delete `cmd/`, `internal/`, `go.mod`, `go.sum` in the same commit.

### Sequencing inside the PR

Phases 1–4 add a Rust crate that builds in CI alongside the
existing Go binary. The Rust binary builds as `target/release/
shirabe-rs` (a non-default name so it doesn't collide with the
Go binary at `./shirabe`); `cargo test --workspace` asserts the
Rust side green and `go test ./...` continues to assert the Go
side green. The parity fixture asserts the Rust binary's output
against the committed `expected/` baseline (captured once from
`shirabe-go-v0.6.1` per Decision 7), so Phases 1–4 don't need a
live Go binary on the PR runner to run the fixture — the
baseline is immutable bytes on disk.

Phase 5 deletes `cmd/`, `internal/`, `go.mod`, `go.sum`; renames
the Rust binary from `shirabe-rs` to `shirabe`; and changes
`.github/workflows/validate-docs.yml`'s build step from
`go build ./cmd/shirabe` to `cargo build --release --bin shirabe`.
The deletion commit is reviewable as deletes-plus-one-workflow-
line-change in `git log -p`.

There is no cargo feature flag. The two languages coexist as
distinct build targets during Phases 1–4; Phase 5 is the cut.

### Out of scope for this design

- The library crate's API stability (library-crate-publication
  follow-on).
- `shirabe transition` subcommand (transition-subcommand follow-on).
- `shirabe resolve-upstream` subcommand and the underlying cross-
  repo resolver (cross-repo-resolver follow-on).
- `shirabe metrics` subcommand (tripwire-metrics follow-on; see
  Decision 5).
- crates.io publication of `shirabe-validate` (library-crate-
  publication follow-on + a separate API-stability decision).
- Any v2 break to the GHA annotation format, CLI surface, or install
  contract (the parent initiative's preservation contract forbids).

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

YAML aliases, anchors, and explicit `!!tag` directives are not
exploited by any check in shirabe today; the validator reads scalar
key/value pairs at the top level of the mapping and treats nested
structures as opaque. saphyr's behavior on alias expansion is the
parser's own concern — the validator does not introspect the expanded
structure. (The strategy already named YAML parser choice as the
single non-trivial portability risk; the security framing here is
deliberately narrow because the parser's risk profile is correctness,
not exploitation.)

### Supply-chain posture for saphyr's 0.0.x version line

saphyr is published at v0.0.6 (June 2025) and the project's own
README notes the pre-1.0 API may shift. The design pins saphyr to a
specific patch version in `Cargo.toml` and commits `Cargo.lock`
(standard Rust binary-crate practice) so CI builds are
deterministic across runs. The documented fallback (drop to
`saphyr-parser`'s `SpannedEventReceiver` if the higher-level API
drifts cosmetically) is also a supply-chain hedge: `saphyr-parser`
is the lower-level crate the higher-level API itself uses, and its
event-receiver surface is the more stable of the two.

A future security advisory against saphyr would require a patch
bump on shirabe's side; downstream adopters who pin a specific
shirabe tag get the dependency pin transitively. The supply-chain
trust horizon is bounded by shirabe's release cadence.

**Build-script hygiene.** Cargo dependencies can ship `build.rs`
files that execute arbitrary code during `cargo build`. saphyr
is pure Rust with no documented build script at the version
this design targets; clap's build path is well-vetted. The
Phase 1 implementation step runs `cargo deny check bans` (or
equivalent) once over the saphyr + clap dependency tree to
surface any unexpected build-script dependencies before they
reach CI.

The check is also a runtime hedge against future supply-chain
drift: after the first `cargo build` in Phase 1, verify the
absence of build scripts in the saphyr tree by running
`find ~/.cargo/registry/src -name build.rs -path '*/saphyr-*'`
(and the same for clap). If a future saphyr patch ships a
`build.rs`, the bare hygiene-note assumption breaks silently;
the runtime check fails loudly and the implementer can pin to
the pre-build-script patch or evaluate the new build script
before letting it land in CI.

### Data exposure via FC03's `## Status` body echo

FC03's error message echoes the first non-blank line after `## Status`
back into the GHA annotation when the body line does not match
frontmatter `status`. If a PR author writes sensitive content as
their `## Status` body, that content appears in the workflow log
(after sanitization removes `\n` and `\r`). The validator inherits
this behavior from the Go implementation unchanged.

The exposure pre-exists the validator: any content a PR author
puts in a publicly-visible markdown file is already public the
moment the PR opens. The validator is not the disclosure surface.
A future maintainer evaluating whether to expand error messages to
include more body context should know the constraint is
intentional: the validator quotes only the minimum body content
needed to make the error actionable.

### Panic surface

Rust panics (from saphyr parse errors, indexing, or any
unrecoverable parser state) write to stderr by default. GHA's
annotation parser reads stdout only, so panic messages cannot
inject annotations even if they include attacker-controlled YAML
content. The parity fixture catches divergence between Go's
recover-and-emit-error path and Rust's panic-or-emit-error path:
any input that causes the Go binary to emit an error annotation
but causes the Rust binary to panic would surface as a parity
test failure on the corpus. A real panic-on-malicious-input would
itself be a parser bug worth fixing in saphyr; the fixture
catches the regression without requiring a separate guard rail
in shirabe.

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
preservation, not improvement; the parent initiative's "non-event" framing
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

- **Single-language deterministic substrate.** Once this design's
  PR lands, the validate CLI is Rust, the planned follow-on
  subcommands land in the same crate, and the path to the library-
  crate-publication follow-on is a Cargo manifest change rather than
  a code reorganization.
- **Per-field line numbers without a hand-rolled scanner.** The
  strategy named field→line reconstruction as 80% of the risk; saphyr
  reduces that risk to choosing the right parser, which is now
  reduced further by saphyr being the actively-maintained successor
  to yaml-rust2.
- **The byte-for-byte preservation contract becomes testable code.**
  The preservation discipline applied across PRs gets a concrete
  acceptance gate. Future Rust changes to shirabe cannot accidentally
  regress GHA annotation output without the parity tests catching it.
- **The library-crate-publication follow-on doesn't pay a
  restructuring cost.** The workspace + library crate exist already;
  publication just decides API stability and the crates.io push.

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

### Risks the parent initiative already named

- *Reconstruction breaks byte-for-byte preservation in subtle ways.*
  The parent initiative's invalidation signal — extend the
  preservation fixture to include real artifacts if synthesized
  tests pass but real artifacts diverge. This design's Decision 3
  fixture already uses both real artifacts and synthesized cases;
  if Layer 1 passes but Layer 2 catches divergence on a real-adopter
  corpus, the synthetic-only direction was incomplete and the
  Layer 1 corpus extends to cover the divergence class.
- *Toolchain pinning surprises.* `rust-toolchain.toml` pins the
  channel; downstream Rust-version policy is downstream of this PR.
  Pinning to stable (not nightly) avoids the most obvious foot-gun.
