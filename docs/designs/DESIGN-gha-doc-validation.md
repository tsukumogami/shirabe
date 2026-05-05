---
status: Proposed
upstream: docs/prds/PRD-gha-doc-validation.md
problem: |
  shirabe's doc format rules exist only as prose. There is no executable
  representation: no CLI that encodes the rules, no reusable workflow that
  downstream repos can call, and no distribution path for local use. The one
  existing validator (validate-plan.sh) is a non-portable bash script hardcoded
  to shirabe's own path layout.
decision: |
  A Go CLI (`shirabe`) with a `cmd/shirabe` entry point and `internal/validate`
  logic using yaml.v3 `yaml.Node` for line-number-aware frontmatter parsing, flat
  sequential check functions driven by per-format `FormatSpec` configuration, and a
  GHA reusable workflow that builds the binary from source via `actions/cache` for
  warm performance. GoReleaser publishes pre-built binaries for tsuku and curl
  distribution.
rationale: |
  yaml.v3's Node API is the only standard Go approach that provides accurate
  key-level line numbers without an additional pass — required by the GHA annotation
  format. Flat sequential functions match the scale (5 formats, 6 checks) and keep
  the call graph fully visible. Build-from-source guarantees version coherence between
  the workflow and binary without a binary release pipeline as a v1 prerequisite;
  actions/cache keeps warm builds to 10-20 seconds within the 60-second budget.
---

# DESIGN: GHA Doc Validation

## Status

Proposed

## Context and Problem Statement

shirabe defines five doc formats (Design, PRD, VISION, Roadmap, Plan), each with
required frontmatter fields, a closed set of valid status values, a required set of
section headings, and format-specific structural rules. These rules are specified in
prose. There is no executable artifact that encodes them.

The technical problem has three parts:

**1. No portable validation binary.** The only existing validator is
`skills/plan/scripts/validate-plan.sh` — a bash script that calls other scripts by
relative path. It cannot be invoked from outside shirabe's repo. Any downstream repo
that wants validation must copy the script tree and keep it in sync manually.

**2. No reusable GHA workflow.** A reusable workflow (`on: workflow_call:`) runs in
the caller's repo context. To use Go validation logic, the workflow must obtain the
binary at runtime — either by building it from shirabe's source (a second checkout
step) or downloading a pre-built release artifact. Neither mechanism exists today.

**3. No distribution path for local use.** Plugin skills need the same validation
binary available locally. The Claude Code plugin system has no binary distribution
mechanism. A separate distribution path (tsuku recipe + curl install script) must
be established and the binary must be published via a release pipeline.

The solution requires three integrated components: a `shirabe` Go CLI that encodes
all validation rules, a reusable GHA workflow that builds and invokes it, and a
release pipeline that distributes pre-built binaries for local use.

## Decision Drivers

- **Go, not bash** (R13a): typed frontmatter parsing, `go test`, cross-platform
  binary compilation, no bash portability issues
- **Shared binary for CI and local use** (R13a): identical validation behavior in
  both contexts; no duplicate rule implementations
- **Two-layer scope control** (R2, R8): changed-files-only scan narrows to PR-touched
  files; schema version gate further narrows to opted-in docs
- **Collect-all before exit** (R12): errors must be buffered per file; a fail-fast
  pattern is explicitly rejected
- **Exact annotation format** (R11): `::error file=<path>,line=<N>::[CODE] message` —
  GHA annotation rendering is format-sensitive; any deviation produces plain text
- **60-second total budget including binary build** (R15): the checkout + build step
  must not consume the bulk of the budget; the validator itself must be fast
- **Zero files to copy** (R13): the entire validator lives in shirabe; downstream
  repos add one ~12-line caller file
- **CLI distributable via tsuku + curl** (R13a): pre-built binaries required for
  tsuku recipe and install script; requires cross-platform release pipeline
- **Schema version replaces canonical enum, not extends** (R9): `custom-statuses`
  override is full replacement; partial addition is not supported
