# Maintainer Research: Error, Rollback, and Long-Term Maintenance

## Lead 1: Error and Rollback Scenarios

The Maven-style prepare-release dance has six sequential steps. Each can
fail, and each leaves the repo in a different state. The analysis below
traces through every failure point, defines the recovery path, and
identifies who performs recovery.

### The Sequence

For reference, the full happy path:

1. Skill creates draft GH release with release notes
2. Skill dispatches reusable workflow with tag/version input
3. Workflow runs `.release/set-version.sh` (stamps version files)
4. Workflow commits the version stamp
5. Workflow creates annotated tag on that commit
6. Workflow bumps to dev version (`.release/set-version.sh` with next-dev)
7. Workflow commits the dev bump
8. Workflow pushes everything (version commit, tag, dev bump commit)
9. Workflow promotes draft release to published

---

### Failure Point 1: Skill creates draft but workflow dispatch fails

**What happened.** The draft GH release exists on GitHub. The workflow
never ran. No version stamp, no tag, no commits.

**Repo state.** Clean. Main is unchanged. A draft release exists that
nobody can see (drafts are only visible to collaborators).

**Recovery.** Delete the draft release via `gh release delete <tag> --yes`.
Re-run the skill. Alternatively, fix whatever caused dispatch to fail
(permissions, workflow file not found, bad ref) and re-dispatch.

**Who recovers.** The repo owner who ran the skill. They see the dispatch
failure immediately in their terminal.

**Risk level.** Low. The draft is harmless and invisible to consumers.

---

### Failure Point 2: set-version.sh fails

**What happened.** The workflow checked out the repo and called
`.release/set-version.sh`, which exited non-zero. Maybe jq isn't
installed, the version file path changed, or the script has a bug.

**Repo state.** Clean. The workflow ran in CI, so no local changes
exist. The runner's workspace has partial modifications but they're
discarded when the job fails. Main is unchanged.

**Recovery.** Fix the set-version.sh script (or its dependencies), push
the fix to main, then re-dispatch the workflow. The draft release is
still sitting there, ready to be promoted once the workflow succeeds.

**Who recovers.** The repo owner. They see the workflow failure in the
GitHub Actions UI or via `gh run view`.

**Risk level.** Low. Nothing was committed or pushed.

**PRD requirement.** The workflow must fail fast and report which hook
failed, what exit code it returned, and the last N lines of output.
Generic "step failed" messages make debugging slow.

---

### Failure Point 3: Version committed but tag creation fails

**What happened.** The set-version commit was created locally on the
runner, but `git tag` failed. This is unlikely in practice -- git tag
creation is a local operation that only fails if the tag already exists
or there's filesystem corruption.

**Repo state.** Clean (nothing pushed yet). The commit and attempted tag
exist only on the CI runner, which is ephemeral.

**Recovery.** If the tag already exists (someone created it manually or a
previous partial run left it), delete the tag: `git push --delete origin
<tag>`. Then re-dispatch. If it's a different error, investigate on the
runner logs.

**Who recovers.** The repo owner.

**Risk level.** Very low. This failure mode is rare.

**PRD requirement.** The workflow should check for existing tags before
starting the dance, not after committing. Fail-fast validation: "tag
v1.2.3 already exists" before any mutations.

---

### Failure Point 4: Tag created but dev bump fails

**What happened.** The version stamp commit and tag were created locally.
Then set-version.sh was called again with the dev version and failed.

**Repo state.** Still clean (nothing pushed). The runner has commits and
a tag but they haven't been pushed.

**Recovery.** Same as failure point 2: fix the script, re-dispatch.

**Who recovers.** The repo owner.

**Risk level.** Low. But note: if the script works for release versions
but fails for dev versions (e.g., `-dev` suffix handling), this is a
latent bug that only manifests at release time. Testing the hook with
both release and dev versions is important.

**PRD requirement.** The hook contract should specify that set-version.sh
must handle both release versions ("1.2.3") and dev versions
("1.2.4-dev"). The workflow should document this expectation. Evals or a
dry-run mode should exercise both paths.

---

### Failure Point 5: Dev bump committed but push fails

**What happened.** All local operations succeeded: version stamp commit,
tag, dev bump commit. But `git push` failed. Common causes: branch
protection rules, RELEASE_PAT expired or missing, network timeout,
force-push protection on the tag, or someone pushed to main between
checkout and push.

**Repo state.** Clean from the remote's perspective. Main is unchanged.
No tag exists remotely. But the draft release still exists.

**Recovery depends on the cause:**

