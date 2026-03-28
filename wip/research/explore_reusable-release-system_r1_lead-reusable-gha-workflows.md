# Reusable GitHub Actions Workflows: Mechanics and Constraints

Research lead for the reusable release system exploration. Covers how
reusable workflows work, what they can and can't do, and how callers
customize them -- with specific attention to the release-workflow use case.

## 1. Defining a Reusable Workflow (`workflow_call`)

A reusable workflow is a standard GitHub Actions workflow file that uses
`workflow_call` as its trigger instead of (or in addition to) `push`,
`pull_request`, etc.

```yaml
# .github/workflows/release.yml in shirabe repo
name: Reusable Release

on:
  workflow_call:
    inputs:
      version:
        description: "Version to release (e.g. 1.2.3)"
        required: true
        type: string
      dry-run:
        description: "If true, skip push and release creation"
        required: false
        type: boolean
        default: false
    secrets:
      RELEASE_TOKEN:
        description: "Token with push + release permissions"
        required: false
    outputs:
      tag:
        description: "The git tag that was created"
        value: ${{ jobs.release.outputs.tag }}
```

The file must live in `.github/workflows/` in the publishing repo. It can
coexist with other triggers on the same file (e.g., `workflow_dispatch`
for testing), though that's uncommon for release workflows.

### Nesting Limit

Reusable workflows can call other reusable workflows, but only to a depth
of 4. A caller workflow counts as level 1, so the called workflow can nest
up to 3 more levels deep. This is unlikely to matter for a release
workflow.

### Concurrency

A reusable workflow runs in the context of the *caller* workflow. This
means concurrency groups set inside the reusable workflow are evaluated
against the caller repo. This is actually what we want -- if two PRs try
to release simultaneously, the concurrency group prevents conflicts.

## 2. Input Types and Limits

`workflow_call` inputs support three types:

| Type | Notes |
|------|-------|
| `string` | Default type. Max ~65,535 chars per input. |
| `boolean` | `true`/`false` only. |
| `number` | Integer or float. JSON number semantics. |

There is no `choice` type for `workflow_call` inputs (unlike
`workflow_dispatch`). If the caller passes an invalid value, there's no
built-in validation -- the reusable workflow must validate it in a step.

**Limit on number of inputs**: GitHub allows up to 10 inputs per
`workflow_call` trigger. This is a hard limit. If the release workflow
needs more than 10 customization knobs, some must be packed into a single
JSON string input and parsed inside the workflow.

**Limit on number of outputs**: Up to 10 outputs per reusable workflow.

**Limit on number of secrets**: Up to 10 explicit secrets (though
`secrets: inherit` bypasses this by passing all of them).

## 3. Secret Passing

Two mechanisms:

### Explicit Secrets

```yaml
# Caller
jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
    secrets:
      RELEASE_TOKEN: ${{ secrets.MY_PAT }}
```

The reusable workflow must declare each secret it accepts. Up to 10.

### `secrets: inherit`

```yaml
# Caller
jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
    secrets: inherit
```

This passes *all* secrets available to the caller workflow into the
reusable workflow. The reusable workflow doesn't need to declare them --
it can reference `${{ secrets.ANYTHING }}` and it will resolve if the
caller has that secret.

**Trade-off**: `secrets: inherit` is simpler for callers but means the
reusable workflow has access to every secret the caller has, which
violates least-privilege. For a release workflow that only needs a push
token, explicit secrets are cleaner. However, if the release workflow
needs to call other tools (npm publish, cargo publish, etc.), inherit
avoids the 10-secret limit.

**Cannot mix**: You must use either explicit secrets or `secrets: inherit`,
not both.

### GITHUB_TOKEN

The `GITHUB_TOKEN` is automatically available in the reusable workflow
without being passed as a secret. Its permissions are determined by the
caller's `permissions` block (see section 7).

## 4. Checking Out and Pushing to the Caller's Repo

Yes, a reusable workflow can check out the caller's repo and push to it.

When a reusable workflow runs, the `github` context reflects the *caller*
repo. So `actions/checkout@v4` with no arguments checks out the caller's
repo, not shirabe.

```yaml
# Inside the reusable workflow
steps:
  - uses: actions/checkout@v4
    # This checks out the CALLER's repo at the ref that triggered the workflow

  - name: Push version bump
    run: |
      git add version.txt
      git commit -m "release: bump to ${{ inputs.version }}"
      git push
```

