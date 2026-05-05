# Architecture Review: DESIGN-gha-doc-validation

**Scope:** Solution Architecture, Implementation Approach phases, and data flow analysis.

---

## 1. Is the Solution Architecture concrete enough to implement?

### What is present and sufficient

The architecture provides enough for an implementor to begin without ambiguity on the core path:

- File tree is specified down to individual `.go` file names with a single-line description of each file's responsibility.
- All key interfaces are specified in Go: `Doc`, `FieldValue`, `Section`, `ValidationError`, `FormatSpec`, `Config`, and `validateFile`.
- The GHA acquisition block is given as literal YAML, including the exact `checkout`/`cache`/`build` step sequence.
- Annotation output format is given with examples.
- GoReleaser and release workflow are explicitly delegated to the niwa pattern, which exists and can be read directly.

### Missing or underspecified components

**1. `validate-docs.yml` inputs are not specified.**

The design names the workflow and its job (`validate-docs`) and references two inputs (`custom-statuses`, `docs-path`), but does not define:

- the full `on: workflow_call: inputs:` block — field types, defaults, whether `docs-path` is `required`, what it controls (a subdirectory filter? a glob? the base path for relative file resolution?)
- `docs-path` appears only in Phase 4's deliverable list and in the binary acquisition YAML snippet (it's absent there). Its semantics are entirely implicit. If it filters which changed files are passed to `shirabe validate`, that filtering logic needs to be spelled out.
- The `visibility` input: R7 requires passing `github.repository_visibility` to the CLI. The design shows `--visibility=<vis>` as a CLI flag but doesn't mention a corresponding workflow input. The workflow must surface it (probably hardcoded from `github.repository_visibility` context, not a caller input), and the design doesn't clarify which approach.

**2. `checkFC03` behavior on body-frontmatter mismatch is underspecified.**

FC03 checks that the frontmatter `status` matches the `## Status` section body. The PRD (R11) says the annotation line is "the line of the `## Status` heading." But what the body of `## Status` means in practice — how many lines to read, how the comparison value is extracted — is not defined. The existing `validate-plan.sh` doesn't implement FC03 at all, so there's no reference implementation. An implementor must guess whether the check reads the next non-blank line after `## Status`, searches for a status-like token, or does a full substring match. This ambiguity will surface in test-writing and may produce an inconsistent implementation.

**3. `checkPlanUpstream` scope creep from the existing script.**

The current `validate-plan.sh` checks three things for `upstream`:

1. File exists on disk
2. File is git-tracked (`git ls-files --error-unmatch`)
3. Upstream doc `status` is `Accepted` or `Planned`

R6 in the PRD specifies only checks 1 and 2. The design's `checkPlanUpstream` description also only lists checks 1 and 2. Check 3 (upstream status validation) is silently dropped. Whether this is intentional or an oversight is not documented. If it's intentional, the design should say so; if it's an oversight, the check needs to be added back. Either way, an implementor reading the design today would produce an incomplete check relative to the existing script.

**4. Exit code contract is not defined.**

The data flow diagram says "exit 1 if any errors; exit 0 otherwise" but the CLI's full exit code contract is not stated in the Key Interfaces section. The existing `validate-plan.sh` uses three exit codes (0, 1, 2, 3) with distinct semantics. The design conflates parse errors, validation errors, and file-not-found errors into a single "exit 1." An implementor needs to know: does a file that cannot be opened produce an annotation and exit 1, or is it a separate error category? The GHA caller workflow also needs to know what exit codes it should treat as failures versus bugs.

**5. `install.sh` install path.**

The design states the install script installs to `~/.shirabe/bin/`. The niwa install script installs to `~/.niwa/bin/`. The pattern is consistent, but the design doesn't specify whether the `shirabe` binary is installed as `shirabe` (so `command -v shirabe` works) or as `shirabe-<os>-<arch>` (the GoReleaser binary name). The GoReleaser config for niwa uses `name_template: "{{ .Binary }}"` with `binary: niwa-{{ .Os }}-{{ .Arch }}` — the release artifact name includes the platform suffix. The install script downloads under the platform-suffixed name and installs it as the plain name (`mv "$TEMP_DIR/niwa" "$INSTALL_DIR/niwa"`). The design should confirm this same rename convention for `shirabe`.

