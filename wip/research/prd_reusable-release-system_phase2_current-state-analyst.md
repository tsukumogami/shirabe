# Current-State Analysis: Reusable Release System

## Lead 1: Adoption Path for Existing Repos

### Current Release Workflow Inventory

| Repo | Trigger | Build Tool | Release Creation | Post-Release | Secrets | Has .release/ dir |
|------|---------|------------|------------------|-------------|---------|-------------------|
| tsuku | tag push `v*` | goreleaser (Go) + cargo (Rust) | goreleaser creates draft, finalize job publishes | Integration tests, unified checksums, draft-to-published promotion | GITHUB_TOKEN only | No |
| koto | tag push `v*` | cross (Linux) + cargo (macOS) | `gh release create` (non-draft) | Version pin commit to main via RELEASE_PAT | GITHUB_TOKEN + RELEASE_PAT | No |
| niwa | tag push `v*` | goreleaser | goreleaser creates draft, then notes updated | None | GITHUB_TOKEN only | No |
| shirabe | None (no release workflow) | None (no binaries) | Manual (presumably) | None | N/A | No |

### Per-Repo Adoption: What Changes

#### tsuku (Go + Rust multi-binary)

**New files to create:**
- `.release/set-version.sh` -- stamps `cmd/tsuku-dltest/Cargo.toml` and `tsuku-llm/Cargo.toml` (currently done inline in CI with `sed`)
- `.github/workflows/prepare-release.yml` -- caller workflow that invokes the reusable workflow via `workflow_call`

**Existing files that change:**
- `.github/workflows/release.yml` -- stays as-is (tag-triggered build/test/publish). No changes needed because the prepare-release workflow handles the pre-tag steps and the existing workflow handles everything after the tag push.
- The inline `Inject version` steps in `build-rust`, `build-rust-musl`, and `build-llm` jobs become redundant once `set-version.sh` stamps files before tagging. However, they can remain as a safety net since they're idempotent.

**Secrets:** No new secrets. Uses GITHUB_TOKEN with `contents: write`.

**Permissions:** `contents: write` (already granted).

**Minimum viable adoption:** Add the caller `prepare-release.yml` with `workflow_dispatch`. The existing `release.yml` keeps working unchanged -- it still triggers on tag push. The prepare-release workflow just automates the "stamp version, commit, tag, push tag" steps that are currently manual.

**Delta assessment:** Low friction. tsuku's release.yml is complex (520 lines, 6 jobs) but doesn't need modification. The version injection currently happens per-job in CI; moving it to a pre-tag commit via `set-version.sh` is cleaner but optional -- goreleaser handles Go version via ldflags and the sed injection in Rust jobs still works from the tag.

#### koto (Rust single binary)

**New files to create:**
- `.github/workflows/prepare-release.yml` -- caller workflow

**Existing files that change:**
- `.github/workflows/release.yml` -- no changes needed. Tag-triggered build and release stays the same.
- The `finalize-release` job (version pin commit) becomes a `.release/post-release.sh` hook if desired, but could also stay inline since the reusable workflow's post-release hook is optional.

**Secrets:** Already has `RELEASE_PAT` for the version-pin push to protected main branch. The reusable workflow would need this passed as an explicit secret if `post-release.sh` needs to push.

**Permissions:** `contents: write` (already granted). PAT needed for branch-protected push (already configured).

**Minimum viable adoption:** Add caller `prepare-release.yml`. No `set-version.sh` needed (build.rs reads git tag). Optionally extract the version-pin logic into `.release/post-release.sh`.

**Delta assessment:** Very low friction. koto doesn't need version file stamping at all. The only repo-specific post-release behavior (version pinning) can stay in the existing workflow or move to a hook.

#### niwa (Go single binary)

**New files to create:**
- `.github/workflows/prepare-release.yml` -- caller workflow

**Existing files that change:**
- `.github/workflows/release.yml` -- no changes needed. Identical pattern to tsuku's Go build.

**Secrets:** No new secrets. GITHUB_TOKEN only.

**Permissions:** `contents: write` (already granted).

**Minimum viable adoption:** Add caller `prepare-release.yml`. No hooks needed -- goreleaser handles versioning from the git tag, no post-release steps.

**Delta assessment:** Trivially low friction. niwa is the simplest case -- a single goreleaser job with tag annotation release notes. The prepare-release workflow just automates the manual tag creation.

#### shirabe (Claude Code plugin, no binaries)

**New files to create:**
- `.release/set-version.sh` -- stamps `plugin.json` and `marketplace.json` (currently version is `0.2.0-dev`, needs to be set to release version)
- `.release/post-release.sh` -- (optional) bumps version back to next dev sentinel after release
- `.github/workflows/release.yml` -- doesn't exist today. Needs both a prepare-release caller AND a release workflow (or the reusable workflow handles everything since there's no build step).
- `.github/workflows/prepare-release.yml` -- caller workflow

