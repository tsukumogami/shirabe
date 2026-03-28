---
status: Proposed
problem: |
  Shirabe's plugin.json and marketplace.json versions drift from git tags because
  versions are maintained manually. The Claude Code marketplace reads version from
  plugin.json at the tagged commit, making this a correctness problem: stale versions
  cause users to miss updates. The release process needs to set versions automatically
  at release time and integrate with the org's existing /prepare-release and /release
  skills.
decision: |
  The /release skill stamps both manifest files with the release version and commits
  before creating the annotated tag. A tag-triggered GitHub Actions workflow creates
  the GH release and resets manifests to 0.0.0-dev on main. A dedicated CI workflow
  validates the sentinel on every PR that touches .claude-plugin/.
rationale: |
  Commit-first-then-tag is the only approach that guarantees marketplace correctness,
  since Claude Code reads plugin.json at the tagged commit. The sentinel prevents
  drift between releases and gives CI a trivial check. This extends the /release skill
  naturally while keeping the tag-triggered workflow pattern consistent with koto.
---

# DESIGN: Release Process

## Status

Proposed

## Context and Problem Statement

Shirabe is a Claude Code skills plugin with version declared in two manifest files
(`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`). The Claude Code
marketplace reads the version from `plugin.json` at the specific git ref/sha -- the
version field is the sole mechanism for update detection. If two refs have identical
versions, Claude Code treats them as the same and skips the update.

Currently versions are maintained manually. The manifests already drifted: both say
0.2.0 while the only git tag is 0.1.0. No release workflow exists. No CI validates
version consistency.

Exploration found that neither koto nor tsuku face this problem (they have no plugin
manifests). Superpowers, the most prominent Claude Code plugin, uses fully manual
versioning with no automation -- this is an unsolved problem in the ecosystem.

## Decision Drivers

- Marketplace correctness: version in plugin.json at the tagged commit must match the
  tag name
- Integration with existing /prepare-release and /release org skills
- Full automation: version set at release time, not maintained manually
- Prevention of version drift between releases
- Simplicity: shirabe has no binaries to build, so the workflow should be minimal
- Consistency with koto/tsuku release patterns where possible

## Considered Options

### Decision 1: Release flow architecture

The /release skill creates annotated tags locally and pushes them to trigger CI.
Shirabe's constraint is that plugin.json must contain the correct version at the
tagged commit, because the marketplace reads version from that exact ref. This
rules out any flow where the tag exists before manifests are updated.

Three approaches were evaluated: extending the /release skill to update manifests
before tagging, moving the entire release to a workflow_dispatch workflow, or using
a release branch.

Key assumptions:
- The Claude Code marketplace resolves plugin version by reading plugin.json at the
  tagged ref. If wrong: the tag-must-match-manifest constraint is unnecessary.
- The /release skill can accommodate a repo-specific pre-tag step without a full
  rewrite. If wrong: the skill needs a hook mechanism first.
- RELEASE_PAT secret is available for the finalize-release job (same as koto).

#### Chosen: /release skill updates manifests locally before tagging

The /release skill handles manifest updates as a pre-tag step. The full flow:

1. `/prepare-release <version>` creates a release checklist issue (unchanged).
2. `/release <issue>` validates the checklist, generates release notes.
3. `/release` replaces `0.0.0-dev` with the release version in both
   `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
4. `/release` commits the manifest change: `chore(release): set version to <version>`.
5. `/release` creates an annotated tag on that commit with release notes as the message.
6. `/release` pushes the commit and tag to origin.
7. A tag-triggered GitHub Actions workflow (`release.yml`, triggered on `v*` tags):
   a. Creates a GitHub release using the tag's annotation as release notes.
   b. Runs a `finalize-release` job that checks out main, resets both manifests to
      `0.0.0-dev`, commits (`chore(release): reset version to 0.0.0-dev`), and pushes.

The tag always points to a commit where plugin.json has the correct version. Main
normally carries `0.0.0-dev`, briefly has the real version during the release commit,
and returns to `0.0.0-dev` after finalize-release.

#### Alternatives Considered

**workflow_dispatch orchestration**: Server-side workflow accepts version input, updates
manifests, commits, tags, and creates the release. Rejected because it splits release
logic between the local skill and a server-side workflow, reduces testability (can't
dry-run locally), and requires passing release notes through workflow inputs (awkward
for multi-paragraph notes). Also breaks consistency with koto's tag-triggered pattern.

**Release branch with updated manifests**: Create a short-lived release branch, update
manifests there, tag, push, then clean up the branch. Rejected because it introduces
branch management overhead (creation, cleanup, merge) without clear benefit for a
project with no build artifacts.

### Decision 2: CI validation approach

Manifests on main contain the sentinel `0.0.0-dev`. Without enforcement, a contributor
could accidentally commit a version bump in a PR, breaking the sentinel contract. The
check needs to fit shirabe's existing CI pattern: path-filtered triggers, single-concern
workflows, and shell scripts in `scripts/`.

Key assumptions:
- The sentinel value is exactly the string `0.0.0-dev` -- simple equality is sufficient.
- Only `plugin.json` and `marketplace.json` contain version fields needing enforcement.

#### Chosen: Dedicated workflow with shell script

A new workflow `.github/workflows/check-sentinel.yml` triggers on PRs modifying
`.claude-plugin/**`. It calls `scripts/check-sentinel.sh`, which parses both JSON
files and verifies all version fields equal `0.0.0-dev`.

The workflow follows the check-evals pattern exactly: path-filtered trigger, single
job, single step calling a script. On failure, the script reports which file has
the wrong version, what value was found, and explains the sentinel convention.

#### Alternatives Considered

**Inline workflow check (no script)**: Puts validation logic directly in the workflow
YAML `run:` step. Rejected because it breaks the script-backed pattern, can't be run
locally for debugging, and saves one file at the cost of consistency.

**Add to an existing workflow**: Extends check-evals.yml with a sentinel job. Rejected
because it violates single-concern design, requires broadening path filters, and makes
the workflow name misleading.

**Pre-commit hook only**: Local git hook validates the sentinel before commit. Rejected
as the primary mechanism because hooks are voluntary and easily bypassed. Could
complement CI but can't replace it.

## Decision Outcome

**Chosen: Local manifest stamping + tag-triggered workflow + sentinel CI check**

### Summary

The /release skill gains a pre-tag step that replaces `0.0.0-dev` in both
`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` with the release
version, then commits before creating the annotated tag. This guarantees the tag always
points to a commit with the correct version in plugin.json -- the field the Claude Code
marketplace uses for update detection.

After the tag is pushed, a GitHub Actions workflow (`release.yml`) creates the GitHub
release from the tag annotation and runs a `finalize-release` job that resets both
manifests to `0.0.0-dev` on main. This mirrors koto's pattern but adds the sentinel
reset step.

Between releases, a CI check (`check-sentinel.yml`) runs on PRs that modify
`.claude-plugin/**` and verifies the sentinel is intact. The check calls
`scripts/check-sentinel.sh`, which uses `jq` to extract version fields and compare
against `0.0.0-dev`. Clear error messages guide contributors who aren't familiar
with the convention.

The version is determined by the user at `/prepare-release` time and confirmed at
`/release` time. No automatic semver bumping -- the human decides what the next
version should be, and the tooling ensures it's applied consistently.

### Rationale

This combination works because each piece reinforces the others. The sentinel on
main prevents accidental drift. The /release pre-tag step guarantees correctness
at the tagged commit. The finalize-release job restores the sentinel automatically.
And the CI check catches the one scenario none of the others cover: a contributor
manually changing the version in a PR.

The approach extends the /release skill naturally rather than replacing it. The
tag-triggered workflow matches koto's existing release.yml, keeping the org's CI
patterns consistent. The sentinel CI check follows shirabe's existing path-filtered,
script-backed workflow pattern.

## Solution Architecture

### Overview

Three components work together: the /release skill extension (local, runs during
release), the release.yml GitHub Actions workflow (server-side, triggered by tag),
and the check-sentinel.yml CI workflow (server-side, runs on PRs).

### Components

**1. /release skill pre-tag hook**

A repo-specific step in the /release skill that runs after release notes generation
but before tag creation. It:
- Reads the version from the release checklist issue title (e.g., `v0.3.0`)
- Strips the `v` prefix for manifest values (manifests use `0.3.0`, not `v0.3.0`)
- Uses `jq` to update `.version` in `.claude-plugin/plugin.json`
- Uses `jq` to update `.plugins[0].version` in `.claude-plugin/marketplace.json`
- Commits: `chore(release): set version to v<version>`

The hook is implemented as a conditional block in the /release skill's Phase 3
(tag creation). It detects shirabe by checking for `.claude-plugin/plugin.json`
existence. Other repos without this file skip the hook.

**2. release.yml (GitHub Actions)**

Tag-triggered workflow with two jobs:

```
v* tag push
  |
  +-> release job
  |     - Validate tag format matches v<major>.<minor>.<patch>
  |     - Extract release notes from tag annotation
  |     - Create GitHub release
  |
  +-> finalize-release job (needs: release)
        - Checkout main with RELEASE_PAT
        - Reset plugin.json version to 0.0.0-dev
        - Reset marketplace.json version to 0.0.0-dev
        - Commit and push to main (pull --rebase first to handle concurrent merges)
```

The release job validates the tag format with a regex (`^v[0-9]+\.[0-9]+\.[0-9]+$`)
early and fails fast on malformed tags. The finalize-release job runs
`git pull --rebase origin main` before committing to handle the case where a PR
merged between the release push and the finalize job. If the rebase fails (unlikely
given the narrow window), the job fails and the sentinel reset must be done manually.

**3. check-sentinel.yml (GitHub Actions)**

PR validation workflow:

```
PR modifies .claude-plugin/**
  |
  +-> check-sentinel job
        - Run scripts/check-sentinel.sh
        - Verify plugin.json .version == "0.0.0-dev"
        - Verify marketplace.json .plugins[0].version == "0.0.0-dev"
        - Fail with clear message if either differs
```

**4. scripts/check-sentinel.sh**

Shell script that:
- Extracts version from both manifest files using `jq`
- Compares against `0.0.0-dev`
- On failure: reports which file, what value was found, and explains the convention
- Exit 0 on success, exit 1 on failure

### Key Interfaces

**Manifest version fields:**
- `.claude-plugin/plugin.json`: `.version` (top-level)
- `.claude-plugin/marketplace.json`: `.plugins[0].version` (nested in first plugin entry)

**Tag format:** `v<major>.<minor>.<patch>` (e.g., `v0.3.0`)

**Sentinel value:** `0.0.0-dev` (exact string, no variations)

**RELEASE_PAT secret:** Required by finalize-release job to push to protected main
branch. Same secret koto already uses.

### Data Flow

```
Normal development:
  main has 0.0.0-dev in manifests
  PRs validated by check-sentinel.yml

Release:
  /prepare-release v0.3.0 --> creates checklist issue
  /release <issue>
    --> validates checklist
    --> generates release notes
    --> updates manifests to 0.3.0
    --> commits "chore(release): set version to v0.3.0"
    --> creates annotated tag v0.3.0
    --> pushes commit + tag

  release.yml triggers on v0.3.0 tag:
    release job --> creates GH release with tag annotation
    finalize-release job --> resets manifests to 0.0.0-dev on main
```

## Implementation Approach

### Phase 1: Sentinel bootstrap

Switch manifests from their current values to the sentinel and create the CI check.

Deliverables:
- Update `.claude-plugin/plugin.json` version to `0.0.0-dev`
- Update `.claude-plugin/marketplace.json` version to `0.0.0-dev`
- Create `scripts/check-sentinel.sh`
- Create `.github/workflows/check-sentinel.yml`
- Configure GitHub tag protection rules for `v*` tags

### Phase 2: Release workflow

Create the tag-triggered GitHub Actions workflow.

Deliverables:
- Create `.github/workflows/release.yml` with release and finalize-release jobs
- Test with a dry-run tag (can be deleted after verification)

### Phase 3: Skill integration

Extend the /release skill to handle manifest updates before tagging.

Deliverables:
- Pre-tag hook in /release skill that detects `.claude-plugin/plugin.json` and
  updates both manifests
- Documentation of the release process in README or CONTRIBUTING

### Phase 4: First release

Tag the current state as the first proper release using the new process.

Deliverables:
- Run `/prepare-release` and `/release` end-to-end
- Verify the tag has correct manifests
- Verify finalize-release resets the sentinel

## Security Considerations

**RELEASE_PAT scope:** The personal access token used by finalize-release needs
write access to the repository's main branch. It must be a fine-grained PAT scoped
to the shirabe repository only with `contents: write` permission -- not a classic
PAT with broader access. Stored as a repository secret, same pattern koto uses.
The finalize-release push bypasses branch protection rules (required reviews, status
checks) by design; this is intentional and consistent with koto's established pattern.

**Script injection:** `check-sentinel.sh` uses `jq` for JSON parsing rather than
string matching with `grep` or `sed`, avoiding injection risks from malformed JSON.
The release workflow uses `jq` for the same reason.

**Tag annotation extraction:** The release workflow extracts tag annotations using
`git tag -l --format='%(contents)'`. This is safe because tag annotations are
written by the /release skill (not user input) and the format string is fixed.

**Tag format validation:** The release workflow validates the tag name matches
`^v[0-9]+\.[0-9]+\.[0-9]+$` before proceeding. Git allows arbitrary tag names,
so the workflow must enforce the expected format rather than relying on convention.

**Tag protection:** GitHub tag protection rules should be configured for `v*` tags
to prevent deletion and recreation. Without this, a compromised token or malicious
actor with push access could redirect a tag to a different commit.

**PAT lifecycle:** The RELEASE_PAT should be created as a fine-grained PAT with an
expiration date. Rotation should happen when the token expires. The token's usage
is visible in GitHub's audit log.

## Consequences

### Positive
- Version drift between tag and manifests becomes impossible by construction
- The marketplace always sees the correct version at the tagged commit
- CI catches accidental version bumps before they reach main
- Release process is fully automated -- no manual file editing
- Pattern is consistent with koto's existing release workflow

### Negative
- Two extra commits per release on main (version stamp + sentinel reset)
- The /release skill needs a shirabe-specific extension (increases skill complexity)
- `plugin.json` on main shows `0.0.0-dev` instead of the current release version
- Contributors browsing the repo see an uninformative version in the manifest

### Mitigations
- Extra commits are low-frequency (shirabe doesn't release often) and consistent
  with koto's pattern, so they're expected in the git history
- The /release extension can be implemented as a generic plugin-manifest hook that
  any repo with `.claude-plugin/plugin.json` can use
- The current release version is visible in GitHub releases and git tags -- the
  manifest on main isn't the primary place users check version
- If finalize-release fails (leaving main with a real version instead of the
  sentinel), the fix is a single manual commit resetting to `0.0.0-dev`. CI will
  flag the drift on the next PR that touches `.claude-plugin/`