- **Expired PAT:** Rotate the secret, re-dispatch.
- **Branch protection:** The workflow needs a PAT with bypass permissions
  or the GitHub Actions bot must be exempted. Fix the protection rules
  or token, re-dispatch.
- **Concurrent push to main:** The workflow should `git pull --rebase`
  before pushing. If rebase conflicts with the version changes, manual
  intervention is needed: pull, resolve conflicts, push manually, then
  promote the draft.
- **Network timeout:** Re-dispatch. The workflow is idempotent if nothing
  was pushed.

**Who recovers.** The repo owner for re-dispatch. An org admin for PAT
rotation or branch protection changes.

**Risk level.** Medium. PAT expiration is the most common real-world
cause. It's silent until release day.

**PRD requirement.** The workflow should validate the push token early
(e.g., attempt a no-op API call to verify token validity) before starting
the commit dance. Failing after three commits but before push wastes
time and creates confusion. Also: document PAT requirements and
expiration monitoring.

---

### Failure Point 6: Push succeeds but draft release promotion fails

**What happened.** All commits and the tag are on the remote. Main has
both the version stamp and dev bump commits. The tag exists. But
`gh release edit --draft=false` failed -- maybe the draft was manually
deleted, the token lacks release permissions, or there's a GitHub API
outage.

**Repo state.** Partially complete. The tag and commits are correct. The
release exists as a draft (invisible to consumers) or doesn't exist at
all (if someone deleted it).

**Recovery:**
- If the draft still exists: run `gh release edit <tag> --draft=false`
  manually.
- If the draft was deleted: create a new release from the tag:
  `gh release create <tag> --title "<tag>" --notes-file <notes>`.
- If the tag annotation contains release notes (which it does in the
  current design): the notes can be extracted from the tag.

**Who recovers.** The repo owner. This is a one-command fix.

**Risk level.** Medium. The repo is in a correct state (tag points to
right commit, dev bump is on main) but consumers can't see the release.
The failure is visible and the fix is simple, but if nobody notices, the
release is effectively "stuck."

**PRD requirement.** The workflow should report clearly when promotion
fails: "Release v1.2.3 is ready but the draft could not be published.
Run: gh release edit v1.2.3 --draft=false". Provide the exact recovery
command in the error output.

---

### Failure Point 7: Partial push (some refs pushed, others not)

**What happened.** `git push origin main v1.2.3` partially succeeded.
Maybe the version commit and tag were pushed but the dev bump commit
wasn't (interrupted connection), or the tag was pushed but the branch
update wasn't.

**Repo state.** Depends on what got through:

- **Tag pushed, branch not updated:** The tag points to a commit that
  doesn't exist on any branch. GitHub will still show it. Consumers
  could download from it. But main doesn't have the version stamp or
  dev bump.
- **Branch updated, tag not pushed:** Main has the version stamp commit
  (and possibly dev bump) but no tag. No release can be created.
- **Version commit pushed, dev bump not:** Main has the release version
  but not the dev bump. The sentinel CI check will catch this on the
  next PR.

**Recovery.** Depends on the partial state. The simplest approach:

1. Check what exists remotely: `git ls-remote origin v1.2.3`, `git log origin/main`.
2. Push whatever is missing: `git push origin main`, `git push origin v1.2.3`.
3. If the dev bump is missing, run set-version.sh locally with the dev
   version, commit, push.

**Who recovers.** The repo owner. Requires git knowledge to diagnose.

**Risk level.** Low probability but high confusion when it happens.

**PRD requirement.** The workflow should push branch and tag separately
and report the result of each. If one fails, the error message should
state what was pushed and what wasn't. Consider pushing the tag last
(since tag push triggers downstream workflows in some setups), so a
failed tag push means "branch is updated, just push the tag manually."

The push order should be: (1) branch with all commits, (2) tag. This
ensures that if the tag push triggers a release workflow in the caller
repo, the commits are already on the branch.

---

### Failure Point 8: Everything succeeds but the release is bad

**What happened.** The release is live. Consumers can see it. But
something is wrong: a bug in the code, wrong version stamped, release
notes have errors, or the wrong commit was tagged.

**Recovery options, in order of severity:**

1. **Release notes wrong:** Edit via `gh release edit <tag> --notes-file
   corrected-notes.md`. No code changes needed.

2. **Minor bug discovered:** Fix it and release a patch (v1.2.4). Don't
   yank v1.2.3 unless it's actively harmful.

3. **Wrong commit tagged:** Delete the tag and release, fix the issue,
   re-release. Steps:
   ```
   gh release delete v1.2.3 --yes
   git push --delete origin v1.2.3
   git tag -d v1.2.3
   # Fix the issue, then re-run the release
   ```
   This is safe as long as nobody has already consumed the release.
   GitHub's API returns 404 for deleted releases, which is a clean
   failure for consumers.

