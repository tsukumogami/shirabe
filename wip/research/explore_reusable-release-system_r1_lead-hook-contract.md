# Hook Contract Research: Reusable Release System

## Per-Repo Inventory

### tsuku (Go + Rust multi-binary)

**Version files:**
- Go: no file; version injected via ldflags at build time (`-X .../buildinfo.version={{.Version}}`)
- Rust (tsuku-dltest): `cmd/tsuku-dltest/Cargo.toml` version field (sed-replaced in CI)
- Rust (tsuku-llm): `tsuku-llm/Cargo.toml` version field (sed-replaced in CI)

**Build steps:**
- Go: goreleaser (`release --clean`) handles cross-compilation, produces draft release
- Rust: native cargo build per-platform + musl variants in Alpine containers
- Rust (llm): feature-flagged builds (metal/cuda/vulkan) with GPU SDK dependencies

**Artifacts:** 4 Go binaries, 4+2 dltest binaries (glibc+musl), 6 llm binaries, checksums.txt

**Post-release:** Integration tests download binaries and validate version strings, then finalize (verify artifacts, generate unified checksums, publish draft).

**Version injection summary:** goreleaser handles Go automatically from the git tag. Rust needs explicit `sed` on Cargo.toml before `cargo build`.

---

### koto (Rust single binary)

**Version files:**
- `Cargo.toml` has a version field (`0.2.1`) but it's NOT used at runtime
- `build.rs` derives version from `git describe --tags` at compile time

**Build steps:**
- Cross-compilation via `cross` (Linux) and native `cargo build` (macOS)
- No version file mutation needed -- `build.rs` reads the git tag directly

**Artifacts:** 4 binaries (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64), checksums.txt

**Post-release:** Finalize step pins the new version as default in `check-template-freshness.yml` and pushes that commit to main.

**Version injection summary:** None needed. The git tag is the source of truth via build.rs.

---

### niwa (Go single binary)

**Version files:**
- Go: no file; version injected via goreleaser ldflags (`-X .../buildinfo.version={{.Version}}`)

**Build steps:**
- goreleaser (`release --clean`), identical pattern to tsuku's Go build
- Single job, no matrix complexity

**Artifacts:** 4 Go binaries, checksums.txt

**Post-release:** Tag annotation extracted as release notes.

**Version injection summary:** goreleaser handles everything from the git tag. No file mutation.

---

### shirabe (JSON manifests, no binaries)

**Version files:**
- `.claude-plugin/plugin.json` -- `"version": "0.2.0-dev"`
- `.claude-plugin/marketplace.json` -- nested `"version": "0.2.0-dev"` in plugins array

**Build steps:** None.

**Artifacts:** None (the release is just a git tag + GitHub Release entry).

**Post-release:** None currently.

**Version injection summary:** Both JSON files need version field updated. Could use `jq` or `sed`.

---

## Analysis: What Varies Across Repos

| Concern | tsuku | koto | niwa | shirabe |
|---------|-------|------|------|---------|
| Files to stamp | 2 Cargo.toml | none | none | 2 JSON |
| Build tool | goreleaser + cargo | cross + cargo | goreleaser | none |
| Artifact upload | multi-job matrix | multi-job matrix | single job | none |
| Post-release | integration tests, finalize | version pin commit | none | none |
| Version source | git tag | git tag (build.rs) | git tag | file-embedded |

The key insight: **version stamping** is the only truly universal concern. Build and publish are so different across repos that a single `build.sh` hook would either be trivially thin (delegating to goreleaser/cargo/cross) or fight against the existing tooling.

## Proposed Hook Contract

### Design Principles

1. **Convention over configuration.** Hooks live at `.release/` in the repo root.
2. **Optional hooks.** If a script doesn't exist, the workflow skips that phase.
3. **Minimal interface.** Each hook receives version as an argument. Environment provides context.
4. **Idempotent.** Running a hook twice with the same version produces the same result.

### Hook Scripts

| Hook | Path | When Called | Required? |
|------|------|------------|-----------|
| **set-version** | `.release/set-version.sh` | Before commit/tag, during prepare-release | If version is embedded in files |
| **post-release** | `.release/post-release.sh` | After GitHub Release is published | If cleanup/pinning needed |

That's it. Two hooks. Here's why:

