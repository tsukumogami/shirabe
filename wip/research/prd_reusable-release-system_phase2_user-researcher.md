# User Research: Reusable Release System

Phase 2 research from the User Researcher perspective. Covers repo owner
workflows (Lead 1) and consumer experiences (Lead 2) across all four repo
types in the tsukumogami ecosystem.

---

## Lead 1: Repo Owner Workflow

### User Story Set A: Go Binary Repo (tsuku, niwa)

**Persona**: Repo owner with push access to main and tag creation
permissions.

#### Story A1: Standard release from main

The owner decides to release after merging several PRs.

1. Owner runs the release skill: `/release 0.5.0`
2. The skill checks preconditions:
   - Main branch is checked out, clean working tree
   - CI is green on HEAD (queries `gh run list --branch main`)
   - No existing `v0.5.0` tag
3. The skill generates release notes from commits since the last tag,
   grouped by conventional commit prefix. Presents them in `$EDITOR`.
4. Owner reviews, edits the notes (adds context about a breaking change),
   saves, and closes the editor.
5. The skill asks: "Create draft release v0.5.0? [Y/n]"
6. Owner confirms. The skill:
   - Creates a draft GitHub release with the notes
   - Creates an annotated tag `v0.5.0` pointing at HEAD
   - Pushes the tag
7. The skill prints: "Draft release created. CI triggered. Run `/ci` to
   monitor."
8. The tag push triggers `release.yml`. GoReleaser builds binaries for
   linux/darwin x amd64/arm64. Integration tests run against the draft
   release artifacts. The finalize job verifies all expected artifacts,
   generates checksums, and promotes the draft to published.
9. Owner monitors with `/ci` and sees each phase: build, test, finalize.

**Key decision point**: Step 4 -- the owner edits release notes. This is
where they add narrative context that commit messages alone don't capture.

**What if they cancel at step 5?** Nothing has been pushed. No tag, no
draft release. The generated notes are lost (or could be saved to a temp
file for later use). Clean cancellation.

**What if CI fails at step 8?** The draft release remains. The tag exists
on the remote. The owner can:
- Fix the issue, force-push the tag to a new commit, and re-trigger
- Delete the tag and draft release, then start over
- The PRD must specify which recovery path the skill supports.

**niwa-specific difference**: niwa's release.yml is simpler (no Rust
builds, no integration tests). The GoReleaser draft-then-publish flow is
the same, but today niwa may have a bug where the draft is never promoted
to published. The reusable system must ensure the draft-to-published
promotion always happens.

#### Story A2: First-ever release