**6. tsuku recipe is mentioned but not described.**

Distribution via `tsuku install shirabe` is referenced multiple times but the recipe format and location are never described. An implementor building the release pipeline doesn't know what the tsuku recipe looks like or whether it lives in the `tsuku` repo (which owns `recipes/`) or in `shirabe`. This is likely out of scope for the shirabe design itself (it belongs to the tsuku repo), but the design should say so explicitly rather than leaving it implied.

**7. `go.sum` and module bootstrap.**

The design says `go.mod` and `go.sum` are Phase 1 deliverables, but it doesn't specify the Go version (`go 1.21+` appears in the frontmatter decision but not the module scaffold description). Phase 1 also doesn't list the dependency on `gopkg.in/yaml.v3` and `github.com/spf13/cobra` as explicit `go get` steps. This is minor — an experienced Go dev would know — but a less-experienced implementor might miss the `go.sum` implications.

---

## 2. Are the Implementation Approach phases correctly sequenced?

### Sequencing is mostly correct

The phases reflect the correct dependency order:

- Phase 1 (types + parser) is a correct prerequisite for everything else.
- Phase 2 (specs + universal checks) correctly comes before Phase 3 (format-specific checks + CLI).
- Phase 4 (GHA workflow) correctly comes after Phase 3 (the workflow calls the CLI).
- Phase 5 (release pipeline) is independent of Phases 3-4 and can run in parallel, but placing it last is fine.

### Issues

**Phase 3 groups too much into one deliverable.**

Phase 3 adds `checkPlanUpstream`, `checkVisionPublic`, the `annotation` package, and the full cobra CLI entry point. These are independent. If the cobra wiring turns out to be complex (flag parsing, `--custom-statuses` YAML deserialization, file argument handling), it could block the format-specific checks or vice versa. Splitting the annotation package and CLI entry point into their own mini-phase, or at minimum calling it out as two separable workstreams within Phase 3, would reduce integration risk.

**Phase 4 (`validate-docs.yml`) has an implicit dependency on the `docs-path` input semantics that isn't resolved earlier.**

Because the workflow's input interface is not defined in the Architecture section, Phase 4's implementor must invent it. If the semantics turn out to be wrong (e.g., `docs-path` is a filter on changed files but the changed-file detection logic runs before `docs-path` is applied), it creates rework. The workflow input contract should be resolved during Phase 3 design, not discovered during Phase 4 implementation.

**Phase 5 does not mention `finalize-release.yml` integration.**

The niwa release pipeline uses two workflows: `release.yml` (which calls shirabe's reusable `release.yml`) and a separate `finalize.yml` (which calls shirabe's `finalize-release.yml`). The design's Phase 5 mentions only `release-binaries.yml` triggered on tag push. It does not specify whether the new `release-binaries.yml` is standalone or whether it integrates with the existing `release.yml` / `prepare-release.yml` workflows already in shirabe. The niwa pattern has a `finalize.yml` that calls `finalize-release.yml` with `expected-assets: 5` — the design notes updating `expected-assets` to 5 but doesn't clarify which workflow file that setting lives in. An implementor needs to know whether a new standalone `release-binaries.yml` coexists with the existing release infrastructure, or replaces/extends it.

---

## 3. Are there simpler alternatives that were overlooked?

### The major choices are well-reasoned

The design evaluates the key decision space thoroughly. The build-from-source acquisition strategy, yaml.v3 Node API, flat function architecture, cobra, and GoReleaser are all defensible choices with written rationale. The bakeoff for Decision 4 is thorough.

### One missed simplification: `github.repository_visibility` as a GHA context value