**Why no `build.sh`:** Build logic is deeply coupled to CI matrix strategies, runner selection, GPU SDK installation, goreleaser config, and cross-compilation tooling. Abstracting it behind a single script gains nothing -- the workflow already needs to define the matrix. The reusable workflow should call goreleaser/cargo directly based on a declarative config, not shell out to a build script.

**Why no `publish.sh`:** Publishing means "upload artifacts to GitHub Release" and that's already handled by `gh release upload` / goreleaser in the workflow itself. There's no repo-specific logic here.

**Why `post-release` exists:** koto needs to pin its version in a reusable workflow file after release. This is genuinely repo-specific logic that doesn't fit in the standard flow.

### Hook Interface

#### `.release/set-version.sh`

```
Usage: .release/set-version.sh <version>

Arguments:
  version   Semver without 'v' prefix (e.g., "1.2.3")

Environment:
  REPO_ROOT   Absolute path to repository root (always set by caller)

Exit codes:
  0   Success (files modified in-place, ready for git add)
  1   Failure (abort release)

Contract:
  - Modifies version-bearing files in-place
  - Does NOT commit or tag
  - Caller handles staging and committing
  - Must be idempotent
```

**Per-repo implementations:**

- **tsuku:** `sed` on `cmd/tsuku-dltest/Cargo.toml` and `tsuku-llm/Cargo.toml`
- **koto:** No file needed (build.rs reads git tag). Hook doesn't exist, workflow skips.
- **niwa:** No file needed (goreleaser reads git tag). Hook doesn't exist, workflow skips.
- **shirabe:** `jq` to update `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`

#### `.release/post-release.sh`

```
Usage: .release/post-release.sh <version> <tag>

Arguments:
  version   Semver without 'v' prefix (e.g., "1.2.3")
  tag       Full tag string (e.g., "v1.2.3")

Environment:
  REPO_ROOT      Absolute path to repository root
  GITHUB_TOKEN   Token with push access (for commits to main)

Exit codes:
  0   Success
  1   Failure (non-fatal -- release is already published)

Contract:
  - Runs after the GitHub Release is published
  - May commit and push to main (e.g., version pinning)
  - Failures are logged but don't roll back the release
```

**Per-repo implementations:**

- **tsuku:** No hook needed currently. Skipped.
- **koto:** Pins version default in `check-template-freshness.yml`, commits, pushes.
- **niwa:** No hook needed. Skipped.
- **shirabe:** No hook needed. Skipped.

### Workflow Integration

The reusable `prepare-release` workflow would look like:

```
1. workflow_dispatch with version input
2. Checkout repo
3. If .release/set-version.sh exists:
     run it with the version
     git add -A && git commit -m "chore(release): set version $VERSION"
4. Create annotated tag v$VERSION
5. Push tag (triggers existing release.yml)
6. [release.yml runs: build, test, publish -- unchanged per repo]
7. On release published event, if .release/post-release.sh exists:
     run it with version and tag
```

This means existing `release.yml` workflows don't change at all. The new `prepare-release.yml` wraps the front (version stamping + tagging) and back (post-release hooks) around the existing flow.

### Declarative Metadata (Optional Enhancement)

A `.release/config.json` could declare capabilities without needing hook scripts:

```json
{
  "version_files": [
    { "path": ".claude-plugin/plugin.json", "type": "json", "field": "version" },
    { "path": ".claude-plugin/marketplace.json", "type": "json", "field": "plugins[0].version" }
  ]
}
```

For simple cases like shirabe (JSON field updates) and tsuku's Cargo.toml (TOML field updates), the workflow could handle version stamping directly from config without a shell script. The `set-version.sh` hook would then only be needed for truly custom logic.

This is a "nice to have" that could replace most `set-version.sh` implementations. If adopted, the hook becomes the escape hatch for cases the declarative config can't handle.

### Opting Out

Repos opt out by simply not providing the hook script. The workflow checks `[ -f .release/set-version.sh ]` before calling it. No configuration needed to say "I don't have a set-version step."

## Summary

The minimal contract is **two optional scripts** in `.release/`:
- `set-version.sh <version>` -- stamp version into files before tagging
- `post-release.sh <version> <tag>` -- repo-specific cleanup after publish

Build and publish stay in each repo's existing `release.yml` since they're too varied (goreleaser vs cross vs cargo vs nothing) to usefully abstract. The reusable workflow orchestrates the prepare-release dance around the existing per-repo release triggers.
