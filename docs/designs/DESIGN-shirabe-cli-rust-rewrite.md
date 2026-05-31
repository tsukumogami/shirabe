---
status: Planned
problem: |
  shirabe's deterministic surface (`shirabe validate` CLI, the line-number-aware
  YAML frontmatter parser, the ten validation rules, the GHA annotation
  emitter) is implemented in Go. Aligning this surface with koto's Rust
  substrate keeps cross-component composition structurally cheap and removes
  the Go/Rust seam that currently sits between shirabe and the rest of the
  toolkit's workflow tier. This design translates `cmd/shirabe/` +
  `internal/validate/` from Go to Rust while preserving the public contract
  byte-for-byte.
decision: |
  Translate the ~1,350 LOC of Go (cmd/shirabe + internal/validate +
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
  restructuring of every import path later. saphyr is the actively-maintained
  successor to yaml-rust2 with explicit `Span`/`marker` support on every node,
  so the field→line map shirabe needs falls out of the parse tree directly
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

Planned

## Context and Problem Statement

shirabe's deterministic surface is a small Go CLI (`shirabe`) with one
subcommand today (`validate`), backed by:

- About 1,350 LOC of Go across `cmd/shirabe/main.go` (104 LOC),
  `internal/validate/` (~1,213 LOC across `validate.go`, `checks.go`,
  `formats.go`, `frontmatter.go`, `doc.go`, and `table.go` — the
  issues-table engine), `internal/annotation/annotation.go` (35 LOC),
  and Go-side tests (~1,480 LOC across `checks_test.go`,
  `frontmatter_test.go`, and `table_test.go`). The validate package
  grew past the last tagged release: PR #134 added `table.go`,
  `table_test.go`, and the issues-table checks (see below), so the
  surface the rewrite ports is the current `main` tree, not `v0.6.1`
  (Decision 7).
- Two external dependencies: `github.com/spf13/cobra` (CLI framework) and
  `gopkg.in/yaml.v3` (frontmatter parsing).
- One callable contract: GitHub Actions annotation lines on stdout
  (`::error file=<path>,line=<N>::[CODE] message` and
  `::notice file=<path>::message`), exit code 1 if any error annotation was
  emitted, zero otherwise.

The validation logic encodes seven doc formats (Design, PRD, VISION,
Roadmap, Plan, Strategy, Brief) and ten check rules: the SCHEMA gate,
FC01–FC04 frontmatter checks, FC05/FC06 issues-table checks (header
profile and document-local dependency existence, run for Roadmap and
Plan), R6 (Plan upstream existence + git tracking), R7 (VISION
public-visibility), and R8 (STRATEGY public-visibility). Only two
rules — **FC02** (`status` enum) and **R6** (Plan upstream existence +
git tracking) — require **per-key line numbers from the YAML
frontmatter** so the rendered GHA annotation points at the offending
field rather than the top of the file. The Go implementation gets
these from `yaml.v3`'s `yaml.Node.Line` field, which is populated
during decoding.

The other eight rules don't consume YAML per-key positions: SCHEMA,
FC01, and FC04 hardcode `line=1`; FC03 (frontmatter `status` ↔ `##
Status` body match), R7, and R8 (prohibited sections in public VISION
and STRATEGY docs) read section lines from a separate Markdown body
scan (`scanBody` in `internal/validate/frontmatter.go`); FC05 and FC06
report the issues-table header line or a row line, both computed by the
table parser's own line tracking (`internal/validate/table.go`), not
from YAML node positions. This narrows the parser's per-key line-number
contract to two scalar field lookups (`status` and `upstream`);
everything else is independent of the YAML parser's position-tracking
surface.

Aligning shirabe's deterministic surface with koto's Rust substrate
keeps cross-component composition structurally cheap and removes the
Go/Rust seam that currently sits between shirabe and the rest of the
toolkit's workflow tier. This design translates the Go binary to Rust
while preserving the public output contract byte-for-byte. Four
technical questions must be answered before implementation can start:

1. **What Rust YAML parser provides per-key line numbers?** `serde_yaml`
   deserializes into Rust structs but discards source positions. The Go
   implementation depends on `yaml.v3`'s `Node.Line` for FC02 (`status`)
   and R6 (`upstream`) annotations — the only two checks that read
   per-key positions from the YAML mapping. This is the single
   non-trivial portability risk in the rewrite.
2. **How does the cobra subcommand tree translate to clap?** Mechanical,
   but the design should document the mapping so future shirabe
   subcommands inherit a conventional shape.
3. **How is output-contract preservation enforced as a test?** Byte-for-
   byte preservation against the current Go binary is an acceptance
   criterion, not aspiration; this design names the fixture mechanism.
4. **Single binary crate vs. Cargo workspace?** The validate logic will
   eventually want a library-crate boundary so koto and other Rust
   callers can link directly rather than shell out across a process
   boundary. Anticipating that boundary from day one avoids a
   structural re-port later.

A fifth question — does a separate `shirabe metrics` subcommand ship
inside this PR — is resolved in **Decision 5** below.

## Decision Drivers

- **Byte-for-byte output preservation is mandatory.** No v2 break
  window. Every GHA annotation, every exit code, every `--version`
  byte must match the Go binary on identical inputs.
- **Per-field line numbers are non-negotiable for FC02 (status) and
  R6 (upstream).** Today's Go output points GHA annotations at
  specific frontmatter keys; the Rust binary must do the same on the
  same files. Falling back to line 1 for these errors would be a
  behavior regression.
- **The rewrite must be a non-event for known internal pinning
  callers.** shirabe's own `.github/workflows/validate-docs.yml`
  consumes the published binary on tagged releases; any other
  workspace caller of the reusable workflow does the same. All must
  continue to pass on the day the Rust binary ships.
- **The Cargo crate layout must support a future library boundary
  without restructuring.** When koto or any other Rust caller commits
  to linking the validate logic directly (rather than shelling out to
  the binary), the library boundary needs to exist already; renaming
  every import path at that moment is a cost worth avoiding now for
  the price of one Cargo.toml split.
- **Test-suite parity, not test-suite migration.** The existing Go test
  suite (`checks_test.go`, `frontmatter_test.go`, `table_test.go`,
  ~1,480 LOC) covers the nine error rules, the schema gate, and the
  issues-table engine. The Rust implementation must hit the same
  logical assertions; whether it ports test-by-test or restructures is
  a tactical call inside the implementation.
- **Eval suite passes unchanged.** `scripts/run-evals.sh` and per-skill
  JSON fixtures stay in their current substrate. The Rust binary must
  satisfy the existing evals as a baseline acceptance criterion.
- **No new runtime dependencies on the host CI environment.** The Go
  binary needs only `git` on PATH (for R6's `git ls-files`). The Rust
  binary inherits the same minimum.
- **install.sh contract preservation.** The shell installer's URL
  pattern (`shirabe-<os>-<arch>` release asset names), install path
  (`~/.shirabe/bin/shirabe`), and PATH guidance are part of the
  public contract. Cargo-built binaries must match the same asset
  naming convention.

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
Go implementation's `parseYAMLFields`. The field→line reconstruction
that is this rewrite's single largest portability hazard is a 30-line
function in this approach, not a custom parser.

**Considered and rejected.**

- *`serde_yaml` + a hand-rolled second-pass line scanner.* serde_yaml is
  the de-facto Rust YAML library and pairs cleanly with serde derive, but
  it discards source positions entirely. Recovering per-key lines would
  require a second `bufio`-style scan of the frontmatter bytes, matching
  each key string to its first occurrence. **Rejected** because matching
  keys to lines correctly across multi-line scalars, anchor/alias
  expansion, and quoted-key edge cases is exactly the kind of subtle work
  this design flags as the rewrite's single non-trivial risk. Putting
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

**Why this isn't a strawman:** the rejected serde_yaml + hand-rolled
scan approach is the path most Rust CLI authors reach for first, and
it would plausibly work. The rejection is not because it cannot
succeed — it is because saphyr makes the same outcome free, and
concentrating risk in a hand-rolled YAML reconstruction is the worst
shape for the single largest portability hazard in the rewrite.

### Decision 2: CLI framework — cobra → clap mapping

**Question.** How does the cobra subcommand tree (`shirabe`, `shirabe
validate`, `--visibility`, `--custom-statuses`, `--version`) translate
to a clap idiom that future shirabe subcommands inherit cleanly?

**Key assumptions.**
- clap's `derive` macros are stable in clap v4 and are the conventional
  Rust shape (matching how cobra's struct-based config is the Go
  conventional shape).
- The subcommand surface today is tiny (one subcommand, two flags);
  the validator-side scaling profile for any future subcommands is
  similar (one subcommand each, a few flags each), so the framework's
  per-subcommand boilerplate dominates the cost calculation.

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
- *Hand-rolled argument parser.* Smallest possible dependency
  footprint. **Rejected** because shirabe already commits to one
  external dependency for YAML parsing (saphyr) and would gain nothing
  by avoiding clap; the cobra → clap translation is structurally
  mechanical, and picking a non-conventional approach turns mechanical
  work into exploratory work.

This decision is mechanical. The design records the chosen idiom so
future shirabe subcommands inherit a consistent pattern.

### Decision 3: Output-contract preservation mechanism

**Question.** How does the rewrite enforce byte-for-byte output
preservation against the Go binary's behavior on every committed artifact
in the workspace?

**Key assumptions.**
- The shirabe repo's preservation contract is bounded by what the
  shirabe repo itself can verify in its own public CI. The reusable
  `validate-docs.yml` workflow has callers in other repos; their
  preservation tests run in their own CI, not in shirabe's, because
  shirabe cannot embed their corpora directly (the source-of-truth
  for what's "their committed artifact set" lives in their repo).
- The shirabe-side fixture must exercise the full validation surface
  (all seven formats, all ten rules including the issues-table checks,
  edge cases on each) so external adopters see a representative
  preservation contract on the shirabe-side test surface.
- A captured Go binary at a frozen commit (the rewrite branch's
  merge-base with `main`; see Decision 7) is the immutable reference;
  once captured, the fixture asserts against it rather than rebuilding
  Go each run.

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
   failure paths, R7 and R8 success and failure paths (public
   VISION and STRATEGY docs with and without prohibited sections),
   FC05 paths (a wrong issues-table header for both the Roadmap and
   Plan profiles, the legacy four-column plan-table migration hint,
   and a missing-description-row shape) and FC06 paths (an entity
   row whose Dependencies value names no row in the same table), and
   a small set of **parser stress-test inputs** that exercise the
   panic surface (malformed UTF-8 in YAML, deeply nested
   mapping structure, anchor-cycle YAML). The stress-test set
   makes the "Rust panics go to stderr; parity catches
   divergence" argument live-tested rather than just asserted;
   without these inputs, the panic-surface mitigation is
   unfalsified by Layer 1.
2. `expected/` — for each corpus file, the captured stdout, stderr,
   and exit code produced by the baseline Go binary built from the
   pinned commit (Decision 7) running `validate <path>`. The capture
   is regenerated by `tests/fixtures/capture_go_baseline.sh`
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
      go-baseline-ref: 20fb8ed
      corpus-glob: "docs/**/*.md"
```

Workflow inputs:

| Input | Required | Description |
|-------|----------|-------------|
| `go-baseline-ref` | no | Git ref (commit SHA, tag, or branch) of the Go tree to build the baseline binary from. The workflow checks out this ref and runs `go build` rather than downloading a release, because no published tag carries the post-#134 contract (Decision 7). Defaults to the pinned baseline commit (`20fb8ed`). A caller pinning an older ref asserts against the contract at that ref. |
| `corpus-glob` | yes | Shell glob (interpreted by `find` or `git ls-files`) of files in the caller's checkout to test against. Files whose basename doesn't match a shirabe format prefix are silently skipped. |
| `rust-binary-version` | no | Tag of the Rust shirabe binary to download. Defaults to the workflow's own `uses:` ref (e.g. `v0.7.0` from `parity-check.yml@v0.7.0`), so callers usually don't set it explicitly. |

The workflow checks out the caller's repo, builds the Go baseline
binary from `go-baseline-ref` (the same build-from-ref mechanism
Layer 1's capture script uses), downloads the Rust release binary,
runs both against the matched files, and diffs output per-file. On
any byte mismatch on stdout, stderr, or exit code, the workflow
**exits non-zero** and writes the side-by-side diff to the GHA log
(same format Layer 1's `parity_test.rs` emits). Callers should treat
this workflow as a required check on PRs that touch their committed
corpus.

Layer 2 exists because shirabe's "preservation contract" extends
conceptually to every caller of `validate-docs.yml`, but the
shirabe repo cannot embed those callers' artifacts directly.
Giving them a reusable parity workflow lets each caller assert the
preservation contract against their own corpus on their own CI
without leaking content into shirabe.

Every PR in the Rust rewrite must pass Layer 1; Layer 2 is the
mechanism by which the byte-for-byte contract extends to callers
shirabe doesn't directly control.

**Known out-of-contract divergences.** The byte-for-byte contract
holds exactly on the GHA-annotation stdout surface for files that
exist and are readable — the surface callers actually consume, and
the surface the corpus exercises. Three runtime/build outputs were
verified to differ between the Go and Rust binaries during the O4
CLI port and are accepted as deliberate, bounded exceptions because
none is reachable by the parity corpus:

1. *IO read-failure annotation (stdout).* On an unreadable or
   missing file, Go emits `could not read file:` followed by the
   `os.PathError` string (e.g. `read <path>: open <path>: no such
   file or directory`); Rust emits `could not read file:` followed
   by the `std::io::Error` Display (e.g. `No such file or directory
   (os error 2)`). The shared prefix is byte-identical and the CLI
   trims Rust's intermediate `io error:` wrapper, but the OS-level
   error string is not made byte-identical — matching it would
   require fragile hardcoding of platform error text. This path is
   not in the corpus: a missing or unreadable file can't be
   committed as a deterministic fixture, and parity asserts on files
   that exist and are readable, so the path is unexercised by Layer 1
   and Layer 2.
2. *`--custom-statuses` invalid-YAML error (stderr only).* Go (cobra)
   wraps the failure with an `Error:` prefix, a usage block, and a
   `yaml.v3`-specific message tail; Rust emits the shared prefix
   `--custom-statuses contains invalid YAML: ` plus a saphyr-specific
   tail with no cobra wrapper. This is stderr, not the GHA annotation
   contract (GHA parses stdout), and is out of corpus.
3. *`--version` unversioned local default.* An unversioned local
   build prints `shirabe 0.0.0` on the Rust side (from
   `CARGO_PKG_VERSION` via `SHIRABE_VERSION`, per Decision 2) versus
   `shirabe dev` on the Go side. Release and CI builds inject the
   real version (`SHIRABE_VERSION` / `-ldflags`), so the published
   binaries converge; only unversioned local builds differ, and the
   default value isn't in the corpus.
4. *Control-character input (parse-error surface).* Go's `yaml.v3`
   rejects control characters at parse time with a single
   `yaml: control characters are not allowed` error, while saphyr
   accepts them and validates through to a normal result. Like the
   IO divergence, this lands on the parse-error / quoting surface
   rather than the consumed annotation contract, and it is out of
   corpus: a control character can't be committed as a deterministic
   fixture.
5. *Malformed-UTF-8 input (parse-error surface).* Go's `yaml.v3`
   errors when the input bytes aren't valid UTF-8; the Rust frontmatter
   reader uses `String::from_utf8_lossy`, which replaces invalid
   sequences with the U+FFFD replacement character and parses through.
   The two binaries therefore diverge on byte sequences that aren't
   valid UTF-8. This is the parse-error surface, not the annotation
   contract, and is out of corpus — invalid bytes can't be a committed
   text fixture (the coder keeps an `#[ignore]`'d corpus case marking
   the difference).

The contract these exceptions bound is precise: byte-for-byte on the
GHA annotation stdout for the corpus. The five above are an
unreproducible OS string on an unexercised path, a stderr message
outside the annotation contract, a build-time value that converges
in release, and two parse-error/quoting-surface differences on
uncommittable control-character and malformed-UTF-8 input. The tsuku
recipe and the release/install pipeline consume the injected
`--version`, not the
local default, so the recipe contract is unaffected.

**Why two layers instead of one fixture directory.** A single fixture
in this repo covering every committed artifact across every caller
would require embedding callers' corpora into shirabe — which doesn't
scale: the source of truth for what a caller considers their
committed artifact set lives in that caller's repo, and content
ownership decisions live there too. The two-layer split makes the
preservation contract portable: any caller (an existing workspace
caller, an external adopter, a future first-time user) gets the same
byte-equality guarantee by including `parity-check.yml` at a pinned
shirabe tag, without coupling shirabe's release cadence to their
corpus changes and without shirabe needing visibility into their
content.

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
  workspace's actual document corpus. The preservation contract
  scope is every existing committed artifact in workspace repos that
  consume `validate-docs.yml`; evals do not cover that corpus.
- *Snapshot testing with `insta`.* `insta` is the Rust de-facto snapshot
  library; using it would surface diffs cleanly. **Rejected** because
  `insta` is designed for the "I changed code, accept the new snapshot"
  workflow, and the contract here is "the Go output is the snapshot;
  Rust output must never deviate." Using `insta` would conflate the two
  directions of update. A plain assertion with side-by-side diff output
  matches the actual contract.

### Decision 4: Cargo crate layout

**Question.** Is the rewrite a single binary crate (one `Cargo.toml`,
everything in `src/`) or a Cargo workspace with a separate library
crate anticipating the library-crate boundary that follows from
convergence with koto?

**Key assumptions.**
- Convergence with koto's Rust substrate makes a library-crate
  boundary the eventual natural shape: koto's workflow templates may
  want to call shirabe's validate logic without shelling out, and a
  Rust crate boundary is the structurally cheap way to allow that.
  The publication itself (a crates.io push, API stability commitment,
  etc.) is out of scope for this PR.
- Until a concrete caller commits to linking, the library API stays
  "internal-shaped, public for distribution" — unstable across
  shirabe versions, locked only when the first call-site surfaces
  concrete requirements.
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
│   │       ├── checks.rs        (check_schema, check_fc01..06, check_plan_upstream, check_vision_public, check_strategy_public)
│   │       ├── table.rs         (Row, Table, RowKind, parse_issues_table)
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
distribution but no API stability guarantee across versions). Its
public surface during this PR mirrors the Go `internal/validate`
exports plus `internal/annotation`. A future publication PR will push
this crate to crates.io with the same code; the publishing decision
shifts, the layout does not.

**Considered and rejected.**

- *Single binary crate, restructure when publication lands.* Simplest
  now; pushes the workspace decision to the moment the future library
  publication happens. **Rejected** because the publication design
  will then need to negotiate every import path change at the same
  time it's negotiating the library API surface. Decoupling
  publication-as-code-shape (now) from publication-as-distribution
  (later) keeps each decision separable.
- *Single binary crate with `pub mod validate`.* Use Rust's module
  system in place of a separate crate; pull `validate` into a library
  crate when publication lands. **Rejected** because Cargo's
  `[[bin]]`/`[lib]` distinction at publication time still requires
  moving the module source into a new crate directory and updating
  every `mod`/`use` path. The diff is small in absolute terms but
  lands at exactly the moment the publication design needs cognitive
  bandwidth for library API decisions.
- *Three crates from day one (`shirabe-validate`, `shirabe-cli`,
  `shirabe-bin`).* Pre-anticipate a separate crate per future
  subcommand. **Rejected** because YAGNI: future subcommands
  haven't been designed yet and their crate-shape preferences are
  unknown, and the three-crate split adds workspace complexity for
  zero current benefit. Two crates is the minimum that bypasses the future
  publication-time import-path churn; more is speculation. Also,
  Decision 2 commits the clap subcommand tree to live in the binary
  crate; any future shirabe subcommand inherits that tree as a new
  `Commands` enum variant, not as a separate crate, so a three-crate
  split would put subcommand dispatch on the wrong side of a crate
  boundary.

### Decision 5: `shirabe metrics` subcommand timing

**Question.** Does a `shirabe metrics` subcommand ship inside this
PR, or as a separate PR after this rewrite lands?

**Key assumptions.**
- The metrics subcommand has no behavioral overlap with `validate`;
  its output is a small JSON or text report read by a scheduled GHA,
  not by the validate-docs reusable workflow.
- The byte-for-byte preservation fixture (Decision 3) is the
  load-bearing acceptance work in this PR; coupling metrics to that
  PR would either delay it or force a partial-completion shape.

**Chosen: separate PR. The metrics subcommand ships after this PR
lands.**

This PR ships the workspace, the validate logic, the parity fixture,
and the install/release plumbing. The metrics subcommand lands
afterward as its own PR.

Conflating metrics with the rewrite would put preservation-fixture
review attention against a feature that has no validation contract
to preserve.

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

**Implementation note: the `build.rs` toolchain check is warn-only.**
The design (and the PLAN's O4 outline) prescribed a `build.rs` runtime
check that the active toolchain matches `rust-toolchain.toml`. It is
implemented — `build.rs` does two jobs, version injection (Decision 2)
and `verify_toolchain()` — but as a **warn-only** check: on a mismatch
between the active `rustc` and the pinned `channel = "1.95.0"`, it
emits a `cargo:warning` and never aborts the build. The pin itself
stays the actual enforcement: `rustup` honors `rust-toolchain.toml`
automatically and CI installs the pinned toolchain via
`dtolnay/rust-toolchain` reading that file. The check exists to
surface drift (a deliberately overridden local toolchain) before it
could shift a `Debug`/`format!` byte the parity fixture depends on,
not to gate the build — softening any hard-fail reading to warn-only
keeps that drift signal without adding contributor friction. So the
prescribed check is present, in its warn-only variant, beyond the
strict pin.

### Decision 7: Captured Go baseline version pinning

**Question.** Which Go commit is captured as the parity fixture's
`expected/` baseline?

**Key assumptions.**
- The Go binary's behavior is deterministic on a given commit (the
  same source tree produces identical output for identical input).
- The validation surface on `main` has grown past the last tagged
  release. PR #134 merged after `v0.6.1` and added checks FC05, FC06,
  the issues-table engine (`internal/validate/table.go`,
  `table_test.go`), and the `IssuesTableColumns` field on
  `FormatSpec` (populated for `roadmap/v1` and `plan/v1`). The
  Strategy and Brief formats and check R8 (`checkStrategyPublic`)
  also landed after `v0.6.1`. None of these are in a tagged release
  yet — they are merged-but-unreleased on `main`.
- Because the rewrite atomically deletes the Go tree (Decision
  Outcome step 7 / Outline 5), the contract the Rust binary must
  preserve is whatever is live on `main` at cut time, not the last
  tag. A baseline that predates the merged-but-unreleased checks
  would let the cut silently drop them.

**Chosen: pin the baseline to the rewrite branch's merge-base with
`main` (the post-#134 tree), built locally — currently
`20fb8ed` (`v0.6.1-16-g20fb8ed`).**

Pinning to `20fb8ed` makes the parity baseline and the source the
Outline 5 cut deletes the *same commit*: there is no gap between
"what we captured as the contract" and "what we removed from the
tree," so the parity tests assert against exactly the Go behavior
being replaced. The immutability the baseline needs comes from the
commit pin itself, not from a frozen release artifact: a pinned
commit SHA is immutable, so building from it satisfies the
immutable-baseline intent a tagged release would otherwise have
served. There is no intermediate Go release to cut, and the team
deliberately declines to cut a throwaway one.

**Build the baseline from the pinned ref, do not download a release.**
Both parity layers produce the baseline binary by checking out
shirabe at the pinned ref and running `go build ./cmd/shirabe` at
runtime, rather than downloading a release asset. This is a
deliberate, documented deviation from the design's original Layer-2
framing, which had the workflow download a captured Go baseline
binary from a release: no published release carries the post-#134
contract, so there is no release asset to download. Decision 3's
Layer-2 description and inputs table are updated to match (the input
is `go-baseline-ref`, a git ref built from, not a release tag).

The `tests/fixtures/capture_go_baseline.sh` script (Layer 1) checks
out the pinned commit and runs `go build ./cmd/shirabe`, runs the
resulting binary against `corpus/`, and writes the stdout/stderr/exit
triple to `expected/`. The committed `expected/` is the output of the
Go tree the rewrite actually replaces. If `main` advances with a
Go-side validation change the team wants the Rust port to mirror
before the cut, the capture is re-run against the new commit and
`expected/` is updated as a separate change before the rewrite lands.
The script records the pinned commit SHA so the baseline is
reproducible.

The Layer 2 reusable `parity-check.yml` workflow (Decision 3) uses
the same build-from-ref mechanism: its `go-baseline-ref` input is a
git ref the workflow checks out and builds with `go build
./cmd/shirabe`, defaulting to the pinned baseline commit (`20fb8ed`),
rather than a release tag it downloads.

**Considered and rejected.**

- *Pin baseline to the `shirabe-go-v0.6.1` tag.* The most recent
  tagged release; the obvious "stable reference" choice. **Rejected**
  because the validation surface grew substantially after `v0.6.1`:
  the tag has five formats (Design, PRD, VISION, Roadmap, Plan) and
  seven checks (SCHEMA, FC01–FC04, R6, R7), whereas the pinned
  `20fb8ed` has seven formats (adding Strategy and Brief) and ten
  checks (adding FC05, FC06, R8). PR #134 specifically added FC05,
  FC06, the `IssuesTableColumns` field, and the `table.go` engine;
  the Strategy/Brief formats and R8 landed before #134 but still
  after `v0.6.1`. Capturing `v0.6.1` would make the Rust port
  reproduce a stale contract, and the Outline 5 Go-tree deletion
  would then silently drop two formats, three checks, and the entire
  issues-table validation surface that are live on `main`. This is
  the load-bearing argument for the rebaseline: the rewrite must
  preserve the contract at cut time, which is `main`, not the last
  tag.
- *Pin baseline to multiple Go commits and assert parity against
  all of them.* Maximally robust. **Rejected** as overkill — the
  rewrite ships against the single Go tree it deletes (the cut-time
  `main`), not a historical-version sweep.

## Decision Outcome

The rewrite ships as one PR that:

1. Adds a Cargo workspace at the repo root with two crates
   (`shirabe-validate` library, `shirabe` binary).
2. Implements the ten validation rules (including the FC05/FC06
   issues-table checks and the `table.rs` engine) and the GHA
   annotation emitter in `shirabe-validate` using `saphyr` for
   line-aware YAML parsing.
3. Wires the clap derive-based CLI in `shirabe` to mirror the cobra
   surface exactly (one `validate` subcommand, `--visibility`,
   `--custom-statuses`, `--version` with the same template).
4. Commits the golden-output fixture under `tests/fixtures/golden/`
   covering every shirabe-side committed artifact plus a synthetic
   edge-case corpus exercising all ten validation rules.
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
  workspace shape; a publication PR is a separate decision.
- Add any subcommand beyond `validate`. Other subcommands ship in
  their own PRs against the workspace this PR creates.
- Change the GHA annotation byte format, exit codes, install path,
  release asset naming, or `--version` template. All are preserved by
  the fixture.

The byte-for-byte preservation discipline is operationalized as
the two-layer parity mechanism (Decision 3). Every PR in this rewrite
and any follow-up PRs runs Layer 1; merging is gated on parity.

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
│  pub use table::{Row, RowKind, Table,           │
│                  parse_issues_table};           │
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
live in `shirabe-validate`. This boundary is the one a future
crates.io publication will expose; this design doesn't push the
library crate to crates.io.

**No API stability commitment.** The `pub use` list above looks like
a library API surface, but it isn't one yet — every export is
internal-shaped (public for distribution but unstable across
shirabe versions). The exports may rename, change signatures, or
disappear in any release without a deprecation cycle, since the only
caller is shirabe's own binary crate. Semantic versioning of
`shirabe-validate` as a library is a future decision, shaped by
whichever caller first commits to linking against it.
Until then, treat these exports as if they were `pub(crate)`.

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

**Extending the validator.** Two conventions a future contributor
needs to know without re-reading this design:

- *Adding a new check.* A check is a function
  `fn check_<name>(doc: &Doc, spec: &FormatSpec, cfg: &Config)
  -> Vec<ValidationError>` in `checks.rs`, called from
  `validate_file` in `validate.rs` in the order the existing
  checks are called. Checks return one error per violation;
  empty vec means pass.
- *Adding a new format.* Add one entry to `FORMATS` in
  `formats.rs` (the `FormatSpec` struct carries the name,
  prefix, schema version, required fields, valid statuses,
  required sections, and `issues_table_columns` — empty for
  formats without an issues table), plus optionally a match arm in
  `validate_file` if the format needs format-specific checks
  (the Go code dispatches `Plan` to `check_plan_upstream` plus the
  FC05/FC06 issues-table checks, `Roadmap` to the FC05/FC06 checks,
  `VISION` to `check_vision_public`, and `Strategy` to
  `check_strategy_public` via a `switch spec.Name`; the Rust port
  mirrors this with a `match`).

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
     │  ├─ parse_yaml_fields via saphyr (early_parse(false)):
     │  │    ├─ loader.early_parse(false); loader.load_from_str(yaml_str)
     │  │    ├─ walk mapping; for each (key_node, val_node):
     │  │    │    fields[key] = FieldValue { value: scalar_source_text(val),
     │  │    │                               line: key_node.span().start.line }
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
     │       Plan     -> check_plan_upstream (R6: file exists + git ls-files)
     │                   check_fc05 (issues-table header + row shape)
     │                   check_fc06 (issues-table dependency existence)
     │       Roadmap  -> check_fc05, check_fc06
     │       VISION   -> check_vision_public (R7: prohibited sections in public)
     │       Strategy -> check_strategy_public (R8: prohibited sections in public)
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
use saphyr::{MarkedYamlOwned, YamlDataOwned};

fn parse_yaml_fields(yaml_str: &str, fm_start_line: usize)
    -> Result<HashMap<String, FieldValue>, ParseError>
{
    // Load with early_parse(false) so every scalar keeps its original
    // source token in the Representation variant rather than being
    // reparsed to a typed value (see "Typed-scalar preservation" below).
    let mut loader = MarkedYamlOwned::loader();
    loader.early_parse(false);
    let docs = loader.load_from_str(yaml_str)?;
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
        // scalar_source_text returns the verbatim Representation token.
        let Some(key) = scalar_source_text(&key_node.data) else { continue; };
        let absolute_line = key_node.span.start.line() + offset;
        let value = scalar_source_text(&val_node.data)
            .map(|s| s.trim_end_matches('\n').to_string())
            .unwrap_or_default();
        fields.insert(key, FieldValue { value, line: absolute_line });
    }
    Ok(fields)
}

// Under early_parse(false) every scalar arrives as
// YamlDataOwned::Representation(source_text, ..); return that verbatim.
fn scalar_source_text(data: &YamlDataOwned<MarkedYamlOwned>) -> Option<String> {
    match data {
        YamlDataOwned::Representation(text, _, _) => Some(text.clone()),
        _ => None,
    }
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
— the original source token, not a reparsed canonical form. The Go
`parseYAMLFields` reads `valNode.Value` directly. To match this
byte-for-byte, the Rust parser preserves the original scalar source
lexical form rather than reparsing to a typed value: it loads the
document with saphyr's `early_parse(false)`, so every scalar arrives
as `YamlDataOwned::Representation(source_text, ..)` carrying the exact
source token, and a `scalar_source_text()` helper returns that text
verbatim. No reparse-to-canonical occurs and no
`as_yaml_string()`-style coercion is involved — a value like
`status: 1.50` stays `1.50`, not `1.5`. The parity fixture catches
divergence on this path, and it now genuinely exercises it: the
corpus includes a typed-scalar regression artifact
(`DESIGN-typed-scalar-status.md`, with `status: 1.50`) plus
null (`~`) and hex (`0x1F`) cases in a consumed field, so
`parity_test.rs` asserts source-text preservation on non-round-tripping
scalars rather than the claim resting on an incidentally-typed field.

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
`shirabe-validate::frontmatter` and doesn't leak into whichever
public API surface a future crates.io publication eventually
stabilizes.

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

**Phase 3 — Validation checks, issues-table engine, and annotation
emitter.**
Port `internal/validate/checks.go` and `internal/validate/validate.go`
to `shirabe-validate` (`checks.rs`, `validate.rs`), including the
issues-table checks FC05 and FC06 and the STRATEGY public-visibility
check R8 (`check_strategy_public`). Port `internal/validate/table.go`
(the issues-table parser and row classifier) to
`shirabe-validate::table`, with its `RowKind`/`Row`/`Table` types and
the `parse_issues_table` entry point. Add the `issues_table_columns`
field to the Rust `FormatSpec` and populate it for the `roadmap/v1`
and `plan/v1` formats (the only two formats with an issues table),
matching the Go `IssuesTableColumns` profiles. Port `internal/
annotation/annotation.go` to `shirabe-validate::annotation`. Port
`checks_test.go` and `table_test.go` cases. R6 (`check_plan_upstream`)
calls `std::process::Command::new("git")` with
`ls-files --error-unmatch --` — same semantic as the Go
`exec.Command`. Verify the Go unit-test corpus passes on the Rust
side.

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
(sanitize coverage, FC01–FC04 failure paths, FC05/FC06 issues-table
paths for the Roadmap and Plan profiles plus the legacy plan-table
migration hint, R6, R7, and R8 paths, parser stress-test inputs for
the panic surface, multi-line scalars, missing-frontmatter,
unrecognized format, mismatched body status). Run
`tests/fixtures/capture_go_baseline.sh` to populate `expected/`
against the Go binary built locally from the pinned commit
(Decision 7's merge-base with `main`, currently `20fb8ed`), not a
downloaded tag. Commit `corpus/` and `expected/` to the repo. Write
`parity_test.rs`. Verify every parity test passes.

Add `.github/workflows/parity-check.yml` as a reusable workflow
(`on: workflow_call:`) with inputs for `go-baseline-ref` and
`corpus-glob`. The workflow builds the Go baseline binary from
`go-baseline-ref` (checkout + `go build`, defaulting to the pinned
commit `20fb8ed`) and downloads the Rust release binary, runs both
against the caller's matched files, and asserts byte equality on
stdout, stderr, and exit code per file. The workflow is documented
in the design doc and ships as part of this design's deliverable.

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
against the committed `expected/` baseline (captured once from the
Go binary built locally at Decision 7's pinned commit), so Phases
1–4 don't need a live Go binary on the PR runner to run the fixture
— the baseline is immutable bytes on disk.

Phase 5 deletes `cmd/`, `internal/`, `go.mod`, `go.sum`; renames
the Rust binary from `shirabe-rs` to `shirabe`; and changes
`.github/workflows/validate-docs.yml`'s build step from
`go build ./cmd/shirabe` to `cargo build --release --bin shirabe`.
The deletion commit is reviewable as deletes-plus-one-workflow-
line-change in `git log -p`.

There is no cargo feature flag. The two languages coexist as
distinct build targets during Phases 1–4; Phase 5 is the cut.

### Out of scope for this design

- API-stability commitments on `shirabe-validate` (deferred until a
  concrete consumer surfaces with call-site requirements).
- crates.io publication of `shirabe-validate` (the workspace exists
  for the layout shape; publication is a separate decision).
- Any new subcommands beyond `validate` (other shirabe subcommands
  ship in their own PRs against the workspace this design creates).
- Any v2 break to the GHA annotation format, CLI surface, install
  contract, or release asset names. Byte-for-byte preservation
  forbids them.

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
structure. (YAML parser choice is the rewrite's single non-trivial
portability risk per Decision 1; the security framing here is
deliberately narrow because the parser's risk profile is correctness,
not exploitation.)

### Supply-chain posture for saphyr's 0.0.x version line

saphyr is published at v0.0.6 (June 2025) and the project's own
README notes the pre-1.0 API may shift. The design pins saphyr to a
specific patch version in `Cargo.toml` and commits the workspace
`Cargo.lock` (standard for the binary output; publication of the
library crate later is a separate concern and may relax this) so
CI builds are deterministic across runs. The documented fallback (drop to
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
preservation, not improvement; the rewrite is a non-event at the
security boundary just as at the output-contract boundary.

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

- **Single-language deterministic substrate.** Once this PR lands,
  the validate CLI is Rust, future shirabe subcommands land in the
  same crate, and the path to library publication is a Cargo manifest
  change rather than a code reorganization.
- **Per-field line numbers without a hand-rolled scanner.** Field→line
  reconstruction was the rewrite's flagged-largest portability risk;
  saphyr reduces that to choosing the right parser, which is in turn
  reduced by saphyr being the actively-maintained successor to
  yaml-rust2 with native marker support.
- **The byte-for-byte preservation contract becomes testable code.**
  The preservation discipline applied across PRs gets a concrete
  acceptance gate. Future Rust changes to shirabe cannot accidentally
  regress GHA annotation output without the parity tests catching it.
- **Future publication doesn't pay a restructuring cost.** The
  workspace + library crate exist already; a later publication PR
  just decides API stability and the crates.io push.

### Negative

- **Two-crate workspace adds a small upfront complexity.** A single
  binary crate would be marginally simpler today. The trade is
  intentional (see Decision 4) but real.
- **Captured Go binary in CI artifacts is a one-time cost.** The
  baseline capture script builds the Go binary once from Decision 7's
  pinned commit and commits the outputs. Refreshing the baseline (if
  `main` advances with a Go-side validation change we want to mirror
  before the cut) requires re-running the capture and updating
  `expected/`.
- **Rust toolchain in CI.** The validate-docs workflow now installs
  Rust instead of (or in addition to) Go for the build-from-source
  path. The `actions/cache` key for Rust target+registry is larger
  than the Go module cache; cache misses cost more.

### Mitigations

- *Workspace complexity:* documented in this design and locked to two
  crates; further splits require an SR-level design.
- *Baseline refresh cost:* the capture script is committed and idempotent;
  the recovery path is "rerun capture_go_baseline.sh against a freshly
  built Go binary at the pinned commit." The baseline is tied to a
  specific commit SHA (Decision 7), so it doesn't drift on later
  Go-side commits unless the team deliberately re-pins.
- *CI cache size:* the existing `actions/cache` step in
  `validate-docs.yml` already caches Go modules; the swap is to cache
  the Cargo registry + `target/` directory under a Cargo-specific
  cache key. Cache size is bounded by the Cargo build artifacts for
  saphyr + clap + their transitive dependencies (small).

### Pre-identified risks

- *Reconstruction breaks byte-for-byte preservation in subtle ways.*
  Recovery path: extend the preservation fixture to include real
  artifacts if synthesized tests pass but real artifacts diverge.
  Decision 3's fixture already uses both real shirabe artifacts and
  synthesized cases; if Layer 1 passes but Layer 2 catches divergence
  on a caller's corpus, the synthetic-only direction was incomplete
  and the Layer 1 corpus extends to cover the divergence class.
- *Toolchain pinning surprises.* `rust-toolchain.toml` pins the
  channel; downstream Rust-version policy is downstream of this PR.
  Pinning to stable (not nightly) avoids the most obvious foot-gun.
