# Lead: What's the simplest CI workflow that bumps plugin.json + marketplace.json and tags atomically?

## Findings

### Koto's Tag-Triggered Pattern

Koto's release workflow (`.github/workflows/release.yml`) follows a three-stage tag-triggered approach:

1. **Build stage** (multi-platform Rust compilation)
2. **Release stage** (GitHub release creation with artifact upload)
3. **Finalize-release stage** (artifact verification + manifest updates)

The `finalize-release` job is the critical pattern here:
- Checks out `main` branch (not the tag) with a RELEASE_PAT token
- Verifies all expected artifacts exist on the published release
- Updates `.github/workflows/check-template-freshness.yml` to pin `koto-version` default to the new tag
- Commits the change back to `main` using `git add/commit/push`
- Uses `sed` to perform the update, which is fragile for JSON but works for YAML defaults

**Key insight**: Koto separates the release artifacts (immutable, created from tag) from the manifest updates (happen after release succeeds, committed back to main).

### Tsuku's Extended Pattern with Runtime Injection

Tsuku's workflow uses a similar three-stage approach but adds version injection at **build time**:

1. Extracts version from git tag: `VERSION="${GITHUB_REF_NAME#v}"`
2. Uses `sed` to inject version into `Cargo.toml` before compilation
3. Binaries report their version via `--version` flag
4. Integration tests validate binary version matches tag
5. Finalize job verifies artifacts, generates checksums, publishes release

**Key difference**: For binary tools, injecting version into source code works because the built artifact reports version at runtime. This cannot work for JSON manifests in plugins—there's no runtime to report them.

### Niwa's Minimal Pattern

Niwa (simpler Go tool) uses only two stages:
1. GoReleaser (creates release with artifacts)
2. Extract tag notes and update release description

No finalize-release job needed because GoReleaser handles artifact creation atomically.

### Current Shirabe State

- `plugin.json` version: `0.2.0`
- `marketplace.json` version: `0.2.0`
- Latest git tag: `0.1.0`
- **Already drifted**: manifests are ahead of the tag

This drift likely happened because:
- Someone manually bumped versions in manifests during development
- No release was tagged to match
- CI validation doesn't prevent this

### Two Candidate Approaches for Shirabe

#### Approach A: Tag-Triggered Finalize-Release (Koto Pattern Adapted)

**Flow**:
1. `/release` skill pushes annotated tag `v0.3.0`
2. GitHub Actions detects tag push, starts workflow
3. Workflow creates GitHub release
4. `finalize-release` job (depends on release job):
   - Checks out `main` with RELEASE_PAT token
   - Updates `plugin.json` version: `0.2.0` → `0.3.0`
   - Updates `marketplace.json` version: `0.2.0` → `0.3.0`
   - Commits to `main`: `"chore(release): bump versions to v0.3.0"`
   - Push succeeds because RELEASE_PAT has write access

**Race condition vulnerability**:
- Tag `v0.3.0` is visible immediately after `/release` pushes it
- If someone fetches the tag before `finalize-release` commits, they get code with version `0.2.0` at tag `v0.3.0`
- Partial states: tag exists, release created, manifests not yet updated
- Recovery requires: manual tag deletion + re-push, or manual commit + re-tag

**Failure modes**:
- `finalize-release` fails after release created → release exists with wrong manifest versions on main
- Can retry the job, but if manifests are already correct, another commit happens
- Requires idempotency: check if versions already match tag before committing

**Strengths**:
- Matches org's existing `/release` skill (which creates and pushes tag)
- Familiar pattern from koto
- Artifact creation (release) happens before manifest update

---

#### Approach B: Manual Dispatch with Ordered Commits and Tag

**Flow**:
1. User triggers `dispatch-release` workflow with input `version: "0.3.0"`
2. Workflow runs on `main`:
   - Updates `plugin.json` version to `0.3.0`
   - Updates `marketplace.json` version to `0.3.0`
   - Commits to `main`: `"chore(release): bump versions to 0.3.0"`
   - Pushes to `main`