For `git push` to work, the checkout must use a token with push
permissions. By default, `actions/checkout` uses `GITHUB_TOKEN`, which
works if the caller grants `contents: write` permission.

**Branch protection caveat**: If the caller's default branch has branch
protection rules (required reviews, status checks), pushing directly will
fail even with `contents: write`. Options:
- Use a PAT with admin/bypass permissions
- Push to a temporary branch and create a PR
- Use a GitHub App token with bypass permissions
- Exempt the GitHub Actions bot from branch protection rules

## 5. Creating Tags and Releases in the Caller's Repo

Yes. Since the `github` context points to the caller's repo, both
operations target the right place.

### Tags

```yaml
- name: Create tag
  run: |
    git tag "v${{ inputs.version }}"
    git push origin "v${{ inputs.version }}"
```

Requires `contents: write` on the `GITHUB_TOKEN`.

### GitHub Releases

```yaml
- name: Create GitHub Release
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    gh release create "v${{ inputs.version }}" \
      --title "v${{ inputs.version }}" \
      --generate-notes
```

Or use `softprops/action-gh-release` or `ncipollo/release-action`. The
`gh` CLI approach keeps dependencies minimal.

Requires `contents: write` permission on the token.

## 6. Calling Repo-Local Scripts

Yes. After `actions/checkout`, the caller's repo is on disk. The reusable
workflow can run any script in it:

```yaml
- uses: actions/checkout@v4

- name: Stamp version
  run: scripts/set-version.sh "${{ inputs.version }}"
```

This is important for our design. Each calling repo can define its own
`scripts/set-version.sh` with repo-specific logic (Go: edit
`version.go`; Node: edit `package.json`; Rust: edit `Cargo.toml`). The
reusable workflow just calls the script at a conventional path.

**Gotcha**: The script must be executable (`chmod +x`) in the repo, or
the step must call it via `bash scripts/set-version.sh`.

## 7. Permission Constraints

### GITHUB_TOKEN Scope

The `GITHUB_TOKEN` in a reusable workflow inherits its permissions from
the caller workflow's `permissions` block. The reusable workflow *cannot*
escalate permissions beyond what the caller grants.

```yaml
# Caller must grant these
permissions:
  contents: write   # For push, tag, release
```

If the caller doesn't set `permissions`, the defaults depend on the
repo's settings (Settings > Actions > General > Workflow permissions).
The default for public repos is read-only. So callers should explicitly
set permissions.

The reusable workflow can declare `permissions` too, but GitHub uses the
*intersection* (most restrictive) of caller and callee permissions. In
practice, the reusable workflow should document required permissions and
let callers set them.

### PAT Requirements

For repos with branch protection on the default branch, `GITHUB_TOKEN`
alone is insufficient for direct pushes. A PAT or GitHub App token with
higher privileges is needed. The reusable workflow would accept this as
an explicit secret.

### Fork Restrictions