- **Plan upstream uses `git ls-files HEAD`** (R6): the upstream file must be
  disk-present and git-tracked on the PR branch at the time validation runs
- **VISION visibility check fails closed** (R7): unknown or unset
  `github.repository_visibility` → apply the public-repo restriction

## Considered Options

### Decision 1: Go frontmatter and section extraction approach

The CLI must extract YAML frontmatter and Markdown `## ` headings with accurate line
numbers for each element — required by the GHA annotation format
(`::error file=<path>,line=<N>::`). Performance is not a constraint; correctness and
line number accuracy are.

Key assumptions:
- yaml.v3's `yaml.Node` type is the only standard approach that provides key-level line numbers without a second pass
- `## ` heading detection with `bufio.Scanner` and `strings.HasPrefix` is sufficient for all five formats

**Chosen: Manual byte scan + yaml.v3.** Scan for `---` delimiters to extract the
frontmatter block, feed it to `gopkg.in/yaml.v3` decoded into a `yaml.Node` tree
(which carries per-key `Line` fields relative to block start), scan the body
line-by-line for `## ` headings. Line numbers for annotations are computed by
offsetting yaml.Node positions by the frontmatter block start line.

Alternatives rejected:
- **goldmark + goldmark-meta**: goldmark-meta returns a position-less map; getting frontmatter key line numbers still requires yaml.v3, adding two dependencies for no benefit over the chosen approach.
- **adrg/frontmatter**: Covers delimiter splitting only; no position information; still needs yaml.v3 on top. Adds a dependency without reducing code.
- **bufio.Scanner without YAML library**: Parses YAML with string splitting on `": "`, which fails silently on quoted values containing colons and multi-line block scalars.

---

### Decision 2: Go module layout

The `shirabe` binary coexists in a repo containing skills, docs, and GHA workflows.
No public Go API is required in v1. The workspace convention (tsuku, niwa) is
`cmd/<binary>/` + `internal/` with `go.mod` at the repo root.

Key assumptions:
- Module path `github.com/tsukumogami/shirabe`, `go.mod` at repo root
- No public library API needed in v1

**Chosen: `cmd/shirabe` + `internal/validate`.** `cmd/shirabe/main.go` is the CLI
entry point; `internal/validate/` holds validation logic, testable with
`go test ./internal/...`. Only `go.mod` and `go.sum` appear at repo root from the
Go side; non-Go directories are undisturbed.

Alternatives rejected:
- **Flat root package**: Mixes Go with non-Go content at root; validation logic untestable independently of `main`.
- **cmd/shirabe + pkg/validate**: `pkg/` implies a public API the PRD explicitly rejects; breaks workspace convention.
- **shirabe/ subdirectory**: Creates a nested module; breaks `go test ./...` from repo root; requires a `cd` in GHA build step.

---

### Decision 3: Validation check architecture

Six checks run per file: a schema gate (R8), four universal checks (FC01-FC04), and
two format-specific rules (Plan R6, VISION R7). All errors must be collected before
exit. Per-format variation is primarily data-driven (which fields, which sections,
which statuses), not behavior-polymorphic.

Key assumptions:
- 2-5 formats at launch with slow growth; if format count reaches double digits, migrate to a registry
- Checks are stateless per file; all inputs come from the parsed `Doc` struct
- `internal/validate` package established by Decision 2

**Chosen: Flat sequential functions.** `validateFile(doc Doc, spec FormatSpec, config Config) []ValidationError` calls each check in sequence. `FormatSpec` carries per-format configuration. Format-specific rules run under a `switch spec.Name` block. Each check is a plain function, independently unit-testable without interface setup or registry initialization.

Alternatives rejected:
- **Check interface + registry**: `init()`-based global registration adds implicit execution order and a struct type per check; extensibility benefit is minor at this scale.
- **Per-format validator structs**: Universal checks still need explicit call sites in each `Validate()` method; adds 5 struct types for a data-parameterization problem.
- **Pipeline with middleware**: Threading accumulator and short-circuit booleans through every step adds incidental complexity; collect-all is trivially achieved with `append` in a flat function.

