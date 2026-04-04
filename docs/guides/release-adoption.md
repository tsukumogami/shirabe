# Adopting the Reusable Release Workflows

How to set up the shirabe release system in your repo. Covers the workflow
files, hook scripts, GitHub configuration, and branch protection setup.

## Prerequisites

- A GitHub repository in an organization (bypass lists don't work on
  personal repos)
- The `/release` skill installed (comes with shirabe)
- `gh` CLI authenticated with release creation permissions

## Quick Start (No Branch Protection)

If your repo doesn't have branch protection on main, the setup is minimal.

### 1. Create the caller workflow

`.github/workflows/prepare-release.yml`:

```yaml
name: Prepare Release
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      tag: { required: true, type: string }
      ref: { required: true, type: string, default: main }

jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v0.2.1
    with:
      version: ${{ inputs.version }}
      tag: ${{ inputs.tag }}
      ref: ${{ inputs.ref }}

  finalize:
    needs: release
    uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v0.2.1
    with:
      tag: ${{ inputs.tag }}
```

This is the pattern for repos without builds (like shirabe itself). The
release and finalize jobs run sequentially in one workflow.

### 2. Add hooks (optional)

If your repo has version files that need stamping, create
`.release/set-version.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?Usage: set-version.sh <version>}"

# Update your version files here. Examples:
# jq --arg v "$VERSION" '.version = $v' package.json > tmp && mv tmp package.json
# sed -i "s/^version = .*/version = \"$VERSION\"/" Cargo.toml
```

Make it executable: `chmod +x .release/set-version.sh`

The script is called twice per release: once with the release version
(e.g., `0.3.0`) and once with the next dev version (e.g., `0.3.1-dev`).
The version never includes a `v` prefix.

### 3. Release

```
/release
```

The skill recommends a version from commit history, generates notes,
creates a draft, and dispatches the workflow.

## Repos with Builds

If your repo has a build pipeline (goreleaser, cargo, etc.) triggered by
tag pushes, the setup is slightly different. The finalize step runs after
builds complete instead of immediately after the release workflow.

### 1. Caller workflow (dispatch only, no finalize)

`.github/workflows/prepare-release.yml`:

```yaml
name: Prepare Release
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      tag: { required: true, type: string }
      ref: { required: true, type: string, default: main }

jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v0.2.1
    with:
      version: ${{ inputs.version }}
      tag: ${{ inputs.tag }}
      ref: ${{ inputs.ref }}
    secrets:
      token: ${{ secrets.RELEASE_PAT }}
```

### 2. Finalize bridge workflow

`.github/workflows/finalize.yml`:

```yaml
name: Finalize Release
on:
  workflow_run:
    workflows: ["Release"]  # name of your existing build workflow
    types: [completed]

jobs:
  extract-tag:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.tag.outputs.tag }}
    steps:
      - id: tag
        run: echo "tag=${{ github.event.workflow_run.head_branch }}" >> "$GITHUB_OUTPUT"

  finalize:
    needs: extract-tag
    uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v0.2.1
    with:
      tag: ${{ needs.extract-tag.outputs.tag }}
      expected-assets: 4  # adjust to your expected artifact count
    secrets:
      token: ${{ secrets.RELEASE_PAT }}
```

Change the `workflows:` value to match the `name:` of your existing
tag-triggered build workflow. Adjust `expected-assets` to the number of
release artifacts your build produces (set to 0 to skip verification).

### 3. Existing build workflow

No changes needed. Your existing tag-triggered workflow keeps working --
the tag push from the reusable release workflow triggers it as before.
Make sure it creates a **draft** release (e.g., goreleaser `draft: true`)
so the finalize workflow can promote it.

## Branch Protection Setup

The release workflow pushes commits directly to main (version stamp + dev
bump). Branch protection blocks this by default. You need to allow the
release token to bypass protection rules.

GitHub has two branch protection systems. Check which one your repo uses:
- **Settings > Branches > Branch protection rules** -- legacy system
- **Settings > Rules > Rulesets** -- newer system

### Option A: Fine-Grained PAT (Simpler)

Best for small teams where one person manages releases.

#### 1. Create the PAT

Go to **Settings > Developer settings > Fine-grained personal access tokens**.

| Setting | Value |
|---------|-------|
| Repository access | Only select repositories > pick your repo |
| Contents | Read and write |
| Metadata | Read (required, auto-selected) |

Set an expiration date. Save the token.

#### 2. Add the repo secret

Go to your repo's **Settings > Secrets and variables > Actions > New
repository secret**.

| Name | Value |
|------|-------|
| `RELEASE_PAT` | The token you created |

#### 3. Configure bypass

**Legacy branch protection rules:**

1. Go to **Settings > Branches > Branch protection rules**
2. Edit the rule for `main`
3. Check **"Allow specified actors to bypass required pull requests"**
4. Add the user account that owns the PAT
5. Save