**Existing files that change:**
- `.claude-plugin/plugin.json` -- version field gets stamped by `set-version.sh` (currently `0.2.0-dev`)
- `.claude-plugin/marketplace.json` -- nested version field gets stamped (currently `0.2.0-dev`)

**Secrets:** GITHUB_TOKEN for release creation. Possibly a PAT if main is branch-protected.

**Permissions:** `contents: write`.

**Minimum viable adoption:** This is the most involved adoption because shirabe has NO release workflow today. It needs the full stack: caller workflow, set-version hook, and the reusable workflow handles tag + GitHub Release creation. The absence of a build step actually simplifies things -- the reusable workflow can create the release directly.

**Delta assessment:** Medium friction. Requires creating the most new files (3-4) but each is small. The version stamping in JSON files is straightforward with `jq`. shirabe is also the publishing repo for the reusable workflow itself, creating a bootstrapping question (see requirements below).

### Minimum Viable Adoption Summary

For all repos, the minimum adoption is:
1. Create `.github/workflows/prepare-release.yml` (3-10 lines of YAML calling the reusable workflow)
2. Optionally create `.release/set-version.sh` if the repo has version files to stamp
3. Optionally create `.release/post-release.sh` if repo-specific cleanup is needed
4. Keep existing `release.yml` unchanged

