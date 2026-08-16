---
name: release
description: >-
  Release workflow. Analyzes commits to recommend a version, generates
  release notes for review, creates a draft GitHub release, dispatches
  the reusable workflow, and monitors progress. Falls back to draft +
  manual tag when no workflow is detected.
argument-hint: '[version] [--dry-run]'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh release 2>&1 || true`

# Release

Cut a release. Handles version selection, precondition checks, blocker
identification, release notes, draft creation, workflow dispatch, and monitoring.

## Invocation

```
/release [version] [--dry-run]
```

- **`/release`** -- analyzes commits and recommends a version
- **`/release 0.3.0`** -- uses the specified version (`v0.3.0` also accepted)
- **`/release --dry-run`** -- previews without side effects

## Phases

### Phase 1: Version Analysis and Release Contents

Establish what the release contains, once. Phase 2's security check and Phase
3's notes are both consumers of the pull request set derived here; neither
re-derives it.

```bash
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")

# The commit range the release covers. With no previous tag this is the first
# release, so the range is the whole history.
if [ -n "$LAST_TAG" ]; then
  RELEASE_RANGE="$LAST_TAG..HEAD"
else
  RELEASE_RANGE="HEAD"
fi

# The pull requests the release contains, read off that range: GitHub's squash
# merge appends "(#N)" to the commit subject.
RELEASE_PRS=$(git log --format='%s' "$RELEASE_RANGE" \
  | grep -oE '\(#[0-9]+\)$' \
  | tr -d '(#)' \
  | sort -n -u)

# Commits in the range that name no pull request: the release chore commits,
# and anything pushed straight to the base branch.
UNATTRIBUTED_COMMITS=$(git log --format='%h %s' "$RELEASE_RANGE" \
  | grep -vE '\(#[0-9]+\)$')