**Repository rulesets:**

1. Go to **Settings > Rules > Rulesets**
2. Edit the ruleset that covers `main`
3. Click **"Add bypass"**
4. Select the user account that owns the PAT
5. Save

#### 4. Tag protection

While you're in branch protection settings, also configure tag protection:

**Legacy:** Go to **Settings > Tags > Tag protection rules** and add `v*`.

**Rulesets:** Create a ruleset targeting tags matching `v*` with "Restrict
creations" and "Restrict deletions" rules. Add the PAT user to the bypass
list.

### Option B: GitHub App (More Secure)

Better for teams, orgs, or repos where you want a clear audit trail and
don't want tokens tied to a person.

#### 1. Create the GitHub App

Go to your org's **Settings > Developer settings > GitHub Apps > New
GitHub App**.

| Setting | Value |
|---------|-------|
| Name | `release-bot` (or similar) |
| Homepage URL | Your repo URL |
| Permissions > Contents | Read and write |
| Where can this app be installed? | Only on this account |

Generate a private key and save it.

#### 2. Install the app

Go to the app's settings > **Install App** > select your repo.

#### 3. Add secrets

Add two secrets to your repo:

| Name | Value |
|------|-------|
| `APP_ID` | The app's ID (visible on the app's settings page) |
| `APP_PRIVATE_KEY` | The private key you generated |

#### 4. Update the caller workflow

Use `actions/create-github-app-token` to generate a token:

```yaml
jobs:
  get-token:
    runs-on: ubuntu-latest
    outputs:
      token: ${{ steps.token.outputs.token }}
    steps:
      - uses: actions/create-github-app-token@v1
        id: token
        with:
          app-id: ${{ secrets.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

  release:
    needs: get-token
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v0.2.1
    with:
      version: ${{ inputs.version }}
      tag: ${{ inputs.tag }}
      ref: ${{ inputs.ref }}
    secrets:
      token: ${{ needs.get-token.outputs.token }}
```

#### 5. Configure bypass

Same as Option A, but add the GitHub App (not a user) to the bypass list.
GitHub Apps appear in the bypass actor search by their name.

## Hook Contract

| Script | Required | Arguments | Purpose |
|--------|----------|-----------|---------|
| `.release/set-version.sh` | No | `<version>` | Update version files |
| `.release/post-release.sh` | No | `<version>` | Post-promotion cleanup |

Both receive the version without the `v` prefix as `$1`. Exit 0 on
success, non-zero on failure. If the script doesn't exist, the workflow
skips it.

`set-version.sh` is called twice: once with the release version
(`0.3.0`), once with the next dev version (`0.3.1-dev`). Your script
must handle both.

`post-release.sh` runs after the draft is promoted to published. Use it
for repo-specific cleanup (e.g., updating version pins in other files).

### Dev sentinel suffix

The default dev suffix is `-dev`. To use a different convention (e.g.,
`-SNAPSHOT`), pass `dev-suffix` to the release workflow:

```yaml
uses: tsukumogami/shirabe/.github/workflows/release.yml@v0.2.1
with:
  version: ${{ inputs.version }}
  tag: ${{ inputs.tag }}
  ref: ${{ inputs.ref }}
  dev-suffix: '-SNAPSHOT'
```

## Pinning Strategy

The workflow examples above use `@v0.2.1` (exact tag). Options:

| Ref | Trade-off |
|-----|-----------|
| `@v0.2.1` | Stable. Update manually when new versions ship. |
| `@main` | Always latest. Convenient during development, risky in production. |
| `@<sha>` | Maximum security. Immune to tag overwrites. |

For production repos, pin to an exact tag and update after reviewing the
shirabe release notes.

## Dry-Run

Test the setup without pushing anything:

```bash
gh workflow run prepare-release.yml \
  -f version=0.99.0 \
  -f tag=v0.99.0 \
  -f ref=main \
  -f dry-run=true
```

The workflow runs all steps (version stamp, commit, tag, dev bump) but
skips push and draft promotion. Check the workflow logs to verify
everything works.

## Troubleshooting

**"Token does not have push permission"**: The RELEASE_PAT is missing or
doesn't have `Contents: write`. Check the repo secret exists and the
token hasn't expired.

**"No draft release found"**: The `/release` skill creates the draft
before dispatching the workflow. If you're dispatching manually from the
GitHub UI, create the draft first:
`gh release create v0.3.0 --draft --title "v0.3.0" --notes "Release notes here"`

**Push to main rejected by branch protection**: The PAT user (or GitHub
App) isn't in the bypass list. See the branch protection setup section.

**Finalize bridge never triggers**: Check that the `workflows:` value in
`finalize.yml` matches the exact `name:` of your build workflow. The
`workflow_run` trigger matches by name, not filename.

**Tag already exists**: A previous attempt left a tag. Delete it:
`git push --delete origin v0.3.0`