No existing workflows need modification. No secrets need changing (except possibly adding RELEASE_PAT for repos with branch protection that don't already have it).

---

## Lead 2: Release Skill Boundaries

### What the Skill Does (Local, Interactive)

The release skill runs locally in the developer's terminal via Claude Code. Its responsibilities:

1. **Version selection** -- Prompts for or validates the target version. Could suggest the next version based on the current dev sentinel (e.g., `0.3.1-dev` suggests `0.3.1`).

2. **Pre-flight checklist** -- Verifies preconditions before triggering the release:
   - Working tree is clean
   - On the expected branch (main/release branch)
   - No open blockers (queries GitHub issues/milestones)
   - CI is green on HEAD
   - Version string is valid semver

3. **Release notes drafting** -- Creates or updates a draft GitHub Release with curated notes. The developer reviews and edits the notes before proceeding.

4. **Dispatch** -- Triggers the `prepare-release` workflow via `gh workflow run` with the version input, or by creating/pushing an annotated tag (depending on the handoff mechanism chosen).

5. **Monitoring** -- Optionally watches the CI run and reports success/failure.

### What the Workflow Does (CI, Automated)

The reusable workflow runs in GitHub Actions. Its responsibilities:

1. **Version stamping** -- Runs `.release/set-version.sh` if it exists. Commits the changes.
2. **Tagging** -- Creates annotated tag `v{version}` and pushes it.
3. **Release creation/promotion** -- Either creates a GitHub Release or promotes an existing draft to published.
4. **Dev version bump** -- If a dev sentinel pattern is used, runs `.release/set-version.sh` with the next dev version (e.g., `0.3.2-dev`) and commits.
5. **Post-release hooks** -- Runs `.release/post-release.sh` if it exists.

### Handoff Mechanism Options

**Option A: workflow_dispatch with version input**
- Skill calls `gh workflow run prepare-release.yml -f version=1.2.3`
- Workflow receives version as an input, does everything
- Draft release can be pre-created by the skill; workflow promotes it
- Supports manual dispatch from GitHub UI (no skill needed)

**Option B: Draft release as the data channel**
- Skill creates a draft release with the target tag name and notes
- Workflow is triggered by `release: types: [created]` or by workflow_dispatch
- Workflow reads the draft's tag name to determine version
- More complex, couples the workflow to GitHub Release API state

**Option C: Annotated tag push**
- Skill creates and pushes the annotated tag directly
- Existing release workflows already trigger on tag push
- Simplest for repos that don't need pre-tag version stamping
- Breaks for shirabe (needs version files stamped before tag)

**Recommended: Option A (workflow_dispatch)**

Option A is the cleanest separation. The skill dispatches, the workflow executes. The draft release is a communication channel for release notes (skill creates draft, workflow promotes it) but not the trigger mechanism. workflow_dispatch also supports manual use from the GitHub UI.

### Can the Workflow Be Used WITHOUT the Skill?

Yes, and this is a hard requirement. The workflow must be independently usable via:

1. **GitHub UI** -- Navigate to Actions > Prepare Release > Run workflow, enter version
2. **CLI** -- `gh workflow run prepare-release.yml -f version=1.2.3`
3. **Other automation** -- Any system that can call the GitHub API's workflow dispatch endpoint

The skill adds convenience (checklist, notes drafting, monitoring) but the workflow is the source of truth for the release process. A repo owner who doesn't use Claude Code must still be able to release.

### Can the Skill Be Used WITHOUT the Workflow?

Partially. The skill's value breaks down as:

| Capability | Needs workflow? | Standalone value |
|------------|----------------|-----------------|
| Pre-flight checklist | No | Yes -- useful for any repo |
| Release notes drafting | No | Yes -- creates draft GH release |
| Version validation | No | Yes -- local check |
| Workflow dispatch | Yes | N/A without workflow |
| CI monitoring | Yes | N/A without workflow |

A repo could use the skill for just the checklist and notes portions, then trigger their own release process. The skill should degrade gracefully when no reusable workflow is configured.

### Interface Contract Between Skill and Workflow

```
Skill -> Workflow:
  Trigger: workflow_dispatch
  Inputs:
    version: string (required, semver without v prefix, e.g. "1.2.3")
    dry-run: boolean (optional, default false)
  Pre-conditions:
    - Draft GitHub Release with tag "v{version}" may exist (with notes)
    - If draft exists, workflow promotes it; if not, workflow creates one

Workflow -> Skill (observable outcomes):
  - Workflow run status (success/failure) visible via gh run watch
  - GitHub Release transitions from draft to published
  - Tag "v{version}" exists on the version-stamped commit
  - If dev sentinel: version files show next dev version on main
```

---

## Requirements the PRD Must Specify

Based on the current-state analysis, these items need explicit specification in the PRD:

### 1. Bootstrapping: shirabe releases itself

The reusable workflow lives in shirabe. How does shirabe release itself using its own workflow? This is a self-referential dependency. The caller workflow in shirabe would reference `tsukumogami/shirabe/.github/workflows/prepare-release.yml@v1` -- but the first release needs to exist before callers can reference a tag. The PRD must specify the bootstrapping sequence.

### 2. Tag-triggered vs dispatch-triggered release.yml coexistence

Current release workflows trigger on `push: tags: ["v*"]`. The new prepare-release workflow creates and pushes tags. This means: prepare-release pushes a tag, which triggers the existing release.yml. The two workflows must not conflict. The PRD should state that existing release.yml workflows remain tag-triggered and the prepare-release workflow is dispatch-triggered, with the tag push being the handoff point.

### 3. Version file stamping commit and tag ordering

For repos with version files (tsuku, shirabe), the sequence is: stamp files -> commit -> tag the commit -> push tag. The tagged commit must contain the stamped version. The PRD should specify this ordering explicitly, since the current tsuku workflow stamps version inline during build (after tag) rather than before.

### 4. Dev sentinel bump scope

After releasing 1.2.3, does the workflow bump to 1.2.4-dev or 1.3.0-dev? The scope document says "rolling dev sentinel" but doesn't specify how the next dev version is computed. Options: always bump patch, let the developer specify, or use a `.release/config.json` setting.

### 5. Branch protection compatibility

koto already uses a RELEASE_PAT for pushing to protected main. The PRD should specify the authentication model: default to GITHUB_TOKEN, accept an optional PAT secret for repos with branch protection, document the required token permissions.

### 6. Release notes: who writes them, when?

The current repos extract release notes from annotated tag messages. The proposed system has the skill create a draft release with notes. The PRD should specify: does the developer write notes in the skill (before dispatch), edit them on the draft release in GitHub UI, or both? What happens if no draft exists when the workflow runs?

### 7. Workflow-only adoption (no skill) must be first-class

The out-of-scope section says "migrating existing release.yml" is out of scope, but the adoption path shows that repos only need to ADD a prepare-release caller. The PRD should explicitly state that the workflow is usable without the skill, via GitHub UI or CLI, and define what the experience looks like.

### 8. Idempotency and re-run behavior

If a prepare-release run fails mid-way (e.g., after committing but before tagging), what happens on re-run? The PRD should specify whether the workflow is idempotent and how it handles partial state.

### 9. Per-repo build/publish is explicitly out of scope for the reusable workflow

The existing release workflows have wildly different build matrices (tsuku: 6 jobs, koto: 4-target matrix, niwa: single goreleaser, shirabe: nothing). The PRD should explicitly state that the reusable workflow handles only the prepare-release dance (stamp, commit, tag) and the post-release hooks, not build or artifact publishing. Each repo's existing release.yml remains responsible for builds.

### 10. shirabe's dual role as publisher and consumer

shirabe publishes the reusable workflow AND consumes it for its own releases. The PRD should specify how versioning works for the workflow itself (major tag pattern @v1) and whether shirabe's own release uses the workflow at a pinned SHA or at HEAD.