---

### Decision 4: GHA binary acquisition strategy

The reusable workflow runs in the caller's repo context on ubuntu-latest. It needs
the `shirabe` binary. The strategy is irreversible within v1 (all downstream callers
pin `@v1`). Version coherence is a hard requirement.

This decision went through the full Tier 4 bakeoff. Three of four validators
survived cross-examination; the download advocate and composite-action advocate both
conceded build-from-source is correct for v1.

Key assumptions:
- Build time with `actions/cache` (module + build cache) is 10-20s warm, 25-35s cold
- `actions/cache` is a hard dependency, not an optional optimization
- Single reusable workflow in v1 scope; a second workflow would justify a composite action

**Chosen: Build from source (checkout + go build).** The workflow checks out shirabe
at `${{ github.action_ref }}`, restores Go caches via `actions/cache`, and builds
with `go build -o /usr/local/bin/shirabe ./cmd/shirabe`. Version coherence is
guaranteed by construction. No binary release pipeline required for v1.

```yaml
- uses: actions/checkout@v4
  with:
    repository: tsukumogami/shirabe
    ref: ${{ github.action_ref }}
    path: .shirabe-src

- uses: actions/cache@v4
  with:
    path: |
      ~/go/pkg/mod
      ~/.cache/go-build
    key: ${{ runner.os }}-go-${{ hashFiles('.shirabe-src/go.sum') }}
    restore-keys: ${{ runner.os }}-go-

- run: cd .shirabe-src && go build -o /usr/local/bin/shirabe ./cmd/shirabe
```

Alternatives rejected:
- **Download pre-built binary**: Fastest (1-5s) but requires binary release pipeline as a blocking v1 prerequisite; also introduces version-coherence indirection. Preferred for v2 once GoReleaser pipeline is established.
- **Composite action**: Architecturally sound but premature for single-workflow v1 scope; introduce when a second reusable workflow needs the binary.
- **Embed as base64**: Zero acquisition time but unmaintainable (~7-20MB of base64 in YAML), unauditable; disqualified at the bakeoff phase.

---

### Decision 5: Release and distribution pipeline

Pre-built binaries for linux-amd64, linux-arm64, darwin-amd64, darwin-arm64 with
checksums are needed for the tsuku recipe and curl install script. sibling project
niwa uses GoReleaser with an identical artifact pattern.

Key assumptions:
- Module path and `./cmd/shirabe` main package match Decision 2
- `finalize-release.yml`'s `expected-assets` set to 5 (4 binaries + checksums.txt)

**Chosen: GoReleaser.** `.goreleaser.yaml` follows the niwa pattern exactly.
A `.github/workflows/release-binaries.yml` triggered on tag push runs GoReleaser
and uploads artifacts to the existing draft release.

Stable download URL pattern:
```
https://github.com/tsukumogami/shirabe/releases/download/v{VERSION}/shirabe-{os}-{arch}
https://github.com/tsukumogami/shirabe/releases/download/v{VERSION}/checksums.txt
```

Alternatives rejected:
- **Custom matrix build workflow**: ~3x more YAML for identical output; diverges from Go workspace convention; koto uses matrix only because Rust requires native runners.
- **Extend existing release.yml**: Would contaminate a language-agnostic reusable workflow with Go build steps, breaking its contract with downstream callers (niwa, koto).
- **Manual release**: Creates a blocking manual step; incompatible with shirabe's automated release infrastructure.

---

### Decision 6: CLI framework (implicit)

The `shirabe` CLI needs flag parsing and subcommand support for `shirabe validate`.

**Chosen: cobra.** Matches the tsuku and niwa workspace convention. Provides clean `--help` output, typed flags, and subcommand routing with minimal boilerplate.

Alternative rejected: **`flag` stdlib** — zero dependencies, but `shirabe` will grow beyond a single subcommand (local validation is one capability; others will follow). cobra is already the workspace standard.

---

### Decision 7: Annotation output stream (implicit)

GHA annotations (`::error`, `::notice`) can be written to stdout or stderr.