The design treats VISION's public-repo check (R7) as requiring the `--visibility` flag to be passed from the workflow caller. But `github.repository_visibility` is available as a GHA context expression directly in workflow YAML (`${{ github.repository_visibility }}`). The workflow can embed this as a hardcoded step that always passes the runner's repo visibility to the CLI — no caller input needed, no documentation burden on downstream repos. The design's data flow diagram (`shirabe validate --visibility=<vis>`) suggests this is the intended approach, but Decision 2's `Config` struct introduces a caller-configurable `Visibility` field that implies it could also be set by the caller. Clarifying that `visibility` is always populated from the GHA context (not a `workflow_call` input) would eliminate confusion and simplify the workflow's documented interface.

### One missed simplification: `docs-path` input may be unnecessary

The design mentions a `docs-path` input to `validate-docs.yml` but the PRD's acceptance criteria and requirements make no mention of a path filter beyond changed-files-only detection. Changed-files-only already limits the scope to PR-touched files. A `docs-path` filter adds a layer that requires documentation, implementation, and testing. If the only use case is "only look at files under `docs/`," callers can already express that via the `paths:` trigger on their calling workflow. The design should either justify `docs-path` with a concrete use case, or remove it.

### Composite action not reconsidered for Phase 5

Decision 4 correctly rejects a composite action for v1 (single workflow). But the release pipeline (Phase 5) adds a second consumer of the binary: local install. If a composite action were introduced in v2 anyway (as the design anticipates), the binary acquisition block could be extracted at that point. The design correctly defers this but could make the migration path more concrete.

---

## 4. Is the data flow clear and complete?

### CI path

The CI data flow is clear for the happy path: PR triggers workflow → changed files detected → binary built → `shirabe validate` invoked → annotations emitted → exit code drives job result. The sequencing is unambiguous.

Gaps:

- **The flow does not show what happens when `actions/cache` misses.** The binary build step runs either way (cache hit or miss), but the time budget implications are not reflected in the flow. This is mentioned in Consequences but not in the flow diagram itself.
- **The flow omits the non-PR context branch** (workflow_dispatch or push trigger). R2 specifies exit 0 with a notice in non-PR contexts. The data flow should have a branch for this.
- **The flow does not show how `--custom-statuses` YAML is serialized by the workflow and deserialized by the CLI.** The `FormatSpec` and `Config` types are defined, but the marshaling path (workflow input YAML → flag string → parsed `Config`) is implicit. If `--custom-statuses` accepts a raw YAML string, the CLI must parse it; the design doesn't say which YAML library function handles this or whether it reuses `gopkg.in/yaml.v3`.

### Local path

The local data flow is sparse:

- "skill parses or displays to user" — what does a skill actually do with `::error` annotation strings that were designed for GHA stdout capture? In a local terminal context, `::error file=...,line=N::message` is readable but not rendered. The design doesn't address whether skills invoke `shirabe` and post-process its output, or whether `shirabe` has a `--format=human` mode for local use. If skills are expected to pipe the annotation output through a formatter, that's a missing component. If the annotation format is fine as-is in a terminal, the design should say so.

### Release pipeline data flow

The release data flow is entirely absent. The design describes the release pipeline as a Phase 5 deliverable but provides no flow showing: tag push → `release-binaries.yml` triggers → GoReleaser builds artifacts → artifacts uploaded to draft release → `finalize-release.yml` promotes. The connection to the existing `prepare-release.yml` / `release.yml` orchestration is not drawn.

---

## Summary of Findings

**Blockers for implementation:**

1. `validate-docs.yml` input interface is not defined (`docs-path` semantics, `visibility` source).
2. FC03 body extraction logic is not specified.
3. The upstream status check (third check in `validate-plan.sh`) is silently dropped without documentation.

**Ambiguities that will cause implementor guessing:**

4. Exit code contract for parse errors vs. validation errors vs. file-not-found.
5. Whether `shirabe` binary is renamed on install (platform suffix removal).
6. How the `release-binaries.yml` integrates with existing `prepare-release.yml` / `release.yml` infrastructure.

**Minor gaps:**

7. `docs-path` input lacks justification and may be unnecessary.
8. Local output format for skills using `shirabe` in a terminal context.
9. Go version and dependency bootstrap are implicit.
10. Non-PR context branch is missing from the CI data flow.
