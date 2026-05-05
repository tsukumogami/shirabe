<!-- decision:start id="go-module-organization" status="assumed" -->
### Decision: Go Module Organization for shirabe CLI

**Context**

The shirabe CLI (`shirabe validate [files...]`) is a new Go binary that validates
shirabe's five doc formats. It will be distributed via tsuku recipe, curl install
script, and built from source inside the GHA reusable workflow. The Go code coexists
in the same repo with non-Go content: `skills/`, `docs/`, `.github/`, `scripts/`.

Two sibling projects in this workspace — tsuku (`github.com/tsukumogami/tsuku`) and
niwa (`github.com/tsukumogami/niwa`) — both use `cmd/<binary>/` for the entry point
and `internal/` for implementation packages, with `go.mod` at the repo root. The
PRD explicitly states that no public Go API is needed in v1; callers always go
through the CLI binary.

**Assumptions**

- Module path is `github.com/tsukumogami/shirabe` with `go.mod` at the repo root.
  If the team uses a different module root (e.g., a nested `shirabe/` subdirectory),
  the `cmd/ + internal/` split would still apply within that root, but the GHA build
  step would require a `cd`.
- "go test ./..." in the constraints means from the module root (the repo root under
  this layout), not from an arbitrary working directory.

**Chosen: cmd/shirabe + internal/validate**

The module is rooted at the repo root with `go.mod` declaring `module github.com/tsukumogami/shirabe`.
Two subdirectories hold the Go code:

- `cmd/shirabe/` — CLI entry point. Contains `main.go` and any cobra command files.
  This package is thin: it wires flag parsing, delegates to internal packages, and
  handles exit codes. The `shirabe` binary is built with `go build ./cmd/shirabe`.
- `internal/validate/` — validation logic: frontmatter extraction, check execution
  (FC01-FC04 and format-specific rules), GHA annotation emission. The `internal/`
  path enforces at the Go toolchain level that external modules can't import these
  packages, matching the PRD's explicit "no public API" requirement.

Additional internal packages (`internal/frontmatter/`, `internal/annotation/`, etc.)
can be added as the implementation evolves without restructuring. Additional
subcommands can be added as files in `cmd/shirabe/` or as separate command packages
under `cmd/`. Only `go.mod` and `go.sum` appear at the repo root from the Go side;
the existing non-Go directories are undisturbed.

**Rationale**

This layout satisfies every constraint: `go test ./internal/...` runs validation
logic without a subprocess; `internal/` prevents unintended external imports; the
repo root stays clean with only `go.mod`/`go.sum` as additions; `go build ./cmd/shirabe`
from the repo root requires no `cd` step in GHA; and the layout matches the tsuku and
niwa workspace conventions exactly. It handles v1's one-subcommand scope without
over-engineering, while scaling naturally if future subcommands or internal packages
are added.

**Alternatives Considered**

- **Flat root package**: All Go files at the repo root alongside `skills/`, `docs/`,
  etc. Rejected because it violates the "no repo root pollution" constraint and makes
  it impossible to test validation logic independently of the CLI entry point (both
  live in `package main`).

- **cmd/shirabe + pkg/validate**: Same structure as the chosen option but with `pkg/`
  instead of `internal/`. Rejected because `pkg/` implies a public, importable API —
  a commitment the PRD explicitly discards. It also breaks workspace convention; tsuku
  and niwa both use `internal/` exclusively.

- **shirabe/ subdirectory for all Go**: All Go code in a nested `shirabe/` directory
  with its own `go.mod`. Rejected because the module path becomes awkward, `go test ./...`
  from the repo root would not pick up tests inside a nested module, and the GHA build
  step would require an explicit `cd shirabe`. The non-Go directories (`skills/`, `docs/`)
  are already clearly named and don't create ambiguity at the root that would justify
  this extra indirection.

**Consequences**

- The repo root gains `go.mod`, `go.sum`, and the `cmd/` directory. Skills and docs
  content is unaffected.
- GHA build step: `go build -o shirabe ./cmd/shirabe` from the checkout root — simple,
  no directory navigation.
- Validation logic is fully unit-testable: `go test ./...` or `go test ./internal/...`
  from the module root.
- External modules cannot accidentally take a dependency on `internal/` packages,
  preserving freedom to refactor without semver concerns.
- If a future subcommand (`shirabe lint`, `shirabe check`) is added, it goes in
  `cmd/shirabe/` alongside the existing command files — no restructuring.
<!-- decision:end -->