3. Workflow creates annotated tag `v0.3.0` pointing to the commit
4. Workflow creates GitHub release from tag

**Race condition immunity**:
- Tag is created AFTER manifest commits are on `main`
- No partial state: tag always points to commit with matching versions
- If someone fetches tag, they get matching code and manifests

**Failure modes**:
- Workflow fails after commit but before tag → manifests updated, tag missing
  - Recovery: manually create tag (idempotent commit already done)
- Workflow fails after tag created → release not created
  - Recovery: manually publish release (tag already exists)

**Strengths**:
- Truly atomic: tag creation happens after commit succeeds
- Simple workflow: no multi-stage dependencies, sequential steps
- Works well for plugins with no build phase
- Naturally idempotent: commit to the same version twice is safe

**Limitations**:
- Requires different skill than `/release` (which expects to push tag from local commits)
- Version input must come from user, not derived from commits
- User responsible for version numbering decisions (no automatic semver bump)

---

### Sentinel Value Pattern

A third approach worth noting: use a sentinel value in manifests during development.

**Setup**:
- Manifests contain `"version": "0.0.0-dev"` by default
- CI check on PRs: version is either `"0.0.0-dev"` OR matches latest git tag
- At release time: workflow replaces `"0.0.0-dev"` with the new version

**Advantages**:
- Prevents accidental version drift during normal development
- Simple check: no semver logic, just literal string match
- Clearly marks unreleased code

**Disadvantages**:
- Requires git tag to exist for CI to pass (bootstrapping problem)
- Adds complexity to initial setup (must create first release manually or seed tag)
- Neither koto nor tsuku use this pattern—they rely on build-time injection

**Current state incompatibility**: Shirabe manifests already contain real versions (`0.2.0`), not sentinels. Switching would require manual one-time change.

---

### Manifest Update Implementation Details

For JSON files, the update is straightforward:

```bash
# Using jq (preserve formatting, update only version field)
jq '.version = "0.3.0"' plugin.json > plugin.json.tmp && mv plugin.json.tmp plugin.json

# Using sed (fragile, but simpler for CI)
sed -i 's/"version": "[^"]*"/"version": "0.3.0"/' plugin.json
```

For both `plugin.json` and `marketplace.json`, the same version string appears in two places:
1. `.version` at root of `plugin.json`
2. `.plugins[0].version` in `marketplace.json`

A single `sed` or `jq` command can update both in sequence, or a small script can do both atomically.

---

### Token and Permission Considerations

**Default GITHUB_TOKEN**:
- Can create releases (public repos)
- **Cannot** push to protected `main` branch
- Scope: limited to event context (usually read-only for push events)

**RELEASE_PAT (Personal Access Token)**:
- Required for committing to protected main
- Must be configured as a repository secret
- Org must generate and store securely
- Grants full write access to repository

**Implication for Approach A**: `finalize-release` MUST use `token: ${{ secrets.RELEASE_PAT }}` in checkout step. Without it, `git push` fails on protected branch.

**Implication for Approach B**: Similarly required for workflow dispatch approach.

---

### Shirabe Specific Simplifications

Unlike tsuku/koto, shirabe has:
- No binary builds
- No cross-platform compilation
- No integration tests
- No checksum generation
- Just: manifest update → commit → tag → release

This makes shirabe's workflow simpler:

**Approach A simplified**:
```yaml
name: Release
on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - create-release

  finalize-release:
    needs: [release]
    runs-on: ubuntu-latest
    steps:
      - checkout main with RELEASE_PAT
      - update plugin.json and marketplace.json
      - commit
      - push
```

**Approach B simplified**:
```yaml
name: Release (Dispatch)
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version (e.g., 0.3.0)'
        required: true

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - update manifests to inputs.version
      - commit
      - push
      - create tag
      - create-release
```

---

## Implications

1. **For Approach A (tag-triggered)**: Shirabe can adopt koto's pattern with a small adjustment for JSON manifests instead of workflow YAML. Requires RELEASE_PAT secret. Risk of temporary version mismatch (tag exists, manifests not yet updated), mitigated by idempotency check and fast finalize-release execution.

