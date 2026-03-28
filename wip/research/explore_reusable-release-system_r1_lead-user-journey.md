# Lead: User Journey Analysis for Release System

## Research Question

What do repo owners and consumers actually need from the release experience?
Before deciding mechanics, understand the user journey: what a repo owner does
today vs what they should do, what a consumer sees, and how update detection
works across repo types.

---

## 1. Repo Owner Journey Today

### tsuku (Go + Rust monorepo)

**Trigger**: Manual. Someone decides a release is warranted and creates an
annotated git tag (`v*`).

**Steps**:
1. Write release notes as an annotated tag message.
2. Push the tag to origin.
3. Tag push triggers `.github/workflows/release.yml`.
4. GoReleaser builds Go binaries for linux/darwin x amd64/arm64, creates a
   **draft** GitHub release.
5. The workflow extracts the tag annotation and overwrites the release body
   with it (`gh release edit`).
6. Parallel jobs build Rust binaries (tsuku-dltest for glibc + musl, tsuku-llm
   for metal/cuda/vulkan) across native runners.
7. Integration tests download the draft release binaries and validate version
   strings and basic execution.
8. A `finalize-release` job verifies all 16+ expected artifacts are present,
   generates a unified `checksums.txt`, uploads it, and promotes the draft to
   published (`gh release edit --draft=false`).

**Version source of truth**: `go.mod` (Go version), `Cargo.toml` (Rust
version). GoReleaser injects version via ldflags at build time. Rust versions
are injected via `sed` on Cargo.toml during the workflow. No version file is
maintained manually.

**Pain points**:
- The release workflow is ~520 lines covering Go, Rust glibc, Rust musl, and
  LLM addon builds with GPU backends. It's monorepo-specific and not reusable.
- Release notes live in the tag annotation, which is write-once. Editing after
  push requires `gh release edit`.
- No `/prepare-release` checklist -- the owner must remember what to validate.
- No automated changelog or diff summary -- the owner writes notes from memory
  or by reading `git log`.

### koto (Rust CLI)

**Trigger**: Manual annotated tag push (`v*`).

**Steps**:
1. Write release notes as an annotated tag message.
2. Push the tag.
3. Tag push triggers `.github/workflows/release.yml`.
4. Four parallel `build` jobs use `cross` (Linux) or native `cargo` (macOS) to
   compile for linux/darwin x amd64/arm64. Binaries uploaded as GitHub Actions
   artifacts.
5. A `release` job downloads all artifacts, generates `checksums.txt`, extracts
   tag annotation as release notes, and creates a **published** GitHub release
   (not draft).
6. A `finalize-release` job (needs `RELEASE_PAT`) checks out main, pins the
   `koto-version` default in the reusable `check-template-freshness.yml`
   workflow to the new tag, commits, and pushes.

**Version source of truth**: `Cargo.toml` (`version = "0.2.1"`). The Cargo
version is the source; the git tag must match. Version is compiled into the
binary via Cargo's built-in `env!("CARGO_PKG_VERSION")` or via ldflags if
using the Go wrapper pattern. Actually koto uses `.goreleaser.yaml` -- it's
actually built with GoReleaser despite being described as Rust. Checking
`Cargo.toml` and `.goreleaser.yaml`: koto has both. The release workflow
uses `cross`/`cargo` (Rust build), not GoReleaser. The `.goreleaser.yaml`
references `./cmd/koto` which is a Go path, but the actual workflow builds
Rust. This is a discrepancy worth noting.

**Correction**: Reviewing more carefully -- koto's release.yml builds with
`cross`/`cargo` (Rust). The `.goreleaser.yaml` is present but the release
workflow doesn't use it. The goreleaser config references `./cmd/koto` and
Go ldflags with `buildinfo.version` and `buildinfo.commit`, suggesting koto
may have had or still has a Go wrapper. The actual release pipeline is pure
Rust.

**Pain points**:
- The `finalize-release` step that pins `koto-version` in the reusable
  workflow is koto-specific coupling. If someone forgets to update RELEASE_PAT,
  this silently fails.
