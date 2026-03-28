---
status: Draft
problem: |
  Repos in the tsukumogami ecosystem maintain independent release workflows that
  duplicate the same prepare-release logic and have already caused version drift
  bugs. There's no shared release tool -- each repo reinvents tagging, version
  stamping, release notes, and post-release cleanup independently.
goals: |
  A release skill and reusable GitHub Actions workflow that any repo can adopt
  by providing convention-based hooks. Repo owners get a consistent, safe release
  experience. Consumers get reliable version detection and update availability.
---

# PRD: Reusable Release System

## Status

Draft

## Problem Statement

Four repos in the tsukumogami ecosystem (tsuku, koto, niwa, shirabe) each
maintain their own release workflow. These workflows duplicate the same
pattern -- tag push triggers build, create GitHub release, optional
post-release cleanup -- but each implements it differently:

- tsuku: 520-line workflow covering Go + Rust + GPU backends, draft-then-publish
- koto: Cross-compiled Rust with a post-release version-pinning commit
- niwa: Single goreleaser job with a possible draft-never-promoted bug
- shirabe: No release workflow at all; versions already drifted (0.2.0 in
  manifests vs 0.1.0 tag)

This duplication has caused real bugs. Koto issue #81 hit a version drift
problem identical to shirabe's -- the version in Cargo.toml didn't match
the git tag. Both repos solved it independently with different approaches.
Shirabe issue #4 explicitly asks for reusable workflows.

The current org-level /release skill pushes a tag and monitors CI. It
doesn't handle version file updates, dev version bumping, or draft release
management. Repos that need version-stamped commits before tagging (like
Claude Code plugins, where the marketplace reads version from the tagged
commit) can't use it without workarounds.

## Goals

- **G1**: Repo owners can release any repo type (Go, Rust, plugin, config)
  with the same skill and workflow, customized only through repo-local hooks.
- **G2**: The tag always points to a commit with the correct release version
  in all version files. No version drift by construction.
- **G3**: Release notes are agent-authored and human-reviewed before publication.
- **G4**: Failed releases are recoverable without git surgery. The system
  fails safely and reports actionable recovery steps.
- **G5**: New repos can adopt the system by adding a caller workflow and
  optional hook scripts. No changes to the reusable workflow required.

## User Stories

### US1: Standard release from main

As a repo owner, I want to cut a release by running a single command that
handles version stamping, tagging, release notes, and post-release cleanup,
so that I don't manually edit version files or remember the release sequence.

### US2: Release with no build artifacts

As a plugin repo owner, I want to release without any build step -- just
version stamp, tag, and publish -- so that the release system doesn't
require me to set up build infrastructure I don't need.

### US3: Release with complex builds

As a binary repo owner, I want the release system to handle the
prepare-release dance (version stamp, tag, dev bump) while my existing
build workflow handles compilation and artifact upload, so that I don't
have to rewrite my build pipeline.

### US4: Consumer update detection

As a Claude Code plugin consumer, I want the released version to be
correct in plugin.json at the tagged commit, so that Claude Code's
marketplace detects the update and prompts me to install it.

### US5: Adopting the system

As a repo owner adopting the release system for the first time, I want to
set it up by adding a small caller workflow and optionally a set-version
script, so that adoption doesn't require understanding the internals.

### US6: Dry-run before releasing

As a repo owner, I want to preview exactly what the release will do
(which files change, what commits are created, what tag is produced)
without actually pushing anything, so that I can verify correctness before
committing to an irreversible action.

### US7: Recovery from a failed release

As a repo owner whose release failed mid-way, I want clear error messages
telling me what state my repo is in and what command to run to recover, so
that I don't have to diagnose the failure from raw git state.

### US8: Workflow versioning

As a repo owner calling the reusable workflow, I want to pin to a stable
version and be notified of breaking changes, so that my release process
doesn't break when shirabe updates.

## Requirements

### Functional Requirements

**R1: Release skill**. The system includes a single skill invokable as
`/release [version]`. The skill analyzes commits since the last release,
recommends a version bump (patch/minor/major) based on conventional commit
prefixes and breaking change indicators, and presents the recommendation
for the user to confirm or override. It then validates preconditions
(clean tree, CI green, no blockers, no existing tag), generates release
notes, creates a draft GitHub release, and dispatches the reusable
workflow. It does not push commits or create tags directly. This replaces
the previous two-phase `/prepare-release` + `/release` split.

