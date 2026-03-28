# Lead: How do koto and tsuku's release workflows handle manifest version injection?

## Findings

### Koto Release Workflow

**File:** `/home/dgazineu/dev/workspace/tsuku/tsuku-5/public/koto/.github/workflows/release.yml`

Koto uses a **post-tag file-update pattern**:

1. **Build & Release Jobs** (lines 12-108): Triggered by `push.tags` matching `v*`, builds binaries and creates a GitHub release.

2. **Finalize-Release Job** (lines 109-166): Runs after release completes on the `main` branch with a `RELEASE_PAT` token.
   - **Key step** (lines 144-165): Updates `.github/workflows/check-template-freshness.yml` using `sed` to pin the `koto-version` default input
   - Line 154 pattern: `sed -i "/koto-version/,/default:/ s/default: '.*'/default: '${TAG}'/"`
   - **Commits back to main** with git config, add, commit, and push
   - **Current pinned version**: `v0.3.3` (as seen in check-template-freshness.yml line 18)

**Key insight:** Koto has NO plugin.json or marketplace.json. It only maintains a workflow input default. The pattern is:
- Tag is pushed manually/externally
- Workflow files are updated programmatically post-tag
- Changes are committed back to main

### Tsuku Release Workflow

**File:** `/home/dgazineu/dev/workspace/tsuku/tsuku-5/public/tsuku/.github/workflows/release.yml`

Tsuku uses **build-time version injection via ldflags**:

1. **GoReleaser Build** (lines 9-26 in `.goreleaser.yaml`):
   - Uses GoReleaser to build Go binaries
   - **ldflags injection** (line 24): `-X github.com/tsukumogami/tsuku/internal/buildinfo.version={{.Version}}`
   - Version comes from git tag (GoReleaser automatically parses `v*` tags)

2. **Rust Binary Injection** (tsuku release.yml lines 99-151):
   - For `tsuku-dltest` and `tsuku-llm` built in Rust: **sed-based version injection into Cargo.toml**
   - Lines 99-106 (build-rust job): `sed -i "s/^version = .*/version = \"$VERSION\"/"`
   - Injects directly into `cmd/tsuku-dltest/Cargo.toml` (version field at top level)
   - **Current version in Cargo.toml**: `0.0.0` (placeholder, always overwritten at build time)

3. **No File Commit**: Tsuku does NOT commit these changes back. The version injection is ephemeral, only in the build environment.

4. **No Manifest Files**: Tsuku has no plugin.json or marketplace.json to maintain.

### Shirabe's Manifest Versions

**Files inspected:**
- `.claude-plugin/plugin.json`: version = `"0.2.0"` (line 4)
- `.claude-plugin/marketplace.json`: version = `"0.2.0"` (line 12)
- Current git tag: `0.1.0`

Both manifests have hardcoded versions that require manual updates.

## Implications

### Pattern 1: Post-Tag Commit (Koto's approach)
**Feasibility for shirabe: HIGH**

Koto's pattern is directly transferable:
1. User pushes a tag (e.g., `v1.0.0`)
2. Release workflow is triggered
3. In `finalize-release` job, use `sed` to update `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` with the tag version
4. Commit changes back to `main` with a bot account token

**Advantages:**
- Git history preserves version changes as commits
- Clear audit trail of when versions were updated
- Simple `sed` implementation proven in koto

**Challenges:**
- Requires a PAT (`RELEASE_PAT`) with write permissions to `main`
- Creates an extra commit after the tag (version history is "dirty" relative to the tag)
- Two-phase: tag first, then auto-update files

### Pattern 2: Build-Time Injection (Tsuku's approach)
**Feasibility for shirabe: LOWER (but possible)**

Tsuku injects versions only into compiled binaries via ldflags. This doesn't apply to plugin.json/marketplace.json directly because:
- JSON files cannot be "built" in the same way
- They must be stored in the repo as-is for plugin discovery
- Tsuku has no manifests to inject into

**Possible adaptation:**
- Could use sed during the release workflow to inject into JSON files before publishing artifacts
- Would require reading the file, modifying it in-place, and committing (similar to Koto but without shipping old versions in git)
- Less clean than Koto's approach because the tag and manifest versions would be temporarily out-of-sync

### Pattern 3: Manual Versioning (Current shirabe state)
**Current reality:** plugin.json and marketplace.json versions must be manually kept in sync with git tags. Shirabe currently does not automate this.

## Surprises

1. **Neither koto nor tsuku have plugin.json files** despite being Claude Code-related projects. Koto is a templating tool (not a Claude Code skill), and tsuku is a CLI tool (not published as a plugin). This is why they don't face the manifest versioning problem.

2. **Koto's finalize-release uses a workflow file as the single source of truth for the version pin**, not any config file. The pattern is elegant: one sed command updates one default, which is then inherited by callers of the reusable workflow.

3. **Tsuku's Rust binaries use placeholder versions (`0.0.0`)** in Cargo.toml that are *always* overwritten at build time. The actual version never lives in the source file; it's computed from the git tag. This is a clean separation of concerns.

4. **Koto commits back to `main` after the tag is already published**, which means the git history shows: tag v0.3.3 → commit updating version default. This is the *opposite* of the usual flow where you update files, commit, then tag.

## Open Questions

1. **Should shirabe adopt the Koto pattern (post-tag commit) or something else?**
   - Post-tag commits are unconventional. Do we want the version commit *after* the tag in git history?
   - Alternative: Update versions before tagging, but this requires manual steps or a two-stage workflow.

2. **Who approves the RELEASE_PAT?**
   - Koto uses `secrets.RELEASE_PAT`. Shirabe would need the same. Is this org-wide or per-repo?

3. **Should plugin.json and marketplace.json be in sync with git tags, or could they have independent versions?**
   - This exploration assumes they should always match. Is that a requirement?

4. **Does the marketplace.json need version bumps, or is it used only for metadata?**
   - The marketplace.json in shirabe has a version field in the plugin object (line 12). Is this enforced by the marketplace, or is it optional?

5. **What's the fallback if the release workflow fails after the tag is pushed but before files are updated?**
   - Tag exists without corresponding version updates in manifests. Recovery process needed.

## Summary

Koto updates workflow files post-tag using sed and commits back to main, while tsuku injects versions only into compiled binaries via ldflags at build time. Neither faces shirabe's problem because they lack manifest files. Koto's post-tag-commit pattern is directly adaptable for plugin.json and marketplace.json but requires a PAT token and creates unconventional git history (tag before manifest updates). Tsuku's approach doesn't apply to JSON manifests. A Koto-like pattern is the most straightforward path forward, but workflow execution order and git history conventions need alignment with team preferences.