- `Cargo.toml` version and git tag can drift. Nothing validates they match.
- Release is published immediately (not draft-then-publish), so there's no
  integration test gate before consumers can download.

### niwa (Go CLI)

**Trigger**: Manual annotated tag push (`v*`).

**Steps**:
1. Write release notes as an annotated tag message.
2. Push the tag.
3. Tag push triggers `.github/workflows/release.yml`.
4. Single job: Go build via GoReleaser, extracts tag annotation, updates
   release notes with `gh release edit`.

**Version source of truth**: GoReleaser ldflags inject version from the tag
into `buildinfo.version`. No version file to maintain.

**Pain points**:
- Simplest workflow of the four, but still no pre-release checklist.
- No checksums generated (GoReleaser generates its own `checksums.txt` but
  the workflow doesn't reference it explicitly).
- No finalize step -- the GoReleaser release config says `draft: true`, so
  the release is created as draft and then `gh release edit` updates notes,
  but nothing promotes it from draft. **This may be a bug**: the workflow
  updates release notes but never sets `--draft=false`. GoReleaser creates
  a draft release, and the note-update step doesn't change the draft status.

### shirabe (Claude Code plugin -- no binaries)

**Trigger**: No release workflow exists yet. Version `0.2.0-dev` is in the
manifests. Only tag is `v0.1.0`.

**Current state**:
- `.claude-plugin/plugin.json` declares version `0.2.0-dev`.
- `.claude-plugin/marketplace.json` mirrors it.
- `scripts/check-sentinel.sh` validates the `-dev` suffix on PRs.
- `.github/workflows/check-sentinel.yml` runs the script on PRs touching
  `.claude-plugin/**`.
- DESIGN-release-process.md describes the full intended flow but issues
  #32 (release workflow), #33 (skill hook), and #34 (first release) are
  still open. Only #31 (sentinel bootstrap) is done.

**What's designed but not built**:
- `/release` skill updates manifests to release version, commits, tags, pushes.
- Tag-triggered `release.yml` creates GH release from tag annotation.
- `finalize-release` job advances manifests to next `-dev` on main.

**Pain points**:
- No release process at all yet -- the plugin can't be properly released.
- Manual version management is the only option until the workflow is built.
- The design exists but implementation is blocked on two open issues.

---

## 2. Repo Owner Journey (Desired)

### Deciding to release

The owner should be able to see what changed since the last release without
manual `git log` archaeology. A command or script should:
- List commits since the last tag.
- Group by conventional commit type (feat, fix, docs, chore).
- Flag breaking changes if any.
- Show which issues were closed.

### Reviewing what changed

The owner should review a generated draft of release notes, edit it to taste,
and approve. The draft should be good enough to ship as-is for routine releases
but editable for releases that need narrative context.

### Triggering the release

The owner should run a single command that:
1. Validates preconditions (CI green on main, no uncommitted changes, version
   doesn't already exist as a tag).
2. Stamps version files if the repo has them (manifests, Cargo.toml, etc.).
3. Commits the version stamp.
4. Creates an annotated tag with the release notes.
5. Pushes the commit and tag.

The owner should NOT need to:
- Manually edit version files.
- Remember which files need updating.
- Know the internal release workflow mechanics.

### Monitoring

After push, the owner should see CI status without leaving the terminal. The
current `/ci` skill pattern (poll `gh run list`) works, but the release
workflow should surface clear pass/fail for each phase: build, test, publish.

### Communicating to consumers

For binary repos (tsuku, koto, niwa): the GitHub release page IS the
communication. Release notes should be clear about what changed and any
required user action (breaking changes, migration steps).

For plugin repos (shirabe): the marketplace handles discovery, but there's
no mechanism to communicate "what's new" to existing users. The GitHub
release page serves as the changelog, but plugin consumers may never visit it.

---

## 3. Consumer Journey

### tsuku consumers

**Discovery**: Users find tsuku via the website (tsuku.dev) or GitHub.

**Installation**: `curl | sh` install script or downloading a binary from
the GitHub release page.

**Update detection**: tsuku has a built-in `tsuku outdated` command that
checks installed tools against their version providers (GitHub releases, PyPI,
npm, etc.). For tsuku itself, there's no self-update mechanism. The user must
re-download or re-run the install script. There's no `tsuku update tsuku`
equivalent -- `tsuku update <tool>` updates tools tsuku manages, but tsuku
doesn't manage itself.

**What triggers an update**: The user manually runs `tsuku outdated` or
`tsuku update <tool>`. There are no push notifications or background checks.

**What they see**: The `tsuku outdated` command shows a table of tools with
current and available versions. `tsuku update` re-installs to the latest.

### koto consumers

**Discovery**: Users find koto via shirabe skills that reference it, or
directly via GitHub.

**Installation**: `install.sh` script that:
- Detects OS and architecture.
- Fetches the latest release tag from GitHub API.
- Downloads the platform-specific binary and checksums.
- Verifies the SHA256 checksum.
- Installs to `~/.koto/bin/koto`.
- Configures shell PATH.

The script supports `--version=<tag>` for pinned installs.

**Update detection**: None built-in. The user re-runs `install.sh` and gets
the latest. If they have a pinned version, they must manually change the pin.

Koto's reusable workflow (`check-template-freshness.yml`) has a `koto-version`
input that defaults to the latest release. The `finalize-release` job pins
this after each release. So repos using the reusable workflow automatically
get the latest koto version on their next CI run -- this is a form of
automated consumer update for CI consumers, not end-user consumers.

**What they see**: Nothing proactive. They only discover updates if they
re-run the installer, check GitHub releases, or their CI workflow picks up
the new default.

### niwa consumers

**Discovery**: GitHub.

**Installation**: `install.sh` script, nearly identical to koto's. Downloads
from GitHub releases, verifies checksums, installs to `~/.niwa/bin/niwa`.

**Update detection**: None. Same re-run-installer pattern as koto.

### shirabe consumers

**Discovery**: Claude Code marketplace (planned) or GitHub.

**Installation**: Claude Code's plugin system. The marketplace resolves the
plugin by reading `.claude-plugin/marketplace.json` from the repository.
Users install with something like `claude plugin add shirabe` (exact UX
depends on Claude Code's marketplace implementation).

**Update detection**: Claude Code reads `plugin.json` at the installed ref.
When a new release tag has a different version in `plugin.json`, Claude Code
detects it as an update. This is why the sentinel pattern (`<version>-dev`)
exists -- it ensures every release changes the version field.

**What they see**: Presumably a notification or prompt within Claude Code
that an update is available. The exact UX is controlled by Claude Code's
marketplace, not by shirabe.

**Key difference**: Shirabe is the only repo where the version file IS the
update detection mechanism. For binary repos, the GitHub release tag is
sufficient. For shirabe, the version in `plugin.json` must change for updates
to be detected.

---

## 4. Pain Points

### Cross-cutting

1. **No pre-release validation**: None of the repos have a formalized
   checklist before release. The owner pushes a tag and hopes CI is green.

2. **Release notes are manual**: The owner writes tag annotations from
   scratch. There's no generated draft, no commit grouping, no issue linking.

3. **No update notification for consumers**: Binary CLI consumers (tsuku,
   koto, niwa) have no mechanism to learn about updates unless they actively
   check. No "a new version is available" message.

4. **Version file inconsistency**: tsuku has no version file (ldflags only).
   koto has `Cargo.toml`. niwa has no version file (ldflags only). shirabe
   has two JSON manifests. A reusable release system must handle all of these.

5. **Draft vs published inconsistency**: tsuku uses draft-then-publish with
   integration tests. koto publishes immediately. niwa creates a draft but
   may never publish it (possible bug). shirabe has no workflow yet.

6. **Finalize-release divergence**: tsuku's finalize verifies artifacts and
   publishes. koto's finalize pins a version in a reusable workflow. niwa
   has no finalize. shirabe's design calls for advancing a dev sentinel.
   Each repo's post-release step is different.

### Repo-specific

- **tsuku**: Massive release workflow (520+ lines) with repo-specific build
  matrix. Not abstractable into a reusable workflow without significant
  redesign.

- **koto**: `.goreleaser.yaml` exists but the release workflow doesn't use
  GoReleaser. Potential confusion for contributors.

- **niwa**: Release may be stuck in draft state after the workflow runs.
  Needs verification.

- **shirabe**: No release process at all. Design exists but implementation
  is partially done.

---

## 5. Cross-Cutting Concerns

### Version discovery

**Binary repos**: GitHub Releases API. The `install.sh` scripts query
`/repos/{owner}/{repo}/releases/latest` and parse `tag_name`. This is
the universal pattern across the ecosystem.

**Plugin repos**: The marketplace reads `plugin.json` at a git ref. The
version field must change between releases for update detection.

**Implication for reusable system**: The release workflow must produce a
GitHub release with a tag that matches the version. For plugin repos, it
must also ensure the manifest version matches the tag at the tagged commit.

### Breaking change communication

No repo has a formal mechanism for communicating breaking changes. Release
notes are free-form text. There's no structured "breaking changes" section,
no migration guide template, no semver enforcement.

A reusable system should at minimum:
- Flag commits with `feat!:` or `BREAKING CHANGE:` trailer.
- Include a dedicated "Breaking Changes" section in generated release notes.
- For major version bumps, require explicit confirmation.

### Rollback

**Binary repos**: Consumers re-run the install script with `--version=<old>`.
No built-in rollback command.

**Plugin repos**: Claude Code presumably allows pinning a version or reverting.
Not clear from the current codebase.

**tsuku-managed tools**: `tsuku install <tool>@<version>` allows pinning.
But there's no `tsuku rollback <tool>` that reverts to the previous version.

**Implication**: Rollback is manual across the board. A reusable release
system doesn't need to solve consumer-side rollback, but it should make it
easy for repo owners to yank a bad release (mark as pre-release, delete
assets, etc.).

### Pre-release and beta versions

GoReleaser configs across all repos include `prerelease: auto`, which means
tags like `v1.0.0-rc1` or `v1.0.0-beta.1` are automatically marked as
pre-releases on GitHub. This is correct behavior.

koto's `install.sh` uses `/releases/latest` which skips pre-releases by
GitHub API convention. Consumers on the default path won't accidentally get
a pre-release.

Shirabe's sentinel uses `-dev` suffix. A pre-release would need a different
suffix (e.g., `0.3.0-rc.1`). The sentinel check (`check-sentinel.sh`)
currently only accepts `-dev` -- it would reject `-rc.1` or `-beta.1`.
This needs consideration if shirabe ever wants pre-releases.

### What a reusable system should provide

Based on this analysis, the minimal reusable surface is:

1. **A release skill** that handles: pre-release checklist, release notes
   generation, version stamping (delegated to repo-local hooks), tag
   creation, and push.

2. **A reusable GitHub Actions workflow** with two jobs:
   - `release`: Create GH release from tag annotation.
   - `finalize-release`: Run repo-local post-release hook (bump dev version,
     pin downstream versions, etc.).

3. **A hook contract** with two scripts:
   - `set-version.sh <version>`: Stamp version files. No-op for repos
     without version files.
   - `post-release.sh <version>`: Post-release actions. No-op default.

4. **Build is out of scope** for the reusable workflow. tsuku's 520-line
   build matrix and koto's cross-compilation are too repo-specific to
   abstract. The reusable workflow handles release creation and finalization;
   build artifacts are uploaded by repo-specific workflows or jobs.

---

## Summary

The four repos share a common release pattern (annotated tag triggers CI,
GH release created from tag annotation) but diverge in every detail: build
complexity, version file management, draft/publish behavior, and post-release
steps. Consumers have no proactive update detection except shirabe (where
the marketplace reads plugin.json). The biggest owner pain points are lack
of pre-release validation, manual release notes, and inconsistent
draft-vs-published behavior. The reusable system should standardize the
tag-to-release flow and hook contract while leaving build and post-release
steps to repo-local scripts.