```

`$RELEASE_PRS` is the release's membership, computed here and nowhere else.
**Do not re-derive it from a `gh pr list --search "merged:>..."` query.** GitHub
reads a bare `merged:>YYYY-MM-DD` as "after the *end* of that day", so a
date-shaped bound silently drops every pull request merged on the previous
tag's own calendar day -- from the notes and from the security check alike. The
commit range has no boundary to get wrong, and one value with two consumers
cannot disagree with itself.

The parse assumes GitHub wrote the `(#N)` suffix, which holds while the
repository squash-merges (`allow_merge_commit` and `allow_rebase_merge` both
false, with `squash_merge_commit_title: PR_TITLE`). It is anchored to the end of
the subject, so a pull request whose own title ends in a parenthesized number is
not misread. If the assumption ever stops holding, the symptom is a crowd of
entries in `$UNATTRIBUTED_COMMITS` rather than a silently short list -- which is
what that value is for.

If no tag exists, this is the first release -- ask for version.

Count commits by prefix over `$RELEASE_RANGE`:

| Prefix | Bump signal |
|--------|------------|
| `feat!:`, `fix!:`, `BREAKING CHANGE` | major |
| `feat:` | minor |
| `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:` | patch |

Normalize version input: accept both `0.3.0` and `v0.3.0`.

### Phase 2: Precondition Checks

All must pass before proceeding:

1. **Clean working tree**: `git status --porcelain` is empty
2. **CI green on HEAD**: Check CI status using this fallback chain:
   - First try commit status: `gh api repos/{owner}/{repo}/commits/{sha}/status`
   - If state is `pending` with 0 check runs (common for squash-merge commits where
     CI ran on the PR branch, not the merge result), fall back to checking the latest
     workflow runs on the branch: `gh run list --branch main --limit 3 --json conclusion`
   - If the latest completed run has `conclusion: success`, treat as green
   - Only fail if there's an actual failure, not just missing status data
3. **No existing tag**: `git tag -l v<version>` returns empty
4. **No existing draft**: `gh release view v<version>` returns 404
5. **No release blockers**: Query `gh issue list --label blocks-release --state open`.
   If any exist, list them and stop. Also check `gh issue list --label priority:critical --state open`.
6. **Security-labeled PRs**: read the labels of every pull request in
   `$RELEASE_PRS` (Phase 1) and keep the ones carrying `security`:

   ```bash
   for pr in $RELEASE_PRS; do
     gh pr view "$pr" --json number,title,labels \
       --jq 'select(.labels[]?.name == "security") | "\(.number) \(.title)"'
   done
   ```

   The set is the one Phase 1 derived and Phase 3 writes the notes from, so a
   pull request cannot reach the notes without also reaching this check. That is
   the point: this check fails permissively -- a pull request it does not see is
   published with a standard description and nobody is prompted -- so it must not
   be reading a different, narrower set than the notes are.

   If found, flag them and use AskUserQuestion to decide how each is handled in the
   release notes, following the pattern in
   `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`. Read the PR before
   asking, and recommend one of the three treatments rather than listing them:

   - **Standard description (Recommended)** when the PR is a hardening change with
     no exploitable window in a released version
   - **Redacted** when the PR fixes a live vulnerability and the detail would arm an
     attacker before users upgrade
   - **Excluded** when naming the change at all would point at an unfixed surface

   Ground the recommendation in what the PR actually did -- cite the change and
   whether an affected version already shipped. If it is genuinely borderline, say
   so, still recommend one, and name the tiebreaker (default to the more
   conservative treatment).

Report the specific failure and stop on any check.

### Phase 3: Release Notes and Version Confirmation

Generate notes, present them, and confirm the version with the user.

1. Gather commits: `git log --oneline "$RELEASE_RANGE"`
2. The merged PRs are `$RELEASE_PRS` from Phase 1 -- the pull requests this
   release contains. No further query is needed: a squash subject already
   carries the conventional-commit type, the description, and the number, so
   step 1 has everything the notes group and write.
3. Group by type (features, fixes, other)
4. Draft user-facing notes:
   - Focus on user impact
   - One sentence per change
   - Highlight breaking changes prominently
   - Handle security-labeled PRs per user's Phase 2 decision

5. **Print the notes in chat** so the user can read them, followed by
   `$UNATTRIBUTED_COMMITS` under a short heading such as "In the release, not in
   a pull request". Every release carries at least the version-bump chore
   commit, so this is informational and does not stop the release -- it is there
   so a direct push to the base branch is something the author sees rather than
   something the pull request list quietly cannot represent.

6. **Use AskUserQuestion** to present the recommended version with
   alternatives. Include the commit analysis from Phase 1:

   > Based on 3 feat, 8 fix, and 1 breaking change since v0.2.0:
   >
   > 1. **v0.3.0 (minor) -- Recommended** because new features were added
   > 2. **v1.0.0 (major)** -- if the breaking change warrants a major bump
   > 3. **v0.2.1 (patch)** -- if the features are minor enough to treat as a patch
   > 4. **Custom version** -- enter a specific version

   If the user picks a different version than the one used to draft the
   notes, update the notes title to reflect the chosen version.

7. Allow the user to request edits to the notes before proceeding. Only
   move to Phase 4 after the user confirms both version and notes.

### Phase 4: Draft Release

Phase 3 produces the notes in chat. Before invoking `gh release
create`, persist them to `wip/release-notes-<version>.md` (per
shirabe's `CLAUDE.md` § "Intermediate Storage"; `/release` is not a
koto-driven skill, so intermediates belong in `wip/`):

```bash
gh release create "v<version>" \
  --draft \
  --title "v<version>" \
  --notes-file wip/release-notes-<version>.md
```

The draft survives workflow failures and is editable in the GitHub
UI. The `wip/` file is cleaned per the standard pre-merge wip/
cleanup convention.

### Phase 5: Workflow Dispatch

Detect the release workflow by scanning `.github/workflows/*.yml` for files
referencing `tsukumogami/shirabe/.github/workflows/release.yml` in `uses:` lines.

If found, dispatch with three inputs (version, tag, ref):

```bash
gh workflow run <workflow-file> \
  -f version=<version> \
  -f tag=v<version> \
  -f ref=main
```

**Skill-only mode**: If no release workflow found, print:

```
No release workflow detected. To complete the release:

  git tag -a v<version> -m "Release v<version>" && git push origin v<version>

Draft release with notes: <url>
```

### Phase 6: Monitoring

1. Record dispatch timestamp
2. Poll `gh run list --workflow=<name> --limit=5 --json databaseId,createdAt,status,conclusion`
   every 10 seconds
3. Use timestamp correlation to match the dispatched run (created within
   30 seconds of dispatch time)
4. Up to 5 minutes:
   - **Success**: Verify draft promoted via `gh release view v<version> --json isDraft`.
     Print release URL.
   - **Failure**: Print details. Suggest `gh run view <id> --log-failed`.
   - **Timeout**: Print run URL: "Workflow still running -- monitor at <url>"

## Dry-Run Mode

When `--dry-run` is passed:

- Phases 1-3 run normally (version analysis and release contents, checks,
  notes + confirmation). Phase 1's derivation reads git and nothing else, so it
  runs on this path unchanged.
- Phase 4-6 are skipped (no draft, no dispatch)
- Print what would happen: which files change, what tag, what dev version

## Error Recovery

| Phase | Failure | Recovery |
|-------|---------|---------|
| 1 | `$RELEASE_PRS` is empty but the range has commits | Check `$UNATTRIBUTED_COMMITS`: if every commit is listed there, the repository is not writing `(#N)` suffixes (merge strategy changed) and the derivation's assumption no longer holds |
| 2 | Dirty tree | `git stash` or commit |
| 2 | CI failing | Fix and push |
| 2 | Tag exists | `git push --delete origin v<version>` |
| 2 | Draft exists | `gh release delete v<version> --yes` |
| 2 | Blockers open | Resolve the listed issues first |
| 4 | Draft creation fails | Check `gh auth status` |
| 5 | Dispatch fails | Check workflow exists and permissions |
| 6 | Workflow fails | `gh run view <id> --log-failed` |
| 6 | Timeout | Check URL printed at timeout |