**Chosen: stdout.** GitHub Actions captures `::` workflow commands from stdout by default. Writing to stderr would require explicit step configuration to enable command processing.

Alternative rejected: **stderr** — non-standard for GHA workflow commands; requires additional workflow step configuration.

## Decision Outcome

The five decisions compose into a coherent system:

**The core** is a Go CLI at `cmd/shirabe` + `internal/validate`. yaml.v3's `yaml.Node`
type provides accurate key-level line numbers from frontmatter parsing — the only
approach in the evaluated set that solves this without a second pass. A flat
`validateFile` function driven by per-format `FormatSpec` configuration keeps the call
graph fully visible and each check independently unit-testable.

**The GHA workflow** builds the binary from shirabe's own source at the running ref
using a second `actions/checkout` + `actions/cache`. This guarantees that the binary
and workflow always correspond to the same commit, without requiring a binary release
pipeline as a v1 prerequisite. Warm builds take 10-20 seconds; cold builds 25-35
seconds — both within the 60-second total budget.

**The release pipeline** (GoReleaser, following niwa's convention) produces pre-built
binaries for four platforms attached to GitHub Releases. These serve the tsuku recipe
and `install.sh` — the two local distribution paths. The GHA workflow does not use
these binaries in v1; the two pipelines serve independent consumers.

The schema-version gate and changed-files-only scan together enable incremental
adoption: existing docs without a `schema` field are never validated until a team
explicitly opts them in, and only PR-touched files are ever considered.

## Solution Architecture

### Overview

The `shirabe` CLI reads Markdown doc files, validates each against its format's rules,
and writes GHA annotation strings to stdout. The reusable workflow wraps the CLI:
it computes changed files, builds the binary from source, and invokes it. The release
pipeline produces separate pre-built binaries for local distribution.

### Components

```
shirabe/
├── cmd/shirabe/
│   └── main.go                  # cobra setup, flag wiring, exit codes
├── internal/
│   ├── validate/
│   │   ├── doc.go               # Doc, FieldValue, Section, ValidationError types
│   │   ├── frontmatter.go       # byte-scan + yaml.Node parsing; body heading extractor
│   │   ├── formats.go           # FormatSpec map for all five formats
│   │   ├── checks.go            # checkSchema, checkFC01-FC04, checkPlanUpstream, checkVisionPublic
│   │   └── validate.go          # validateFile() orchestrator; Config type
│   └── annotation/
│       └── annotation.go        # ::error / ::notice formatter
├── .github/workflows/
│   ├── validate-docs.yml        # reusable workflow (on: workflow_call:)
│   └── release-binaries.yml     # GoReleaser pipeline on tag push
├── .goreleaser.yaml             # GoReleaser config (niwa pattern)
└── install.sh                   # curl install script
```

### Key Interfaces

**`Doc` struct** — intermediate representation produced by parsing, consumed by checks:

```go
type Doc struct {
    Path     string
    Schema   string
    Status   string
    Fields   map[string]FieldValue  // frontmatter fields with line numbers
    Sections []Section              // ## headings with line numbers
    Body     []string               // raw body lines (for FC03, R7)
}

type FieldValue struct { Value string; Line int }
type Section   struct { Name  string; Line int }
```

**`FormatSpec` struct** — per-format configuration, drives FC01/FC02/FC04:

```go
type FormatSpec struct {
    Name             string
    Prefix           string   // e.g. "DESIGN-"
    SchemaVersion    string   // e.g. "design/v1"
    RequiredFields   []string
    ValidStatuses    []string // replaced by custom-statuses when provided
    RequiredSections []string
}
```

**`ValidationError`** — one per GHA annotation:

```go
type ValidationError struct {
    File    string
    Line    int
    Code    string  // "FC01", "FC02", ...
    Message string
}
```

**`validateFile` signature:**

```go
func validateFile(doc Doc, spec FormatSpec, cfg Config) []ValidationError
```

**FC03 body extraction:** `checkFC03` finds the `## Status` section in `doc.Sections`,
then reads `doc.Body` from the section's line index + 1 until the first non-blank line.
That line is the comparison value. The comparison is case-insensitive. If no non-blank
line is found before the next `## ` heading or end of body, FC03 does not fire (no body
to compare). FC03 fires only when both the frontmatter `status` and a non-blank status
body are present and they differ.

**`checkPlanUpstream` scope (v1):** This check verifies (1) the `upstream` file exists
on disk and (2) is tracked by `git ls-files HEAD` in the caller's repo. It does not
check the upstream document's status (whether the upstream doc is `Accepted` or
`Planned`). The existing `validate-plan.sh` performs that third check; it is
intentionally out of scope for v1 — the PRD's R6 specifies only file existence and git
tracking. If upstream status checking is required in a future revision, it belongs in a
new check (FC05 or similar) using the same `Doc` parsing infrastructure.