**R2: Reusable workflow**. The system includes a GitHub Actions workflow
triggered by `workflow_dispatch` (and callable via `workflow_call`). The
workflow performs the Maven-style prepare-release dance: call set-version
hook with the release version, commit, create annotated tag, call
set-version hook with the next dev version, commit, push branch and tag,
promote the draft release to published.

**R3: Hook contract**. Repos customize the release by providing
convention-based scripts in a `.release/` directory:
- `.release/set-version.sh <version>`: Updates repo-specific version files.
  Called twice per release -- once with the release version (e.g., `0.3.0`),
  once with the next dev version (e.g., `0.3.1-dev`). The version argument
  never includes a `v` prefix.
- `.release/post-release.sh <version>`: Optional. Runs after the release is
  published. For repo-specific cleanup (e.g., koto's version pin commit).

Both hooks receive the version as the first argument. Both must exit 0 on
success, non-zero on failure. If a hook doesn't exist, the workflow skips it.

**R4: Draft-then-promote**. The skill creates a draft GitHub release with
human-reviewed release notes before dispatching the workflow. The workflow
promotes the draft to published as its final step. This separates note
authoring (local, human-reviewed) from publishing (CI, automated).

**R5: Dev version sentinel**. After each release, the workflow advances
version files to the next dev version (patch bump + `-dev` suffix, e.g.,
`0.3.0` release produces `0.3.1-dev`). This prevents version drift between
releases and enables update detection for consumers tracking HEAD.

**R6: CI sentinel check**. Repos with version files include a CI workflow
that validates the dev sentinel suffix on PRs touching version files. The
suffix is configurable per repo (e.g., `-dev`, `-SNAPSHOT`, `+dev`) via
a setting in `.release/` or the caller workflow inputs. The default is
`-dev`. The check uses a regex pattern that matches the configured suffix,
not a hardcoded string.

**R7: Precondition validation**. Before starting the release, the skill
checks: clean working tree, CI green on HEAD, no existing tag for the
requested version, no existing draft release for the requested version.
The workflow checks: push token is valid, tag doesn't exist remotely,
hook scripts are executable (if present).

**R8: Dry-run mode**. The workflow accepts a `dry-run` input. When true,
it performs all steps (set-version, commit, tag, dev bump) but skips push
and draft promotion. It outputs what it would have done.

**R9: Workflow versioning**. The reusable workflow ships from shirabe and
shares shirabe's version tags. Callers reference it by shirabe's major
version (e.g., `@v1`). Breaking changes to the workflow inputs, hook
contract, or commit format require a new shirabe major version. Old major
tags are preserved indefinitely.

### Non-Functional Requirements

**R10: No force-push**. The workflow never force-pushes. All pushes are
fast-forward only. If fast-forward fails, the workflow fails with an error
message suggesting `git pull --rebase` and manual recovery.

**R11: Actionable errors**. Every failure includes: what failed, what state
the repo is in, and the exact command to recover. No generic "step failed"
messages.

**R12: Push order**. The workflow pushes the branch first, then the tag.
This ensures the tagged commit is reachable from the branch before any
tag-triggered workflows (like existing build pipelines) run.

**R13: Independent operation**. The workflow is usable from the GitHub
Actions UI without the skill (manual dispatch with version input). The
skill is usable without the workflow for repos that only need checklist
and notes management.

**R14: Hook contract stability**. The hook contract (script paths,
argument format, environment variables, exit code semantics) is a public
API. Changes are breaking and follow the workflow versioning protocol (R9).

## Acceptance Criteria

- [ ] A repo with no `.release/` hooks can use the workflow to create a
      tag and GitHub release (baseline behavior)
- [ ] A repo with `.release/set-version.sh` gets version files stamped
      before tagging and bumped to dev after tagging
- [ ] A repo with `.release/post-release.sh` gets the script called after
      the release is published
- [ ] The tag points to a commit where version files contain the release
      version (not the dev sentinel)
- [ ] After release, main contains the next dev version in all version
      files updated by set-version.sh
- [ ] `dry-run: true` performs all steps except push and promotion, and
      outputs what it would have done
- [ ] Failed releases produce error messages with the exact recovery
      command for the specific failure point
- [ ] The reusable workflow can be called from another repo via
      `workflow_call` with `@v1` pinning
- [ ] The skill generates release notes from commit history, presents
      them for editing, and creates a draft release
- [ ] Existing tag-triggered build workflows (tsuku, koto, niwa) continue
      to work after the tag is pushed by the reusable workflow
- [ ] The sentinel CI check rejects PRs that change version files to
      non-dev-sentinel values
- [ ] All public repos in tsukumogami (tsuku, koto, niwa, shirabe) use
      this workflow for their releases

## Out of Scope

- **Automatic semver computation.** The human picks the version. The
  system doesn't analyze commit history to decide between patch/minor/major.
- **Package registry publishing.** Crates.io, npm, PyPI, etc. are out of
  scope. The system creates GitHub releases only.
- **Build pipeline abstraction.** Each repo keeps its own build jobs.
  The reusable workflow handles the prepare-release dance, not compilation.
- **Changelog generation tooling.** Release notes are drafted from commit
  history and human-edited. No CHANGELOG.md automation.
- **Pre-release/beta versions.** Deferred to a future iteration. The MVP
  handles standard semver releases only.
- **Hotfix releases from non-main branches.** Deferred. The MVP releases
  from main only. However, the workflow accepts a `ref` input (defaulting
  to `main`) and the dev-bump step targets a configurable branch, so
  adding release branch support later doesn't require breaking changes.
- **Rewriting existing build pipelines.** Tsuku, koto, and niwa keep their
  existing build/test/publish jobs. Migration adds the reusable workflow as
  the prepare-release step alongside existing tag-triggered builds.

## Open Questions

- ~~**Q1**: Two-phase or single command?~~ **Resolved**: Single `/release`
  command that handles blocker checks, version recommendation, notes
  drafting, and workflow dispatch. The draft GH release replaces the
  checklist issue as the persistent artifact.
- **Q2**: When the reusable workflow pushes to main, should it use
  `GITHUB_TOKEN` (limited to the workflow's permissions) or require a PAT
  (for branch-protected repos)? Or accept either via a `token` input?
- **Q3**: How should the skill discover the "previous release" for
  generating release notes? Latest semver tag? Latest GitHub release?

## Known Limitations

- **Draft window.** Between the skill creating a draft and the workflow
  promoting it, consumers querying `/releases/latest` get the previous
  release. This is intentional -- the draft gates on CI completing -- but
  means there's a window where the latest release appears unchanged.
- **Single-branch MVP.** Only main-branch releases are supported initially.
  Hotfix branches require manual workflow dispatch with careful
  configuration.
- **Workflow coupling.** The reusable workflow is versioned with shirabe's
  tags. Plugin-only changes bump the tag even if the workflow didn't
  change. Release notes will distinguish workflow changes from plugin
  changes.

## Decisions and Trade-offs

**D1: Workflow_dispatch over tag-triggered**. The reusable workflow uses
`workflow_dispatch` rather than reacting to tag pushes. This lets CI own
the full commit-tag-push sequence, guaranteeing the tag points to a
commit with correct version files. Tag-triggered workflows can't stamp
version files before the tag exists.

**D2: Draft-then-promote over workflow input for notes**. Release notes
are created as a draft GH release by the skill, not passed as a workflow
input. Draft releases support full markdown without escaping issues,
are editable in the GitHub UI, and survive workflow failures (the draft
persists for retry).

**D3: Convention-based hooks over declarative config**. Repos provide
shell scripts (`.release/set-version.sh`) rather than a config file
listing version file paths. Shell hooks handle arbitrary logic (tsuku's
multi-file sed, koto's version pin commit) that a declarative approach
couldn't express.

**D4: Rolling dev sentinel over fixed sentinel**. Version files on main
carry `<next>-dev` (e.g., `0.3.1-dev`) rather than a fixed `0.0.0-dev`.
This enables update detection for users installing from HEAD, since the
version changes after each release.

**D5: Patch bump for dev version**. After releasing `X.Y.Z`, the dev
version is always `X.Y.(Z+1)-dev`. The actual next release might be a
minor or major bump, but the dev version is just a placeholder indicating
"newer than the last release." The human picks the real version at release
time.
