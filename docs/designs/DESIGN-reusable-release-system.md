---
status: Accepted
upstream: docs/prds/PRD-reusable-release-system.md
problem: |
  Four repos with different toolchains (Go+Rust, Rust, Go, JSON manifests) each
  implement their own release workflow, duplicating the prepare-release dance and
  causing version drift bugs. CI must own the commit-tag-push sequence while
  delegating repo-specific concerns to convention-based hooks.
decision: |
  Two reusable GitHub Actions workflows (release + finalize) published from shirabe,
  driven by a local /release skill. The release workflow performs the Maven-style
  prepare-release dance via workflow_dispatch. A companion finalize workflow promotes
  the draft release after builds complete. Repos customize via .release/ hook scripts.
rationale: |
  Splitting release from finalize lets the tag push trigger existing build workflows
  unchanged while deferring promotion until builds succeed. Convention-based hooks
  keep the reusable workflows generic. A configurable token input supports both
  protected and unprotected repos without imposing PAT setup on everyone.
---

# DESIGN: Reusable Release System

## Status

Accepted

## Context and Problem Statement

The tsukumogami ecosystem has four public repos with different build toolchains
(Go+Rust, Rust, Go, JSON manifests) that each implement their own release workflow.
The technical challenge is building a single release pipeline that handles the
Maven-style prepare-release dance -- version stamp, commit, tag, dev bump, commit,
push -- while delegating repo-specific concerns (which files contain versions, how
binaries are built) to convention-based hooks.

Three architectural constraints shape the design:

1. **The tag must point to a commit with correct version files.** The Claude Code
   marketplace reads plugin.json at the tagged commit. Go and Rust repos inject
   version at build time from the tag, but repos with static version files need
   them stamped before the tag is created.

2. **CI must own the commit-tag-push sequence.** The release skill runs locally and
   can't reliably push to branch-protected main. A workflow_dispatch workflow runs
   with appropriate permissions and performs all git mutations server-side.

3. **Existing build workflows must keep working.** Tsuku's 520-line release.yml,
   koto's cross-compilation pipeline, and niwa's goreleaser workflow are all
   tag-triggered. The new system's tag push must trigger these unchanged.

## Decision Drivers

- **Version correctness by construction**: The tag must always point to a commit with
  matching version files. No window where the tag exists with wrong versions.
- **Ecosystem diversity**: Go (ldflags), Rust (Cargo.toml), JSON manifests (plugin.json),
  and no-version repos must all work with the same workflow.
- **Adoption friction**: A new repo should adopt the system by adding one workflow file
  and optionally one hook script. No reusable workflow changes needed.
- **Failure recoverability**: Every failure point must have a documented recovery path
  that doesn't require git surgery.
- **Existing workflow compatibility**: Tag push from the reusable workflow must trigger
  existing tag-triggered build/release workflows without modification.
- **Independent operation**: The workflow must be usable from the GitHub UI without the
  skill. The skill must be usable without the workflow.
- **Hook contract stability**: The hook interface is a public API. Changes are breaking.

## Considered Options

### Decision 1: Build workflow coordination and draft promotion

The reusable workflow pushes a tag that triggers existing build workflows (10-30 min
for tsuku/koto). The draft release should only be promoted after those builds succeed.
But the reusable workflow finishes before builds start.

Five approaches were evaluated: promote-immediately with override flag, never-promote
with separate finalize, wait-and-poll for builds, output-based caller chaining, and a
companion finalize workflow with workflow_run coordination.

Key assumptions:
- All repos adopt draft-then-promote (koto and niwa need changes regardless).
- `workflow_run` is an acceptable trigger for cross-workflow coordination.

#### Chosen: Companion reusable finalize workflow

The system ships two reusable workflows:

1. **`release.yml`** -- performs the version dance through tag push. Outputs the tag
   name and release URL. Never promotes the draft.
2. **`finalize-release.yml`** -- accepts a tag name, optionally verifies artifact
   count, promotes the draft to published.

Repos wire these up based on their needs:

- **Repos without builds (shirabe):** Caller workflow calls `release.yml` then
  `finalize-release.yml` as sequential jobs. One workflow file, two jobs, immediate
  promotion.