**`Config`** — workflow-level inputs passed to validation:

```go
type Config struct {
    CustomStatuses map[string][]string // format → replacement enum
    Visibility     string              // "public" | "private" | ""
}
```

**GHA annotation output to stdout:**

```
::error file=<path>,line=<N>::[FC01] missing required field 'rationale'
::notice file=<path>::schema 'design/v0' not in supported range, skipping
```

### Data Flow

**CI path (GHA):**

```
workflow_call trigger
  → if not PR context (no GITHUB_BASE_REF): emit ::notice, exit 0
  → git diff --name-only BASE...HEAD → changed file list
  → actions/checkout (shirabe source) + actions/cache + go build → shirabe binary
  → custom-statuses input (YAML string from workflow_call) → --custom-statuses flag
  → shirabe validate --visibility=${{ github.repository_visibility }}
                     --custom-statuses=<yaml-string> <files>
      for each file:
        detect format by basename prefix
        parse frontmatter (yaml.Node) + body headings (bufio.Scanner)
        schema gate: schema not in supported range → ::notice, skip
        checkFC01 → checkFC02 → checkFC03 → checkFC04
        format-specific checks (checkPlanUpstream | checkVisionPublic)
        accumulate []ValidationError
      emit ::error for each ValidationError → stdout
      exit 1 if any errors; exit 0 otherwise
```

**Local path (skills):**

```
skill needs to validate a file
  → command -v shirabe
  → not found: offer tsuku install shirabe | curl script
  → found: shirabe validate <file>
  → annotation strings written to stdout (e.g. ::error file=...,line=N::message)
  → skill displays raw output; annotation format is human-readable in a terminal
  → (--format=human mode for cleaner terminal output is a v2 improvement)
```

## Implementation Approach

### Phase 1: Go module scaffold and frontmatter parser

Bootstrap the module and implement the parsing layer that everything else depends on.

Deliverables:
- `go.mod` (`module github.com/tsukumogami/shirabe`, Go 1.21+), `go.sum`
- `internal/validate/doc.go` — `Doc`, `FieldValue`, `Section`, `ValidationError` types
- `internal/validate/frontmatter.go` — delimiter byte-scan, yaml.Node parsing with line-number offset, body heading extractor
- `internal/validate/frontmatter_test.go` — table-driven tests: no frontmatter, malformed YAML, block scalars, missing delimiter, heading detection

### Phase 2: Format specs and universal checks

Add all five format definitions and the four universal checks.

Deliverables:
- `internal/validate/formats.go` — `FormatSpec` map for Design, PRD, VISION, Roadmap, Plan; schema version strings; required fields, statuses, sections
- `internal/validate/checks.go` — `checkSchema`, `checkFC01`, `checkFC02`, `checkFC03`, `checkFC04`
- `internal/validate/validate.go` — `validateFile` orchestrator, `Config` type
- `internal/validate/checks_test.go` — per-check table tests; custom-statuses replacement; FC03 absent-section behavior

### Phase 3a: Annotation formatter and CLI entry point

Wire the output layer and CLI before adding format-specific checks.

