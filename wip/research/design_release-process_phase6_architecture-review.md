# Architecture Review: release-process

## 1. Is the architecture clear enough to implement?

**Verdict: Yes, with two areas needing clarification.**

The design specifies the three components (skill pre-tag hook, release.yml,
check-sentinel.yml), their interactions, data flow, and interfaces with enough
precision for implementation. The manifest JSON paths are explicit, the sentinel
value is defined, and the phased implementation plan gives a clear order of work.

### Clarifications needed

**Race condition on finalize-release**: The design says finalize-release checks
out main and pushes a sentinel-reset commit. If a PR merges to main between the
release commit push and the finalize-release job, the finalize job will either
fail to push (if main has diverged) or produce a merge conflict. The design
should specify that finalize-release does a `git pull --rebase` before pushing,
or uses `--force-with-lease` scoped to the expected HEAD. This is a real
scenario: the /release skill pushes a commit to main, then the tag-triggered
workflow takes several seconds to start, during which another PR could merge.

Koto's finalize-release avoids this because it uses `sed` on a specific file
and pushes -- but koto's window is also narrow. Shirabe doesn't release often,
so the practical risk is low, but the design should acknowledge it and specify
the merge strategy.

**Where does the pre-tag hook live?** The design says the /release skill "gains
a pre-tag step" and "detects shirabe by checking for `.claude-plugin/plugin.json`
existence." Phase 3's execute reference (`phase-3-execute.md`) shows the current
/release skill has no hook mechanism -- it goes straight from tag creation to
push. The design should clarify whether the hook is:

(a) Hardcoded in the /release skill's phase-3 reference doc with a conditional
check, or
(b) A new extensibility mechanism in the skill (e.g., a `pre-tag.sh` script the
skill looks for in the repo root).

Option (a) is simpler and sufficient. Option (b) is more general but adds
design scope. The doc implies (a) but doesn't state it explicitly.

## 2. Are there missing components or interfaces?

**Two gaps identified.**

### Gap 1: Version string format inconsistency

The design uses `v<major>.<minor>.<patch>` for tag format (e.g., `v0.3.0`) but
the manifest version fields currently contain `0.2.0` (no `v` prefix). The
commit message says `chore(release): set version to v<version>`, and the
sentinel is `0.0.0-dev` (no `v`). The design needs to state explicitly whether
the manifest version field includes the `v` prefix or not.

Looking at the koto release.yml, the tag is `v0.x.y` while Cargo.toml version
is `0.x.y` (no prefix). The convention is: tags have `v`, version fields don't.
The design should state this -- the `jq` command that stamps the version must
strip the `v` prefix from the tag name before writing to the manifest. The
current wording ("replaces `0.0.0-dev` with the release version") is ambiguous
about whether "release version" means `v0.3.0` or `0.3.0`.

### Gap 2: No rollback procedure

The design covers the happy path thoroughly but doesn't address what happens
if the release workflow's finalize-release job fails (e.g., PAT expired, push
rejected). Main would be stuck with the real version instead of `0.0.0-dev`,
and the sentinel CI check would block subsequent PRs that touch
`.claude-plugin/`. The design should document:

- How to manually reset the sentinel (trivial, but should be documented).
- Whether to retry the finalize-release job or fix manually.

This isn't a design flaw -- it's a documentation gap. The design already covers
error handling for tag creation and push failures in the skill, but not for
the CI-side finalize job.

## 3. Are the implementation phases correctly sequenced?

**Yes. The sequencing is correct and well-reasoned.**

Phase 1 (sentinel bootstrap) is the right starting point: it establishes the
invariant that all subsequent phases depend on. Without the sentinel on main,
the pre-tag hook has nothing to search-and-replace, and the CI check has
nothing to validate.

Phase 2 (release.yml) before Phase 3 (skill integration) is correct because
the workflow must exist before the skill can push tags that trigger it. The
workflow can be tested with a manually-created tag in Phase 2, independent of
the skill.

Phase 3 (skill integration) depends on both Phase 1 (sentinel exists to
replace) and Phase 2 (workflow exists to respond to tags).

Phase 4 (first release) is a natural end-to-end validation.

**One minor suggestion**: Phase 1 could be split into two PRs -- one for the
manifest changes (switching to `0.0.0-dev`) and one for the CI check. This
lets the manifest change merge without waiting for script review. But this is
optional; a single PR works fine given the small scope.

## 4. Are there simpler alternatives we overlooked?

### Alternative A: Tag-only versioning (no sentinel)

Skip the sentinel entirely. Manifests on main always contain the last released
version (e.g., `0.2.0`). The /release skill still stamps the new version before
tagging. The finalize-release job is eliminated. The check-sentinel workflow is
eliminated.

**Why it could work:** The marketplace reads the version at the tagged commit.
As long as each new tag has a higher version, updates are detected. The version
on main doesn't matter -- nobody reads it from the default branch.

**Why the design rejects it (correctly):** Without the sentinel, version drift
is possible. A developer could bump the version in a PR (as happened already --
manifests say 0.2.0 with only a v0.1.0 tag). The sentinel prevents this class
of error. The added complexity (two extra commits, one CI check) is modest for
the protection it provides. The design's choice is sound.

### Alternative B: GitHub Actions workflow_dispatch for the entire release

The user triggers a workflow_dispatch with a version input. The workflow stamps
manifests, commits, tags, creates the release, and resets. Everything is
server-side.

**Why it could work:** No local pre-tag hook complexity. The skill becomes
simpler (just validates and triggers the workflow). Avoids the "commit then
tag" local dance.

**Why the design rejects it (correctly):** Multi-paragraph release notes are
awkward as workflow inputs. Local dry-run testing is impossible. It splits
release logic between skill and workflow. The design's reasoning is solid here.

### Alternative C: Use a GitHub App instead of PAT

Replace the RELEASE_PAT with a GitHub App installation token. Apps have
more granular permissions and don't expire like PATs (they auto-rotate).

**Assessment:** This is a genuine improvement over PAT-based auth but adds
setup complexity (creating the app, installing it, managing the private key).
Not worth it for a single repo with infrequent releases. Worth noting as a
future improvement if the org standardizes on Apps for CI.

### Alternative D: Commit version on release branch, merge to main

Instead of committing the version stamp directly to main, create a temporary
branch, commit the stamp there, tag it, then merge to main and clean up. After
merge, main would have the real version momentarily, then finalize-release
resets it.

**Assessment:** This is strictly more complex than the chosen approach. It
buys you nothing -- the version stamp commit on main is harmless and gets
squashed in history anyway. The design correctly rejected the release branch
approach.

## Summary of Recommendations

| # | Category | Severity | Recommendation |
|---|----------|----------|----------------|
| 1 | Clarity | Medium | Specify merge strategy for finalize-release when main has diverged |
| 2 | Clarity | Medium | Explicitly state whether manifest version includes `v` prefix |
| 3 | Clarity | Low | Clarify where the pre-tag hook lives (skill reference doc vs. extensibility mechanism) |
| 4 | Completeness | Low | Document rollback procedure if finalize-release fails |
| 5 | Phasing | Low | Consider splitting Phase 1 into manifest change + CI check PRs (optional) |

None of these are blocking. The design is implementable as written -- these
items reduce ambiguity and improve resilience documentation.