- **Repos with builds (tsuku, koto, niwa):** Existing tag-triggered build workflow
  runs as usual. A thin `on: workflow_run` workflow triggers when the build completes
  and calls `finalize-release.yml`. The finalize workflow verifies artifacts before
  promoting.

This extracts the finalize-release pattern that already exists in tsuku and koto
into a reusable component.

#### Alternatives Considered

**Promote-immediately with per-repo override**: Single reusable workflow with a
`skip_promotion` flag. Rejected because a boolean controlling whether a release goes
public is the wrong abstraction -- getting the flag wrong means premature promotion
(missing binaries) or orphaned drafts.

**Wait-and-poll for build completion**: Reusable workflow polls for build workflow
completion. Rejected for fundamental reliability issues -- race conditions on run
matching, wasted compute, fragile timeouts, and API rate limits.

**Output-based caller chaining**: Reusable workflow outputs tag/URL, callers handle
promotion. Rejected because every repo would reimplement the same promotion logic,
defeating reusability.

### Decision 2: Authentication model

The workflow pushes commits to main and creates tags. Branch protection may require
more than GITHUB_TOKEN.

Key assumptions:
- All repos will eventually adopt branch protection. The configurable approach works
  whether they do or not.
- GitHub App tokens aren't worth the setup cost for four repos.

#### Chosen: Configurable token secret with GITHUB_TOKEN default

The reusable workflow defines an optional secret named `token`. When provided, it's
used for checkout and push. When omitted, falls back to `github.token`. The expression
`${{ secrets.token || github.token }}` handles both cases.

Caller without branch protection:
```yaml
uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
# No secrets needed
```

Caller with branch protection:
```yaml
uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
secrets:
  token: ${{ secrets.RELEASE_PAT }}
```

Early validation (PRD R7) runs an API permissions check with the effective token
before any git mutations.

#### Alternatives Considered

**GITHUB_TOKEN only**: Zero friction but fails for protected repos with no upgrade
path. Rejected.

**PAT required**: Always works but penalizes unprotected repos with unnecessary setup.
Rejected.

**GitHub App token**: Best security properties but disproportionate setup cost for
four repos. Rejected.

### Decision 3: Release skill interface

The skill runs locally and orchestrates the human side. Key tensions: `gh workflow
run` doesn't return a run ID (correlation is hard), build-heavy repos take 20+ min
(blocking the terminal is impractical), and the skill must work without a workflow.

Key assumptions:
- Simple repo workflows complete within 5 minutes.
- The reusable workflow is discoverable by scanning `.github/workflows/` for the
  shirabe reference.

#### Chosen: Dispatch-then-monitor with graceful degradation

**Invocation**: `/release [version]`. If version omitted, analyzes conventional
commits and recommends patch/minor/major. User confirms or overrides.

**Precondition checks**: Clean working tree, CI green on HEAD, no existing tag, no
existing draft release.

**Note generation**: Gathers commits and PRs since last release, synthesizes notes,
presents for review. Creates draft via `gh release create --draft`.

**Workflow dispatch**: 3 inputs only -- `version`, `tag`, `ref`. The draft already
holds the notes.

**Monitoring**: Polls every 10s for 5 minutes with timestamp-based run correlation.
On success: verifies draft promoted, prints release URL. On failure: prints details
and suggests `gh run view --log-failed`. On timeout (still running): prints URL and
exits gracefully.

**Skill-only mode**: If no release workflow found, creates draft and prints manual
tag instructions. Still useful for note generation.

**Dry-run**: `--dry-run` flag runs all phases except draft creation and dispatch.
Prints what would happen.

#### Alternatives Considered

**Fire-and-forget dispatch**: Dispatch and print URL without monitoring. Rejected
because forcing users to open a browser for every release breaks the single-command
promise.

**Full-lifecycle watch**: Block until workflow completes via `gh run watch`. Rejected
because it blocks the terminal for 20+ minutes on build-heavy repos.

## Decision Outcome

**Chosen: Two reusable workflows + dispatch-then-monitor skill + configurable auth**

### Summary

The release system has three layers. The `/release` skill handles everything the
human touches: version recommendation from commit analysis, precondition validation,
release note generation and review, draft release creation, and workflow dispatch with
monitoring. It passes three inputs to the workflow -- version, tag, and ref -- keeping
the interface minimal since the draft release already holds the notes.