2. **For Approach B (manual dispatch)**: Simpler, more atomic, but requires a different `/release` skill variant. The org's existing `/release` skill (which pushes tag) won't work; need a new skill that takes version input and orchestrates the full workflow.

3. **Sentinel pattern unsuitable**: Too much refactoring needed for a repo already using real versions. Better suited for new projects.

4. **No build phase**: Shirabe's simplicity is an advantage. Either approach is genuinely simple to implement, unlike the multi-stage complexity in koto/tsuku.

5. **Version source decision**: 
   - **Approach A**: Version comes from tag name → must decide version before pushing tag → `/release` skill or user must know next version
   - **Approach B**: Version comes from workflow input → decided at dispatch time → interactive/manual step, more visible

6. **Marketplace caching**: The Claude Code marketplace reads plugin versions at the tagged commit. If tag exists but manifests on main aren't updated yet, a user who clones the tag gets stale version. This is a UX problem, not a correctness problem (marketplace will eventually sync when manifests are updated), but it creates confusion.

---

## Surprises

1. **Koto doesn't use sentinels**: Expected that a build system would use a sentinel pattern (e.g., "0.0.0-dev") to guard against drift, but koto relies on build-time injection and doesn't have a fallback for incomplete releases.

2. **Tsuku sed-injected into Cargo.toml**: Shows that version injection is a validated pattern in the org, but it only works for files that are compiled/executed. JSON manifests can't report their version at runtime, so this pattern doesn't transfer.

3. **Shirabe already drifted**: The fact that manifests (0.2.0) are ahead of the tag (0.1.0) suggests either:
   - Someone prepared a release but never pushed the tag, or
   - Manifests were bumped during development but a release never happened
   - No PR/CI validation catches version drift

4. **Koto's finalize-release is optional**: If it fails, the release still exists. This suggests the pattern is designed to be non-critical, which works for koto (just defaults), but for shirabe (critical version information), a failed finalize-release is unacceptable.

---

## Open Questions

1. **Does the Claude Code marketplace check version at the tag or from main?** 
   - If it reads from the tagged commit, Approach A's race condition is real.
   - If it reads from main's latest version, race condition is benign.
   - **Need to clarify**: how does the marketplace discover and cache plugin versions?

2. **What should `/release` skill do for shirabe?**
   - Continue to push tag (Approach A), or
   - Accept version input and orchestrate full release (Approach B)?
   - Or create a separate dispatch-based skill?

3. **Does the org have RELEASE_PAT configured?**
   - Both approaches need it.
   - Koto's workflow uses it; is it already set up in the organization?

4. **Should shirabe use real versions or sentinel value going forward?**
   - Fix the current drift (0.2.0 vs 0.1.0) first?
   - Then choose pattern for future releases?

5. **Is version bumping part of release workflow or separate?**
   - Approach A implies version decision before tag (in `/release` skill or pre-release prep)
   - Approach B makes version decision explicit (workflow input)
   - Neither automatically bumps semver—should they?

6. **Idempotency for finalize-release**: How should the job detect if versions are already correct and skip commit?
   - Check if `git diff` is empty after updates?
   - Query the release to see what version was intended?

---

## Summary

Koto's tag-triggered finalize-release pattern can be adapted for shirabe by updating JSON manifests instead of workflow YAML, but it carries a race condition vulnerability where the tag exists before manifests are updated on main. Approach B—manual dispatch that commits manifests first, then tags the commit—eliminates the race condition entirely by making the tag creation depend on successful manifest updates, making it genuinely atomic; however, it requires a different skill interface that takes version as explicit input rather than deriving it from the tag name. Shirabe's lack of build complexity makes both approaches straightforward to implement, and the decision should center on whether the org prefers the existing `/release` skill's tag-push-first pattern (accepting the race risk) or wants a new dispatch-based skill with guaranteed atomicity.