4. **Critical security issue:** Same as (3) but with urgency. Mark the
   release as pre-release first (`gh release edit --prerelease`) to
   signal "don't use this" before deleting.

5. **Version-file corruption (wrong version stamped):** The dev bump
   commit on main might have the wrong next-dev version. Fix with a
   manual commit. The sentinel CI check will catch it on the next PR.

**Who recovers.** The repo owner for all cases.

**Risk level.** Varies. Release note typos are trivial. Wrong-commit
tags require careful git surgery.

**PRD requirement.** Document the "yank a release" procedure. The system
should not try to automate yanking -- it's rare enough that manual
recovery is appropriate. But the procedure should be documented and
tested.

---

### Failure Point 9: Reusable workflow itself has a bug

**What happened.** Shirabe publishes the reusable workflow. A caller repo
(koto, tsuku, niwa) calls it via `@v1`. The workflow has a bug that
causes it to fail mid-dance, or worse, to push incorrect commits.

**Impact radius.** Every caller repo that uses `@v1` is affected. If the
bug is in the push logic, it could push wrong commits to callers' main
branches.

**Recovery options:**

1. **Callers pin to SHA or exact tag:** Not affected by workflow updates.
   Recovery is to wait for the fix and update the pin.

2. **Callers use floating `@v1` tag:** Affected immediately. Recovery
   depends on the bug:
   - If the workflow fails cleanly (no mutations pushed): callers wait
     for the fix, then re-run.
   - If the workflow pushed bad commits: callers must revert those
     commits manually. This is the worst case.

3. **Rolling back the workflow:** Shirabe force-pushes the `v1` tag back
   to the previous good commit. This is instant for all callers on `@v1`.
   But it's a destructive operation that's hard to communicate.

**Who recovers.** The shirabe maintainer fixes the workflow. Each caller
repo owner may need to clean up their repo if bad commits were pushed.

**Risk level.** High impact, low probability. The workflow is small and
auditable, but bugs in release infrastructure have outsized consequences.

**PRD requirements:**

- **Dry-run mode is mandatory.** Every workflow invocation should support
  a `dry-run: true` input that performs all steps except push and
  release promotion. This lets callers test the workflow against their
  repo without risk.

- **Callers should be able to pin to exact tags.** Document both `@v1`
  (convenient) and `@v1.2.3` (safe) pinning strategies. Don't
  recommend `@v1` as the only option.

- **The workflow must never force-push.** All pushes should be
  fast-forward only. If the push would require force, fail and let the
  human decide.

- **Changelog for workflow changes.** Since the workflow is
  infrastructure, callers need to know what changed. Workflow releases
  should have release notes like any other software.

---

## Lead 2: Long-Term Maintenance

### Versioning the Reusable Workflow

The workflow lives in shirabe's `.github/workflows/` directory and is
versioned with shirabe's git tags. This means the workflow version is
tied to shirabe's release cadence.

**Recommended approach:** Semver tags with floating major tags.

- Exact tags: `v1.0.0`, `v1.1.0`, `v1.2.0`
- Floating major tag: `v1` (force-updated to latest v1.x.y)
- Breaking changes get a new major: `v2`

This matches the established pattern used by actions/checkout,
hashicorp/ghaction-terraform-provider-release, and others.

**Coupling concern:** Shirabe's version (the plugin) and the workflow
version are the same. A plugin-only change (new skill, updated template)
bumps the tag, which changes the workflow ref even though the workflow
didn't change. This is benign for callers on `@v1` (they get the same
workflow code) but could confuse callers on exact pins who see a new
version and wonder what changed.

**PRD requirement:** The release notes should clearly state whether a
release includes workflow changes, plugin-only changes, or both. A
section header like "Workflow changes" or "No workflow changes in this
release" makes this explicit.

### Testing the Workflow

Testing a reusable release workflow without cutting real releases is the
hardest maintenance challenge.

**Options:**

1. **Dry-run mode.** The workflow accepts `dry-run: true` which skips
   push and release promotion. This tests the version stamping, commit
   creation, and tag creation in a sandbox. The workflow should output
   what it *would* have pushed.

2. **Test repo.** A dedicated repo (e.g., `tsukumogami/release-test`)
   that exists solely for testing the workflow. Real tags are created
   and deleted. Releases are created as drafts and deleted. This tests
   the full path including push and API calls.