The `release.yml` reusable workflow runs server-side and owns all git mutations. It
checks out the caller's repo, validates the push token, calls `.release/set-version.sh`
with the release version, commits, creates an annotated tag, calls set-version.sh again
with the next dev version (patch+1 plus the configured dev suffix), commits, and pushes
branch then tag. It never promotes the draft -- that's the finalize workflow's job.

The `finalize-release.yml` reusable workflow handles promotion. For repos without
builds, it runs as a sequential job after the release workflow in the same caller
workflow file. For repos with builds, a thin `on: workflow_run` bridge workflow
triggers it after the build completes. It optionally verifies artifact count before
running `gh release edit --draft=false`.

Authentication uses a configurable `token` secret that defaults to `GITHUB_TOKEN`.
Repos with branch protection pass a PAT; repos without don't need to configure
anything.

### Rationale

Splitting release from finalize is the key architectural choice. It lets the tag push
trigger existing build workflows unchanged -- tsuku's goreleaser, koto's cross-compilation,
niwa's goreleaser all fire on `v*` tags and don't know the reusable system exists. The
finalize workflow then waits for those builds via `workflow_run` before promoting. This
means zero changes to existing build pipelines during adoption.

The three-input skill interface (version, tag, ref) works because the draft release is
the data channel for notes. No escaping issues, no input size limits, and the draft
survives workflow failures for retry.

## Solution Architecture

### Overview

```
User runs /release [version]
  |
  +-> Skill: recommend version, check preconditions, draft notes
  |     |
  |     +-> gh release create --draft (notes live here)
  |     +-> gh workflow run release.yml -f version -f tag -f ref
  |     +-> Poll for 5 min, then print URL
  |
  +-> CI: release.yml (reusable, workflow_dispatch)
  |     |
  |     +-> Validate token, check tag doesn't exist
  |     +-> .release/set-version.sh <release-version>
  |     +-> git commit "set version to v<version>"
  |     +-> git tag -a v<version>
  |     +-> .release/set-version.sh <next-dev-version>
  |     +-> git commit "advance to <next-dev>"
  |     +-> git push origin main v<version>
  |
  +-> CI: existing build workflow (tag-triggered, unchanged)
  |     |
  |     +-> Build binaries, upload to draft release
  |
  +-> CI: finalize-release.yml (reusable, via workflow_run or sequential job)
        |
        +-> Verify artifacts (optional)
        +-> gh release edit --draft=false
```

### Components