Reusable workflows from public repos can be called by any repo. Reusable
workflows from private repos can only be called by repos in the same
organization (and only if the repo's Actions settings allow it).

Since shirabe is public, any repo (including external users) can call its
reusable workflows.

## 8. How Callers Customize Behavior

### Inputs

The primary mechanism. Example caller:

```yaml
name: Release
on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version to release"
        required: true

jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
    with:
      version: ${{ inputs.version }}
      dry-run: false
    secrets:
      RELEASE_TOKEN: ${{ secrets.RELEASE_PAT }}
    permissions:
      contents: write
```

### Environment Variables

Callers cannot pass environment variables directly to the reusable
workflow. Environment variables must be passed as inputs, or the reusable
workflow must read them from the `github` context.

However, the reusable workflow can reference `vars` context (repo/org/env
variables) -- these resolve from the *caller's* repo settings, not
shirabe's. So if the caller sets a repository variable
`RELEASE_BRANCH=main`, the reusable workflow sees it via `${{ vars.RELEASE_BRANCH }}`.

### Matrix Strategy

Callers *cannot* use matrix strategy when calling a reusable workflow.
The `uses` key in a job definition is mutually exclusive with `strategy`.
If the release workflow needed to run across multiple configurations,
that matrix would need to be inside the reusable workflow itself (driven
by inputs).

### `with` Limitations

All `with` values for a reusable workflow call are strings (or booleans/
numbers matching declared input types). You can't pass complex objects.
JSON-encoded strings work as a workaround.

### Convention-Based Customization

Rather than inputs, the reusable workflow can rely on conventions in the
caller repo:
- `scripts/set-version.sh` -- version stamping logic
- `scripts/set-dev-version.sh` -- dev version bump logic
- `.release.yml` or `release.config.toml` -- configuration file

This keeps the input count low and lets each repo's release behavior be
self-contained.

## 9. Versioning the Reusable Workflow

Callers pin to a git ref:

```yaml
uses: tsukumogami/shirabe/.github/workflows/release.yml@v1
```

Options for the ref:
- **Branch**: `@main` -- always latest, risky for callers
- **Tag**: `@v1.2.3` -- exact pin, safe but requires manual bumps
- **Major tag**: `@v1` -- follows semver convention, updated to point at
  latest v1.x.y. This is the standard pattern used by most actions.

### How Major Tags Work

When shirabe releases v1.3.0 of the workflow:

```bash
git tag v1.3.0
git push origin v1.3.0
git tag -f v1          # Force-update the v1 tag
git push -f origin v1  # Force-push the updated tag
```

Callers using `@v1` automatically get the update. Callers using
`@v1.2.3` are unaffected.

### Breaking Changes

If the workflow needs a breaking change (removing an input, changing
semantics), publish `@v2`. Callers on `@v1` are unaffected. This mirrors
how `actions/checkout@v3` vs `@v4` works.

### SHA Pinning

Security-conscious callers can pin to a full SHA:

```yaml
uses: tsukumogami/shirabe/.github/workflows/release.yml@abc123def456
```

This is immune to tag mutation attacks but requires manual updates.

## 10. Examples of Popular Reusable Release Workflows

### googleapis/release-please

release-please is widely used but as a GitHub Action, not a reusable
workflow. Still relevant as a design reference -- it handles version
bumps via PRs (Release PR pattern) rather than direct pushes.

### slsa-framework/slsa-github-generator

Publishes reusable workflows for provenance-signed releases. Complex
example of `workflow_call` with inputs for build config, artifact paths,
and attestation. Callers pin to `@v2`.

### Homebrew/actions

Homebrew publishes reusable workflows for formula testing and release.
Uses `workflow_call` with `secrets: inherit` to pass bottle-signing keys.

### Common Pattern in the Wild

Most popular release systems (semantic-release, release-please,
changesets) are distributed as *actions* (composite or Docker), not
reusable workflows. The reusable workflow pattern is more common for
organization-internal CI standardization. Shirabe's use case fits well --
it's standardizing release across a small set of repos with a common
convention.

## 11. Constraints Summary for the Release Workflow Design

| Concern | Status | Notes |
|---------|--------|-------|
| Check out caller repo | Works | Default `actions/checkout` behavior |
| Run caller scripts | Works | After checkout, full filesystem access |
| Push commits | Works | Needs `contents: write` or PAT for protected branches |
| Create tags | Works | Needs `contents: write` |
| Create GH releases | Works | Via `gh` CLI, needs `contents: write` |
| Pass version input | Works | `string` type input |
| Pass secrets | Works | Explicit or `secrets: inherit` |
| Branch protection | Caveat | May need PAT or GitHub App token |
| Max inputs | Limit: 10 | Pack complex config into JSON string if needed |
| Environment vars | Indirect | Use `vars` context from caller repo or pass as inputs |
| Matrix strategy | Not supported | Can't matrix over a `uses` job |
| Versioning | Standard | Major tag pattern (`@v1`) |
| Nesting depth | Limit: 4 | Not a concern for this use case |
| Cross-org calling | Works | shirabe is public, anyone can call |

## 12. Recommended Design Decisions

Based on these findings, for the shirabe reusable release workflow:

1. **Use `workflow_call` with explicit inputs**: version, dry-run flag,
   and optionally a dev-version string for the post-release bump.

2. **Rely on caller scripts for repo-specific logic**: The workflow calls
   `scripts/set-version.sh` and `scripts/set-dev-version.sh` at
   conventional paths. Each repo implements these.

3. **Use `GITHUB_TOKEN` by default**: Require callers to set
   `permissions: contents: write`. Accept an optional explicit secret for
   repos with branch protection.

4. **Version with major tags**: Publish as `@v1`, update on each release.

5. **Keep inputs under 10**: version, dry-run, release-branch,
   dev-version-suffix -- that's 4. Plenty of room.

6. **Use `gh` CLI for release creation**: Avoids third-party action
   dependencies. `gh` is pre-installed on GitHub runners.
