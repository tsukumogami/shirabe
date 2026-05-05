<!-- decision:start id="shirabe-binary-release-pipeline" status="assumed" -->
### Decision: Pre-built shirabe binary build and publish pipeline

**Context**

The shirabe CLI must be installable via `tsuku install shirabe` and a curl | bash
install script. This requires pre-built binaries for linux-amd64, linux-arm64,
darwin-amd64, and darwin-arm64, attached to GitHub Releases with SHA256 checksums.
The tsuku recipe TOML and the curl install script both depend on a stable, predictable
download URL pattern known in advance.

shirabe already has release infrastructure (release.yml, finalize-release.yml,
prepare-release.yml) that handles version stamping, tag creation, and draft-to-published
promotion. The binary build step must fit into this pipeline without breaking the
reusable workflow contract that downstream repos (niwa, koto) rely on.

The sibling project niwa is a Go CLI in the same org with an identical set of
distribution requirements. niwa uses GoReleaser (.goreleaser.yaml) with the
goreleaser/goreleaser-action in a dedicated release workflow triggered on tag push.
It produces raw binaries named `niwa-{os}-{arch}` and a checksums.txt, uploads them
to the existing draft release, and relies on finalize-release.yml to promote.

**Assumptions**

- The shirabe Go module will be named `github.com/tsukumogami/shirabe` with `go.mod`
  at the repo root and `./cmd/shirabe` as the main package path, consistent with prior
  module layout decisions and workspace convention. If the module path differs, the
  `.goreleaser.yaml` `main:` field needs adjustment but the approach is unchanged.
- Binary artifact upload happens between tag push (release.yml) and draft promotion
  (finalize-release.yml). finalize-release.yml's `expected-assets` input will be set
  to 5 (4 binaries + checksums.txt). This is consistent with how niwa's finalize.yml
  is configured.
- This decision is made in --auto mode without user confirmation, so status is
  "assumed" per protocol.

**Chosen: GoReleaser**

Add a `.goreleaser.yaml` at the shirabe repo root. Add a dedicated
`.github/workflows/release-binaries.yml` triggered on tag push (`v*`) that runs
GoReleaser via `goreleaser/goreleaser-action` with `--skip=publish`, then uploads
the output artifacts to the existing draft release using `gh release upload`.

The `.goreleaser.yaml` follows the niwa pattern exactly:

```yaml
version: 2

builds:
  - id: shirabe
    main: ./cmd/shirabe
    binary: shirabe-{{ .Os }}-{{ .Arch }}
    env:
      - CGO_ENABLED=0
    goos:
      - linux
      - darwin
    goarch:
      - amd64
      - arm64
    flags:
      - -trimpath
      - -buildvcs=false
    ldflags:
      - -s -w -X github.com/tsukumogami/shirabe/internal/buildinfo.version={{.Version}}
    mod_timestamp: "{{ .CommitTimestamp }}"
    no_unique_dist_dir: true

archives:
  - format: binary
    name_template: "{{ .Binary }}"

checksum:
  name_template: checksums.txt
  algorithm: sha256

changelog:
  disable: true

release:
  disable: true
```

This produces four binaries and checksums.txt in `dist/`:
- `dist/shirabe-linux-amd64`
- `dist/shirabe-linux-arm64`
- `dist/shirabe-darwin-amd64`
- `dist/shirabe-darwin-arm64`
- `dist/checksums.txt`

**Artifact URL pattern** (stable, for tsuku recipe and curl script):

```
https://github.com/tsukumogami/shirabe/releases/download/v{VERSION}/shirabe-{os}-{arch}
https://github.com/tsukumogami/shirabe/releases/download/v{VERSION}/checksums.txt
```

**tsuku recipe TOML** (to be authored in tsuku's recipes/ directory):

The tsuku recipe references the above URL pattern. The platform field maps
`linux/amd64` → `linux-amd64` etc. The checksum file uses the sha256 algorithm.
Example structure (actual TOML syntax follows tsuku recipe conventions):

```toml
[package]
name = "shirabe"
description = "Workflow skills plugin and doc format validator"

[[version]]
provider = "github"
repo = "tsukumogami/shirabe"

[[platform]]
os = "linux"
arch = "amd64"
url = "https://github.com/tsukumogami/shirabe/releases/download/v{version}/shirabe-linux-amd64"
checksum_url = "https://github.com/tsukumogami/shirabe/releases/download/v{version}/checksums.txt"
checksum_file = "shirabe-linux-amd64"

# ... (similar entries for linux-arm64, darwin-amd64, darwin-arm64)

[[action]]
type = "install_binaries"
files = ["shirabe"]
```

**curl install script** (at `install.sh` in the shirabe repo):

The install script follows the koto install.sh pattern: detect OS/arch, resolve
version from GitHub releases API (or use pinned `--version`), construct download URL,
download binary + checksums.txt, verify SHA256, install to `~/.shirabe/bin/shirabe`,
and optionally add to PATH via shell config. This is the same pattern koto uses.

**Rationale**

GoReleaser is the established pattern for Go CLIs in this workspace. niwa uses this
exact setup and produces identical artifact structure. Reusing the pattern gives
shirabe consistent tooling without any novel behavior to validate. The custom matrix
alternative (alternative 2) is technically equivalent but requires ~3x more YAML
for the same output and would diverge from the Go workspace convention for no benefit.
Extending release.yml (alternative 3) would contaminate a language-agnostic reusable
workflow with Go-specific build steps, breaking its contract with downstream callers.
Manual release (alternative 4) is incompatible with shirabe's automated release
infrastructure and creates an error-prone gap in the distribution chain.

**Alternatives Considered**

- **Custom matrix build workflow**: Write a matrix GHA workflow with separate
  GOOS/GOARCH jobs, artifact upload/download steps, and custom sha256sum scripting.
  Rejected because it produces identical artifacts with ~3x more YAML, diverges from
  the niwa (Go) convention for no gain, and puts bespoke maintenance burden on the
  team. koto uses this pattern only because Rust cross-compilation requires native
  runners; Go doesn't have that constraint.

- **Extend existing release.yml**: Add Go build steps to shirabe's reusable
  release.yml or finalize-release.yml. Rejected because release.yml is a
  language-agnostic reusable workflow called by downstream repos (niwa, koto).
  Adding Go build steps would run those steps in every downstream caller's release
  pipeline, breaking the reusability contract. This also mixes tag orchestration
  concerns with binary publishing concerns in a single workflow.

- **Manual release with documented process**: Require a human to run `go build`
  for each GOOS/GOARCH target and upload binaries manually. Rejected because it
  creates a blocking manual step that can be forgotten, produces no checksums unless
  explicitly scripted, and is inconsistent with shirabe's existing automated release
  infrastructure.

**Consequences**

What changes:
- A `.goreleaser.yaml` is added at the shirabe repo root (once the Go module exists).
- A new `.github/workflows/release-binaries.yml` is added, triggered on tag push.
- finalize-release.yml's `expected-assets` input in prepare-release.yml is set to 5.
- An `install.sh` is added to the shirabe repo following the koto install.sh pattern.
- The tsuku recipe for shirabe can be authored with a stable URL pattern.

What becomes easier:
- Adding a new platform target (e.g., Windows) requires only adding entries to
  `.goreleaser.yaml`; the workflow and checksum generation are unchanged.
- Release process is fully automated: tag push → build → upload → promote.

What becomes harder:
- GoReleaser v2 → v3 migration (historically minor, periodic maintenance).
- Local GoReleaser usage requires `goreleaser` binary (rarely needed; CI handles it).
<!-- decision:end -->