**1. /release skill** (lives in shirabe's skills/)

A Claude Code skill replacing /release and /prepare-release. Phases:
1. Version recommendation from conventional commit analysis
2. Precondition validation (clean tree, CI green, no existing tag/draft)
3. Release note generation and user review
4. Draft release creation via `gh release create --draft`
5. Workflow dispatch with 3 inputs (version, tag, ref)
6. Monitoring with 5-min polling and graceful timeout

Detects the release workflow by scanning `.github/workflows/` for shirabe
reference. Falls back to skill-only mode (draft + manual instructions) if
no workflow found.

**2. release.yml** (reusable workflow in shirabe's .github/workflows/)

Trigger: `workflow_call` (callers invoke it) + `workflow_dispatch` (manual from UI).

Inputs:
- `version` (required): Semver without `v` prefix, e.g., `0.3.0`
- `tag` (required): Git tag with `v` prefix, e.g., `v0.3.0`
- `ref` (required, default: `main`): Branch to release from
- `dry-run` (optional, default: `false`): Skip push and promotion
- `dev-suffix` (optional, default: `-dev`): Suffix for dev version

Secrets:
- `token` (optional): Push token. Falls back to `github.token`.

Outputs:
- `tag`: The created tag name
- `release-url`: URL of the draft release

Steps: validate token → validate no existing tag → validate draft release
exists for tag → checkout ref → call set-version.sh with release version
(if exists) → commit → tag → call set-version.sh with next dev version
(if exists) → commit → push branch → push tag.

**3. finalize-release.yml** (reusable workflow in shirabe's .github/workflows/)

Trigger: `workflow_call`.

Inputs:
- `tag` (required): Tag to finalize
- `expected-assets` (optional, default: `0`): If > 0, verify this many
  assets exist before promoting

Secrets:
- `token` (optional): Same pattern as release.yml.

Steps: validate tag format (`^v[0-9]+\.[0-9]+\.[0-9]+$`) → verify draft
exists for tag → verify asset count (if configured) → `gh release edit
<tag> --draft=false` → call `.release/post-release.sh <version>` (if exists).

**4. .release/ hook contract** (in each caller repo)

Convention-based scripts:

| Script | Required | Called with | Purpose |
|--------|----------|------------|---------|
| `.release/set-version.sh` | No | `<version>` (no v prefix) | Update repo-specific version files |
| `.release/post-release.sh` | No | `<version>` (no v prefix) | Post-promotion cleanup |

Both receive version as $1. Exit 0 = success, non-zero = abort. The workflow
skips missing hooks. set-version.sh must handle both release versions (`0.3.0`)
and dev versions (`0.3.1-dev`).

**5. Caller workflow patterns** (in each adopting repo)

Simple repo (no builds):
```yaml
name: Release
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      tag: { required: true, type: string }
      ref: { required: true, type: string, default: main }

jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
    with:
      version: ${{ inputs.version }}
      tag: ${{ inputs.tag }}
      ref: ${{ inputs.ref }}

  finalize:
    needs: release
    uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v1
    with:
      tag: ${{ inputs.tag }}
```

Build repo (with existing tag-triggered workflow):
```yaml
# prepare-release.yml — dispatched by skill
name: Prepare Release
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      tag: { required: true, type: string }
      ref: { required: true, type: string, default: main }

jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
    with:
      version: ${{ inputs.version }}
      tag: ${{ inputs.tag }}
      ref: ${{ inputs.ref }}
    secrets:
      token: ${{ secrets.RELEASE_PAT }}
```

```yaml
# finalize.yml — triggered after build completes
name: Finalize Release
on:
  workflow_run:
    workflows: ["Release"]  # existing build workflow name
    types: [completed]

jobs:
  extract-tag:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.tag.outputs.tag }}
    steps:
      - id: tag
        run: |
          # The build workflow triggers on tag push — extract tag from the run's head_branch
          # For tag-triggered workflows, head_branch contains the tag name
          echo "tag=${{ github.event.workflow_run.head_branch }}" >> "$GITHUB_OUTPUT"

  finalize:
    needs: extract-tag
    uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v1
    with:
      tag: ${{ needs.extract-tag.outputs.tag }}
    secrets:
      token: ${{ secrets.RELEASE_PAT }}
```

**6. check-sentinel.yml** (CI workflow, per repo)

Already implemented in shirabe (#31). Validates version files carry the dev
sentinel suffix on PRs. The suffix is configurable via `.release/` config
or workflow input (default: `-dev`).

### Key Interfaces

**Skill → Workflow**: `gh workflow run <file> -f version=X -f tag=vX -f ref=main`

**Skill → GitHub**: `gh release create vX --draft --title "vX" --notes-file <path>`

**Workflow → Hooks**: `.release/set-version.sh <version>` (called twice per release)

**Workflow → Finalize**: Outputs `tag` and `release-url` for chaining.

**Finalize → GitHub**: `gh release edit <tag> --draft=false`

**Finalize → Hooks**: `.release/post-release.sh <version>` (called once after promotion)

### Data Flow

```
Normal development:
  main has <version>-dev in version files
  PRs validated by check-sentinel.yml

Release:
  Skill: /release 0.3.0
    → recommends version from commit analysis
    → checks preconditions
    → generates notes, user reviews
    → gh release create v0.3.0 --draft
    → gh workflow run prepare-release.yml -f version=0.3.0 -f tag=v0.3.0 -f ref=main
    → polls for 5 min

  release.yml:
    → .release/set-version.sh 0.3.0
    → commit "chore(release): set version to v0.3.0"
    → tag v0.3.0
    → .release/set-version.sh 0.3.1-dev
    → commit "chore(release): advance to 0.3.1-dev"
    → push main, push v0.3.0

  (repos with builds): existing release.yml triggers on v0.3.0 tag
    → build binaries, upload to draft release

  finalize-release.yml (after builds or immediately):
    → verify artifacts
    → gh release edit v0.3.0 --draft=false
    → .release/post-release.sh 0.3.0 (if exists)
```

## Implementation Approach

### Phase 1: Reusable workflows

Create both reusable workflows in shirabe.

Deliverables:
- `.github/workflows/release.yml` (workflow_call + workflow_dispatch)
- `.github/workflows/finalize-release.yml` (workflow_call)
- Dry-run mode for both
- Documentation in README

### Phase 2: Shirabe adoption

Adopt the workflows in shirabe itself (bootstrapping).

Deliverables:
- Caller workflow in shirabe wiring release → finalize as sequential jobs
- `.release/set-version.sh` for plugin.json and marketplace.json
- Verify end-to-end with a dry-run, then cut a real release

### Phase 3: Release skill

Create the /release skill in shirabe.

Deliverables:
- Skill with version recommendation, precondition checks, note generation,
  draft creation, workflow dispatch, and monitoring
- Skill-only mode for repos without the workflow
- Dry-run mode

### Phase 4: Ecosystem migration

Adopt the system in tsuku, koto, and niwa.

Deliverables:
- Per-repo caller workflows and hook scripts
- Finalize bridge workflows for repos with builds
- Verify each repo's existing build workflow still triggers correctly

## Security Considerations

**Token scope**: The configurable `token` secret defaults to `GITHUB_TOKEN`
(contents:write scope in the caller's repo). Repos requiring branch protection
bypass pass a fine-grained PAT scoped to the specific repo with contents:write
only. The workflow validates token permissions before any mutations.

**No force-push**: The workflow uses fast-forward-only pushes. If a concurrent push
to main causes a conflict, the workflow fails rather than force-pushing. Recovery
is manual rebase.

**Hook script trust**: `.release/set-version.sh` and `.release/post-release.sh`
run in the caller's CI environment with the caller's permissions. The reusable
workflow doesn't inject code into the caller -- the caller's own repo provides the
hooks. This is the same trust model as any CI script.

**Tag protection**: Repos should configure GitHub tag protection rules for `v*` tags
to prevent unauthorized tag creation or deletion. The workflow creates tags as part
of its normal operation; the token must have permission to do so.

**Draft release as data channel**: Release notes travel via a draft GH release, not
through workflow inputs. This avoids shell injection risks from markdown content
flowing through workflow dispatch parameters.

**Action dependency pinning**: The reusable workflows must SHA-pin all action
dependencies (e.g., `actions/checkout@<sha>` not `actions/checkout@v4`). A
compromise of a third-party action would otherwise cascade to all repos calling
the reusable workflow. SHA pinning is more important here than in normal
workflows because the reusable workflow receives push tokens.

**Shirabe tag protection**: Tag protection rules for `v*` must be configured on
the shirabe repo itself, not just on caller repos. Since shirabe publishes the
reusable workflows and callers pin to `@v1`, an attacker who can overwrite
shirabe's `v1` tag can inject malicious workflow code into all callers.

**Draft-existence validation**: The release workflow validates that a draft release
exists for the requested tag before starting mutations. This prevents the workflow
from proceeding if dispatched manually without the skill's draft creation step,
which would result in a tag with no release notes.

## Consequences

### Positive
- Version drift eliminated by construction -- the tag always points to a commit with
  correct version files
- Existing build workflows keep working unchanged -- they trigger on the tag push
- Single release experience across all repo types via the /release skill
- Failed releases are recoverable -- draft survives failures, re-dispatch is safe
- New repos adopt by adding one workflow file and optionally one hook script

### Negative
- Two reusable workflows instead of one adds complexity to the mental model
- Repos with builds need a `workflow_run` bridge workflow (thin but another file)
- The `workflow_run` trigger only works from the default branch, so finalize workflow
  changes can only be fully tested after merge
- The skill's 5-minute monitoring timeout means build-heavy repos get a URL instead
  of a completion confirmation

### Mitigations
- Clear caller workflow templates for both simple and build repos reduce the two-workflow
  complexity to copy-paste adoption
- The `workflow_run` bridge is ~10 lines of YAML per repo
- The finalize workflow is thin and changes rarely, so the default-branch limitation
  is acceptable in practice
- The skill prints the monitoring URL at timeout, and the draft release persists as
  a visible artifact showing the release is in progress