Same as A1 except:
- No previous tag exists, so "commits since last tag" means all commits.
- The generated notes could be enormous. The skill should handle this
  gracefully -- perhaps showing a count ("347 commits since initial
  commit") and offering to generate a summary instead of a full list.
- The owner may want hand-written notes for a first release rather than
  auto-generated ones.

**PRD gap**: The exploration didn't address how release note generation
behaves when there's no previous tag. The PRD should specify: fall back
to a template or empty editor if no prior tag exists.

#### Story A3: Pre-release / beta

Owner wants to ship `v0.5.0-rc.1` for testing.

1. Owner runs: `/release 0.5.0-rc.1`
2. The skill follows the same flow as A1.
3. GoReleaser's `prerelease: auto` marks it as a pre-release on GitHub.
4. The `/releases/latest` API endpoint skips it, so install.sh users
   don't get it accidentally.
5. No finalize-release or sentinel advancement needed (pre-releases don't
   change the dev sentinel).

**PRD gap**: The exploration mentioned GoReleaser's `prerelease: auto`
behavior but didn't specify whether the skill should treat pre-releases
differently (skip finalize? skip sentinel bump?). The PRD must define
this.

#### Story A4: Hotfix from non-main branch

Owner needs to patch v0.4.x while main has moved to v0.5.0-dev work.

1. Owner creates a `release/0.4.x` branch from the `v0.4.2` tag.
2. Cherry-picks the fix commit.
3. Runs `/release 0.4.3` from the branch.
4. The skill detects it's not on main. Two options:
   a. Refuse: "Releases must be from main." (simpler, but blocks hotfixes)
   b. Warn and proceed: "Releasing from branch release/0.4.x. Continue?"
5. If allowed, the flow proceeds as A1 but the finalize step must NOT
   advance the sentinel on main (since main is ahead).

**PRD gap**: The exploration assumed all releases come from main. The PRD
must specify whether hotfix releases from non-main branches are
supported, and if so, how finalize-release behaves.


### User Story Set B: Rust Binary Repo (koto)

#### Story B1: Standard release from main

1. Owner runs: `/release 0.3.0`
2. Precondition checks same as Go repos.
3. The skill detects `Cargo.toml` and runs `.release/set-version.sh 0.3.0`
   which updates the version field in `Cargo.toml`.
4. The skill commits: `chore(release): set version to v0.3.0`
5. Release notes generated, presented in `$EDITOR`, owner reviews.
6. The skill creates a draft release, annotated tag on the version-stamped
   commit, and pushes both the commit and tag.
7. CI triggers: `cross`/`cargo` builds for 4 platform targets, checksums
   generated, draft promoted to published.
8. Finalize-release: pins `koto-version` in the reusable workflow
   default, and if using a rolling sentinel, advances `Cargo.toml` to
   `0.3.1-dev`.

**Key difference from Go repos**: The version-stamp commit happens BEFORE
the tag. For Go repos using only ldflags, there's no commit -- the tag
alone is sufficient. This is the "Maven-style prepare-release dance" the
scope document references.

**What if cancel after step 4 but before step 6?** A version-stamp
commit exists locally but hasn't been pushed. The owner needs to
`git reset HEAD~1` to undo it. The skill should handle this: if the user
cancels, the skill should offer to revert the commit.

**PRD gap**: Cancellation after a local commit but before push is a state
the exploration didn't address. The PRD must specify rollback behavior.

#### Story B2: Version file validation

Today, koto's `Cargo.toml` version and git tag can drift. With the new
system:
- `set-version.sh` updates Cargo.toml before tagging
- CI could validate `Cargo.toml` version matches the tag name
- The rolling sentinel (`0.3.1-dev`) on main prevents drift between
  releases

**PRD should specify**: Does the reusable workflow validate version file
contents against the tag, or is this left to repo-specific CI?


### User Story Set C: Claude Code Plugin Repo (shirabe)

#### Story C1: Standard release from main

1. Owner runs: `/release 0.2.0`
2. Preconditions checked (same as others, plus sentinel check: current
   manifests must show `0.2.0-dev`).
3. The skill runs `.release/set-version.sh 0.2.0` which updates:
   - `.claude-plugin/plugin.json` version to `0.2.0`
   - `.claude-plugin/marketplace.json` version to `0.2.0`
4. Commits: `chore(release): set version to v0.2.0`
5. Release notes in `$EDITOR`, owner reviews.
6. Draft release created, annotated tag on the version-stamped commit,
   push.
7. CI triggers: no build step (no binaries). The release job creates the
   GH release from the tag annotation. The finalize-release job advances
   manifests to `0.2.1-dev` on main.
8. The Claude Code marketplace detects the new version at the tagged ref.

**Critical correctness constraint**: The tag MUST point to a commit where
`plugin.json` has the release version (not `-dev`). This is why the
commit-then-tag order is non-negotiable for shirabe.

#### Story C2: Sentinel version mismatch

Owner tries to release `0.3.0` but manifests show `0.2.1-dev`.

Two interpretations:
a. The owner is skipping `0.2.1` and going straight to `0.3.0`. Valid.
b. The owner made a mistake. The sentinel says the next release should
   be `0.2.1`.

**PRD should specify**: Does the skill warn when the requested version
doesn't match the sentinel's implied next version? Or is the sentinel
purely a CI mechanism with no skill-side validation?

#### Story C3: Pre-release for plugin testing

Owner wants to ship `0.2.0-rc.1` to test marketplace integration.

**Problem**: The sentinel check (`check-sentinel.sh`) only accepts
`-dev` suffix. A pre-release commit would need `0.2.0-rc.1` in the
manifests, which the sentinel check would reject on the PR.

**Options**:
a. Pre-releases skip the sentinel check (the release branch bypasses it)
b. Pre-releases are tag-only (no manifest change) -- but then the
   marketplace won't detect the update
c. Expand the sentinel check to accept `-dev`, `-rc.N`, `-beta.N`

**PRD must specify** the pre-release story for plugin repos, since it
interacts with the sentinel mechanism.


### User Story Set D: No-Build Repo (pure docs/config)

#### Story D1: Standard release

1. Owner runs: `/release 1.0.0`
2. No version files to stamp (`set-version.sh` is a no-op or doesn't
   exist).
3. Release notes generated, reviewed.
4. Tag created, pushed.
5. CI creates GH release from tag annotation. No build, no artifacts.
6. No finalize-release needed (no sentinel to advance).

This is the simplest case. The reusable system should degrade gracefully
to this baseline when no hooks exist.

**PRD consideration**: What's the minimum a repo needs to adopt the
system? Just calling the reusable workflow with `workflow_call`? Or must
it also have `.release/` hooks even if they're no-ops?


---

## Lead 2: Repo Consumer Experience

### tsuku consumers

**Current state**:
- Install via `curl -fsSL https://tsuku.dev/install.sh | sh`
- No `--version` flag on install.sh (unlike koto)
- No self-update mechanism (`tsuku update` manages OTHER tools, not
  tsuku itself)
- `tsuku outdated` shows outdated managed tools but not tsuku itself
- To update tsuku, re-run install.sh

**With the new release system**: No change. The release system affects
how releases are created, not how they're consumed. The install.sh still
points to `/releases/latest`. Consumers benefit indirectly from more
reliable releases (no draft-stuck-as-draft bugs).

**Unaddressed consumer gap**: tsuku has no way to tell its user "hey,
you're running v0.4.0 but v0.5.0 is available." This is out of scope
for the release system PRD but worth noting as a related concern.

### koto consumers

**Current state**:
- Install via `curl -fsSL .../install.sh | sh`
- Supports `--version=<tag>` for pinned installs
- No built-in update notification
- CI consumers (repos using `check-template-freshness.yml`) get
  automatic version pinning: the `finalize-release` job updates the
  `koto-version` default after each release

**With the new release system**: The koto-version pinning step moves from
a hardcoded `finalize-release` job to a `.release/post-release.sh` hook.
Functionally identical from the consumer's perspective. CI consumers
still get the latest koto version automatically.

**Edge case -- draft window**: Today koto publishes releases immediately
(no draft phase). With the new system using draft-then-promote, there's
a window where the release exists as a draft but isn't visible to
`/releases/latest`. If a consumer runs `install.sh` during this window,
they get the previous version. This is actually correct behavior (don't
serve unvalidated releases), but the PRD should acknowledge the window
exists.

### niwa consumers

**Current state**:
- Install via `curl -fsSL .../install.sh | sh`
- No `--version` flag (unlike koto)
- No update notification

**With the new release system**: Same as tsuku -- no consumer-facing
change. The main benefit is fixing the potential draft-never-promoted
bug in niwa's current workflow, ensuring releases actually become
visible to the install script.

**PRD consideration**: Should the reusable release system include a
standard install.sh template? All three binary repos have nearly
identical install scripts. This is adjacent to the release system
but might be a natural extension.

### shirabe consumers

**Current state**:
- Install via Claude Code marketplace (planned) or manual plugin
  configuration
- Update detection is automatic: Claude Code reads `plugin.json` at
  the installed ref and compares versions
- The `-dev` sentinel on main means users tracking HEAD get a changing
  version with each release cycle

**With the new release system**: This is the only repo type where the
release system directly affects consumer experience. The marketplace
reads `plugin.json` at the tagged ref, so the release system's
commit-before-tag pattern is what makes update detection work correctly.
Without it, the marketplace could see stale versions and skip updates.

**Edge case -- user on main vs tagged release**: A user tracking `main`
sees `0.2.1-dev`. A user on the `v0.2.0` tag sees `0.2.0`. If Claude
Code compares these, it should recognize that `0.2.1-dev` is newer.
Whether Claude Code handles semver-with-prerelease comparison correctly
is outside our control, but the PRD should document this assumption.


---

## Edge Cases Requiring PRD Specification

### 1. First release ever

- No prior tag means release note generation has no baseline.
- The skill should detect this and offer a template or empty editor.
- The rolling sentinel has no "previous release" to derive from. The
  initial sentinel must be set manually (already addressed by shirabe's
  Phase 1 bootstrap).

### 2. Pre-release / beta versions

- GoReleaser repos: `prerelease: auto` handles GitHub marking. Install
  scripts using `/releases/latest` skip pre-releases. No issues.
- Plugin repos: The sentinel check rejects non-`-dev` suffixes. The PRD
  must decide whether to expand the sentinel check or use a different
  mechanism for pre-release plugin versions.
- Should pre-releases trigger finalize-release? Probably not -- the
  sentinel should stay at the same `-dev` version until the final release.

### 3. Hotfix from non-main branch

- The skill must decide: refuse or warn-and-proceed.
- Finalize-release must NOT touch main's sentinel (main is ahead).
- The hook contract needs to know whether it's a hotfix release or a
  normal release. Suggestion: pass a flag or environment variable to
  `post-release.sh`.

### 4. Cancellation mid-flow

Three cancellation points with different cleanup needs:
a. Before any side effects: clean, no cleanup needed.
b. After local version-stamp commit but before push: skill should revert
   the commit automatically.
c. After push but before CI completes: draft release and tag exist on
   remote. Skill should offer to delete both.

### 5. Concurrent releases

What if two people try to release simultaneously? The tag creation will
fail for the second person (tag already exists). But the draft release
could be created by both. The skill should check for existing drafts
matching the version before creating one.

### 6. Version format disagreements

- Go repos: tag is `v0.5.0`, no version file (ldflags inject from tag)
- Rust repos: tag is `v0.3.0`, Cargo.toml has `0.3.0` (no `v` prefix)
- Plugin repos: tag is `v0.2.0`, manifests have `0.2.0` (no `v` prefix)

The `set-version.sh` hook receives the version without the `v` prefix.
The tag always has the `v` prefix. This convention must be documented
in the hook contract.

### 7. Reusable workflow versioning

The reusable workflow is published from shirabe. When other repos call
it via `workflow_call`, they reference a specific ref (tag or branch).
How does the workflow itself get versioned and updated across repos?
The PRD should specify whether adopting repos pin to a tag or track a
branch.


---

## Gaps the PRD Must Address (Not Covered by Exploration)

1. **Cancellation and rollback behavior** at each stage of the release
   flow. The exploration defined the happy path but not recovery.

2. **Pre-release version handling** for plugin repos where the sentinel
   check conflicts with pre-release suffixes.

3. **Hotfix releases from non-main branches** and how they interact with
   finalize-release.

4. **First release bootstrapping** when no prior tag exists.

5. **Version argument format** -- does the user pass `0.5.0` or `v0.5.0`
   to the skill? The skill should accept either and normalize.

6. **Hook contract details**: what arguments `set-version.sh` and
   `post-release.sh` receive, what environment variables are available,
   what exit codes mean.

7. **Reusable workflow versioning and adoption** -- how repos reference
   the workflow and how they're notified of updates.

8. **Draft release window behavior** -- acknowledgment that consumers
   can't see the release during the build/test phase, and that this is
   intentional.

9. **Skill output and monitoring** -- what the owner sees after triggering
   the release. Does the skill block until CI completes? Poll? Print a
   URL and exit?

10. **Concurrent release prevention** -- how the system handles two
    simultaneous release attempts for the same or different versions.