3. **Act (local runner).** `nektos/act` can run GitHub Actions locally.
   It's imperfect (doesn't support all features, especially
   `workflow_call`) but useful for syntax validation and basic step
   testing.

4. **Branch-based testing.** The workflow can be called from a branch
   ref during development: `@feature/fix-push-logic`. Callers testing
   the fix reference the branch, verify it works, then the fix is
   merged and tagged.

**PRD requirement:** The workflow must support dry-run mode. A test repo
is recommended but not required for the initial version. The dry-run
output should be detailed enough to verify correctness without actually
pushing.

### Breaking Changes in the Workflow

When the workflow changes in a breaking way (input removed, renamed, or
semantics changed), callers on the old major version must not break.

**Protocol:**

1. Identify the breaking change during development.
2. Implement the change behind a new major version.
3. Release the new major version with migration docs.
4. Keep the old major version tag pointing at the last compatible
   release. Don't delete it.
5. Callers migrate at their own pace.

**What counts as breaking:**

- Removing or renaming an input
- Changing the semantics of an existing input (e.g., `version` used to
  accept "v1.2.3" and now only accepts "1.2.3")
- Changing the commit message format (callers may grep for it)
- Changing the tag format
- Adding a required input (callers not passing it will fail)
- Changing the hook contract (different script paths or arguments)

**What's not breaking:**

- Adding an optional input with a default
- Adding a new output
- Fixing a bug (unless callers depend on the buggy behavior)
- Improving error messages

**PRD requirement:** The hook contract (script paths, argument format,
environment variables) is a public API. Changes to it are breaking.
Document it as such.

### Documentation

The reusable release system needs documentation at three levels:

1. **Caller quickstart.** How to adopt the system in a new repo. What
   files to create, what workflow to reference, what secrets to
   configure. A copy-paste-ready caller workflow YAML. This is the most
   important doc -- it determines adoption friction.

2. **Hook contract reference.** What set-version.sh receives, what it
   must do, what exit codes mean. What post-release.sh receives. What
   environment variables are available. Examples for each repo type
   (Go, Rust, Claude Code plugin).

3. **Recovery procedures.** For each failure point above, the exact
   commands to diagnose and recover. This doc is the safety net when
   things go wrong at midnight.

**PRD requirement:** The quickstart and hook contract reference are
required for the initial release. Recovery procedures can follow, but
the PRD should specify them as a deliverable.

---

## Summary of PRD Requirements

These requirements emerged from the failure analysis and should be
specified in the PRD:

### Error Handling

1. **Fail-fast validation.** Check tag existence, token validity, and
   hook script presence before starting the commit dance.
2. **Actionable error messages.** Every failure must include: what
   failed, what state the repo is in, and the exact command to recover.
3. **Separate push reporting.** Report branch push and tag push results
   independently so partial push states are diagnosable.
4. **Push order.** Branch first, tag second. This ensures the tagged
   commit is reachable from the branch before any tag-triggered
   workflows run.

### Recovery

5. **Draft release survives failures.** The draft-then-promote pattern
   means the release notes are preserved across retries. The workflow
   should detect an existing draft and reuse it rather than failing on
   "release already exists."
6. **Idempotent re-runs.** If the workflow is dispatched again after a
   failure, it should detect what already happened (tag exists? version
   commit already on main?) and resume from the right point. Full
   idempotency may be out of scope for v1, but at minimum the workflow
   should not fail on "tag already exists" if the tag points to the
   expected commit.
7. **Document the yank procedure.** Don't automate it, but specify
   the manual steps for deleting a release and tag.

### Workflow Safety

8. **Dry-run mode.** A `dry-run` input that exercises all steps except
   push and promotion. Required for testing.
9. **No force-push.** All pushes must be fast-forward. Fail if
   fast-forward is not possible.
10. **Pinning support.** Document both floating (`@v1`) and exact
    (`@v1.2.3`) pinning. Don't default examples to `@main`.

### Hook Contract

11. **Dual-mode testing.** set-version.sh must work for both release
    versions ("1.2.3") and dev versions ("1.2.4-dev"). The workflow
    should document this expectation.
12. **Hook contract is a public API.** Changes to script paths,
    arguments, or environment variables are breaking changes and
    require a major version bump.

### Maintenance

13. **Release notes differentiate workflow vs plugin changes.** Callers
    need to know whether a new shirabe release affects them.
14. **Breaking change protocol.** New major version for breaking
    workflow changes. Old major tag preserved indefinitely.
15. **Caller quickstart documentation.** Copy-paste-ready adoption
    guide is a required deliverable.
16. **Recovery procedure documentation.** Per-failure-point recovery
    commands are a required deliverable.