Deliverables:
- `internal/annotation/annotation.go` — `FormatError(err ValidationError)`, `FormatNotice(file, msg string)` → `::error`/`::notice` strings; sanitize all embedded field values (strip `\n` and `\r`) before formatting
- `cmd/shirabe/main.go` — cobra root + `validate` subcommand; `--visibility`, `--custom-statuses` flags; `--custom-statuses` accepts a raw YAML string parsed by `yaml.v3` into `map[string][]string` with a 64KB size guard before parsing; reads files from args, calls `validateFile` per file, writes annotations to stdout, exit 1 if any errors

### Phase 3b: Format-specific checks

Add Plan and VISION rules on top of the working CLI.

Deliverables:
- `internal/validate/checks.go` additions — `checkPlanUpstream` (git ls-files HEAD in caller working directory using discrete `exec.Command` args), `checkVisionPublic` (prohibited sections)

### Phase 4: GHA reusable workflow

Wire the workflow that calls the binary.

Deliverables:
- `.github/workflows/validate-docs.yml` — `on: workflow_call:` with a single `custom-statuses` input (optional, YAML string); `permissions: contents: read` declared explicitly; checkout + cache + build acquisition block; changed-files detection via `git diff --name-only`; `shirabe validate --visibility=${{ github.repository_visibility }}` invocation (visibility hardcoded from GHA context, not a caller input); job ID `validate-docs`. Callers scope which files trigger the workflow via the `paths:` filter on their calling workflow — no `docs-path` input is needed.

### Phase 5: Release pipeline and local distribution

Ship GoReleaser config, release workflow, and install script.

Deliverables:
- `.goreleaser.yaml` — four platforms (linux/darwin × amd64/arm64), binary format, `checksums.txt`, following niwa pattern; install target binary name is `shirabe` (the platform-suffixed GoReleaser artifact is renamed on install, matching niwa's convention)
- `.github/workflows/release-binaries.yml` — `goreleaser/goreleaser-action --skip=publish` on tag push; `gh release upload` to draft
- `install.sh` — platform-detect, download binary + checksums, SHA256 verify, rename to `shirabe`, install to `~/.shirabe/bin/`, optional PATH setup
- Update `expected-assets` to 5 in `finalize-release.yml` (the same file niwa uses; search for `expected-assets` in the shirabe repo to locate the exact line)
- Enable tag protection on `tsukumogami/shirabe` before pushing the first `v1` tag: require PR review for any tag move, disallow force-push to the tag

## Security Considerations

**Binary integrity vs. authenticity for local install.** `install.sh` verifies the
downloaded binary against `checksums.txt` using SHA256 before installation. This
closes the window for in-transit substitution or corruption. It does not verify that
the release artifact itself is authentic — a compromised release pipeline could produce
a tampered binary and a matching `checksums.txt` simultaneously. This is the standard
trust model for projects without code signing. Users who require authenticity guarantees
should build from source (`go build ./cmd/shirabe`). Adding SLSA provenance attestation
or sigstore signing is tracked as a v2 improvement.

**Annotation injection via frontmatter field values.** The CLI embeds frontmatter values
(status, upstream, section headings) in GHA annotation strings emitted to stdout. A
doc author who controls a caller's repo could craft a `status:` field containing a
newline followed by `::error file=...::injected` to inject arbitrary GHA annotation
commands into the workflow output. This cannot escalate permissions, but it corrupts CI
output and could mislead code reviewers. The annotation formatter in
`internal/annotation/annotation.go` must sanitize all embedded field values by stripping
`\n` and `\r` characters before formatting — not at each call site, but in the formatter
itself. This is a required implementation constraint for v1.

**`git ls-files HEAD` shellout argument handling and working directory.** `checkPlanUpstream`
shells out to `git ls-files HEAD` to verify that the `upstream` field value is tracked in
the caller's repo. The implementation must use `exec.Command` with discrete arguments (not
shell interpolation of the `upstream` field value), so a malformed upstream path cannot
inject shell commands. The shellout must run in the caller's repo working directory, not
in `.shirabe-src` — running it against the wrong directory would cause the check to query
the shirabe source tree, producing incorrect results. Confirm both constraints in code review.

