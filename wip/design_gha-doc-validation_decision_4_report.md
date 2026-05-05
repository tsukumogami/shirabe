<!-- decision:start id="gha-binary-acquisition" status="assumed" -->
### Decision: GHA Reusable Workflow Binary Acquisition Strategy

**Context**
The `validate-docs.yml` reusable workflow, published in shirabe and consumed by downstream
repos via `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1`, needs the
`shirabe` binary on the runner at execution time. The runner is GitHub-hosted ubuntu-latest
with Go 1.21+ pre-installed. The acquisition strategy must satisfy five constraints: version
coherence (binary and workflow must match exactly), 60-second total wall-clock budget,
no additional runner setup, auditable and pinned security, and stability across all v1.x
patch releases.

The decision is irreversible in a practical sense: downstream repos pin the workflow by
major version (`@v1`), and a strategy change within v1.x would affect all callers
simultaneously. The correct time to choose is before v1 ships.

A full four-validator bakeoff was conducted (build-from-source, download, composite action,
embed-as-base64). Three validators survived to cross-examination; one (embed-as-base64)
was disqualified at the bakeoff phase.

**Assumptions**
- Go build time on ubuntu-latest with `actions/cache` for module and build caches is
  reliably 10-20 seconds. If wrong, the 60-second budget may be exceeded on cache miss.
- The shirabe Go CLI source lives in the same repository as the reusable workflow (shirabe repo).
  If moved to a separate repo, the checkout step requires adjustment.
- The v1 scope is a single reusable workflow (`validate-docs.yml`). If multiple reusable
  workflows requiring the binary are added during v1, a composite action should be introduced
  to avoid duplicating acquisition steps.
- `actions/cache` is considered a hard dependency of this strategy, not an optional optimization.

**Chosen: Build from source (checkout + go build)**
The reusable workflow includes steps that: (1) check out shirabe's own source at the running
ref using `actions/checkout` with SHA-pinned action, (2) restore the Go module and build
cache via `actions/cache`, and (3) build the binary with `go build -o /usr/local/bin/shirabe
./cmd/shirabe`. The binary is immediately available for the validation step. Total acquisition
time with warm cache: 10-20 seconds; cold: 25-35 seconds.

The complete acquisition block in the workflow:

```yaml
- name: Checkout shirabe source
  uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
  with:
    repository: tsukumogami/shirabe
    ref: ${{ github.action_ref }}
    path: .shirabe-src

- name: Cache Go modules and build cache
  uses: actions/cache@v4
  with:
    path: |
      ~/go/pkg/mod
      ~/.cache/go-build
    key: ${{ runner.os }}-go-${{ hashFiles('.shirabe-src/go.sum') }}
    restore-keys: |
      ${{ runner.os }}-go-

- name: Build shirabe binary
  run: |
    cd .shirabe-src
    go build -o /usr/local/bin/shirabe ./cmd/shirabe
```

**Rationale**
Build-from-source is the only option that provides automatic version coherence without
indirection. The workflow runs at commit X (the commit the @v1 tag resolves to); the binary
is compiled from commit X. No mapping logic, no artifact-upload dependency, no mismatch
risk. The security posture is strong: the source is inspectable by any contributor, and
the `actions/checkout` action is already SHA-pinned following shirabe's existing convention.

The primary alternative (download pre-built) requires a binary release pipeline — cross-
compilation, checksum generation, artifact upload — that doesn't exist in shirabe today.
Building that pipeline before v1 ships would delay the feature without improving the
user-facing outcome. Additionally, download requires resolving the moving `@v1` tag to a
specific release artifact URL, an indirection that introduces version-coherence risk if
a release upload fails. The validator who advocated for download conceded: "Download at v2."

The composite action pattern is architecturally sound for enabling future strategy changes
but premature for v1 given a single-workflow scope. The abstraction's benefit materializes
when multiple reusable workflows need the binary. At that point, extracting the acquisition
steps into a composite action is straightforward. Document it as a trigger for a future
decision, not a requirement now.

**Alternatives Considered**
- **Download pre-built binary from GitHub Releases**: Fastest acquisition (1-5s), industry-
  standard pattern for mature Go tools. Rejected because the binary release pipeline (cross-
  compilation, checksum upload) doesn't exist in shirabe and would be a blocking prerequisite
  for v1. Also introduces version-coherence indirection: the workflow must map `@v1` (a moving
  tag) to a specific release artifact, adding complexity and a potential gap if any upload step
  fails. Preferred approach for v2 once release infrastructure is established.
- **Composite action (actions/validate-docs)**: Provides abstraction enabling acquisition
  strategy changes between patch releases without breaking callers. Rejected as premature
  for v1: adds a file to maintain without delivering a benefit that will be exercised during
  the v1 lifecycle given single-workflow scope. Should be introduced when a second reusable
  workflow needs the binary, or at v2 when switching to download.
- **Embed binary as base64 in workflow YAML**: Zero acquisition time. Rejected: makes the
  workflow YAML unmaintainable (~7-20MB of base64), impossible to audit, explicitly violates
  the "auditable and pinned" security constraint, and updates require manual re-encoding.
  Disqualified at the bakeoff phase.

**Consequences**
- Each invocation of `validate-docs.yml` compiles the shirabe binary from source. With
  `actions/cache`, warm builds take 10-20 seconds; cold builds 25-35 seconds.
- The 60-second total budget is reliably met with caching. Cache miss scenarios push
  acquisition to the 25-35 second range, leaving 25-35 seconds for validation — sufficient
  for 5 doc files.
- No changes to the release pipeline are required for v1.
- Version coherence is guaranteed by construction: workflow and binary are always from the
  same commit.
- When shirabe adds a second reusable workflow needing the binary, the acquisition steps
  should be extracted to a composite action to avoid duplication. That extraction is a
  future decision, not a v1 concern.
- When the project establishes binary release infrastructure (for local distribution via
  tsuku or similar), revisit switching the GHA workflow to download at v2.
<!-- decision:end -->