**Reusable workflow permissions.** The workflow must declare `permissions: contents: read`
explicitly in the workflow YAML — relying on caller defaults is insufficient because
organization policies and repo settings vary. The workflow does not request write
permissions, does not pass `GITHUB_TOKEN` to the CLI, and does not make network calls
beyond GitHub infrastructure (checkout, module cache).

**Mutable tag references.** Callers who reference the reusable workflow as
`uses: tsukumogami/shirabe/...@v1` take a mutable tag dependency. The internal
`actions/checkout@v4` and `actions/cache@v4` references are similarly mutable; these are
GitHub-owned actions with a small compromise surface, and the workspace convention accepts
mutable tag references for them. All three are documented accepted risks. Callers who need
a stronger guarantee can pin to a full commit SHA. Protecting the `v1` tag against
force-push is a concrete Phase 5 checklist item: enable tag protection rules on the
`tsukumogami/shirabe` repo before the first v1 tag is pushed.

**`custom-statuses` input bounds.** The `--custom-statuses` flag accepts user-supplied
YAML, parsed by `yaml.v3`. The threat actor with access to this input also controls the
caller's repo; no cross-tenant exposure exists. The implementation must enforce a concrete
limit — 64KB maximum total YAML input, or 50 status values per format — to prevent
accidental resource exhaustion from a malformed input. The limit should be checked after
flag parsing, before validation begins.

**Error path data exposure.** Under normal execution the CLI reads files and writes
annotation strings; no content leaves the runner. Under abnormal exit (panic, unexpected
error), Go's runtime may write a goroutine stack to stderr that includes field values or
partial `git ls-files` output. GHA captures stderr. This is an edge case in a read-only
context with no cross-tenant exposure, but callers should be aware that stderr under
abnormal conditions can reflect doc file contents.

## Consequences

### Positive

- **Version coherence by construction.** Building from source at `github.action_ref` means the workflow and binary always come from the same commit. No mapping, no artifact upload dependency, no mismatch risk.
- **Single implementation.** One Go codebase serves CI (built in GHA) and local use (installed via tsuku or curl). Validation behavior is identical in both contexts.
- **Flat check architecture is readable and debuggable.** The call graph of `validateFile` is fully visible. Stack traces name real functions. Grep for `checkFC01` finds one definition and one call site.
- **Incremental adoption.** The schema-version gate and changed-files-only scan let teams opt in one doc at a time without a forced cleanup sprint.
- **Follows workspace conventions.** `cmd/shirabe + internal/validate`, GoReleaser, and `github.com/tsukumogami/shirabe` match tsuku and niwa. No new patterns to learn.

### Negative

- **`actions/cache` is a hard dependency.** Cold builds (25-35s) leave 25-35s for validation — sufficient for 5 files but less headroom than a warm build. Cache unavailability extends acquisition time.
- **Acquisition strategy is locked for v1.x.** Downstream repos pin `@v1`; switching from build-from-source to download in a patch release would affect all callers simultaneously.
- **Plugin binary must be installed separately.** `shirabe` is not bundled with the Claude Code plugin. Users who want local validation must run `tsuku install shirabe` or the curl script.
- **Adding a format requires editing `validateFile`.** The flat design has one explicit extension point. At 10+ formats, migration to a registry is recommended.

### Mitigations

- **Cache miss risk:** Warm builds (10-20s) leave 40-50s for validation — more than sufficient. Cold builds (25-35s) still meet the 60s budget. The risk is documented in the PRD's Known Limitations.
- **Strategy lock-in:** The PRD designates the download strategy as the preferred v2 approach. v2 is the natural migration point, and switching to a composite action at that time is straightforward.
- **Separate install:** tsuku recipe and `install.sh` provide single-command install paths. Skills check for the binary and emit a clear install instruction if it is not found.
- **`validateFile` extension point:** Adding a format requires editing `validateFile` for behavioral rules only; data-only changes (new required field, new status value) go in `formats.go`. At 10+ formats, flat functions refactor directly to interface implementations.
