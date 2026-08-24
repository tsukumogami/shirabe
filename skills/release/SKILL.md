---
name: release
description: >-
  Cut a release properly: work out the version from what actually landed,
  derive the change set from the commit range, check for blockers, write notes
  someone would want to read, and drive the release out. Use it whenever a
  version is about to move — "cut a release", "ship 0.19", "tag a new
  version", "publish the new version", "bump the version", "write the
  changelog", "what's changed since the last release?", "is this ready to
  release?". Do NOT do any of it by hand instead: hand-tagging, editing a
  version string directly, writing notes off `git log`, or calling `gh release
  create` yourself skips the blocker check and gets the contents wrong,
  because a search for merged pull requests returns work the release does not
  contain and only the commit range is correct. This is releasing a version,
  not merging a change — shipping one piece of work is `/work-on`.
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

# The commit range the release covers. An empty LAST_TAG is the first release.
# The guard is load-bearing: "..HEAD" is a range git ACCEPTS, and it resolves to
# zero commits, so without it a first release derives an empty set silently
# rather than failing.
if [ -n "$LAST_TAG" ]; then
  RELEASE_RANGE="$LAST_TAG..HEAD"
else
  RELEASE_RANGE="HEAD"
fi

# Later phases run as separate shell invocations, so the derivation is written
# to files rather than left in variables: a shell variable set here is gone by
# the time Phase 2 runs, and an empty list there would pass the security check
# by finding nothing. These three files ARE the release's membership.
mkdir -p wip
printf '%s\n' "$RELEASE_RANGE" > wip/release-range.txt

# The pull requests the release contains: GitHub's squash merge appends "(#N)"
# to the commit subject. grep exits 1 when nothing matches, which is a legal
# outcome here rather than a failure, so it is guarded.
git log --format='%s' "$RELEASE_RANGE" \
  | { grep -oE '\(#[0-9]+\)$' || true; } \
  | tr -d '(#)' \
  | sort -n -u > wip/release-prs.txt

# Commits in the range that name no pull request: the release chore commits,
# and anything pushed straight to the base branch.
git log --format='%h %s' "$RELEASE_RANGE" \
  | { grep -vE '\(#[0-9]+\)$' || true; } > wip/release-unattributed.txt

echo "Release range: $RELEASE_RANGE"
echo "Pull requests in the release: $(wc -l < wip/release-prs.txt)"
echo "In the release, not in a pull request:"
cat wip/release-unattributed.txt
```

`wip/release-prs.txt` is the release's membership, computed here and nowhere
else; Phase 2 and Phase 3 read it. **Do not re-derive it from a `gh pr list
--search "merged:>..."` query**, for two reasons that compound. GitHub reads a
bare `merged:>YYYY-MM-DD` as "after the *end* of that day", so a date-shaped
bound silently drops every pull request merged on the previous tag's own
calendar day. And `merged:>` has no upper bound at all, so it also credits
anything merged *after* the release point -- against `v0.16.0` with a release
point of `v0.17.0` it returns 18 pull requests where the range holds 13. The
commit range has both bounds and no date semantics to get wrong.

The parse assumes GitHub wrote the `(#N)` suffix. That holds while the
repository squash-merges (`allow_merge_commit` and `allow_rebase_merge` both
false, with `squash_merge_commit_title: PR_TITLE`) -- a live repository setting,
not something this file can enforce, and one an adopting repository may not
share. The pattern is anchored to the end of the subject, so a pull request
whose own title ends in a parenthesized number is not misread.

The unattributed list printed above is what makes that assumption checkable
rather than assumed. A handful of entries is normal: every release carries the
version-bump chore commit. A list that is suddenly most of the range means the
suffix is no longer being written -- the merge strategy changed, or work is
landing by direct push -- and the pull request set is incomplete. Stop and
reconcile by hand before releasing when that happens; it is the one signal that
the derivation has gone quiet rather than empty. Printing it here, before the
notes are drafted, is also what makes it useful rather than a footnote.

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
6. **Security-labeled PRs**: read the labels of every pull request Phase 1
   derived and keep the ones carrying `security`:

   ```bash
   while read -r pr; do
     gh pr view "$pr" --json number,title,labels \
       --jq 'select([.labels[].name] | index("security")) | "\(.number) \(.title)"' \
       || echo "UNRESOLVED #$pr: in the release range but not a pull request in this repo"
   done < wip/release-prs.txt
   ```

   The set is the one Phase 1 derived and Phase 3 writes the notes from, so a
   pull request cannot reach the notes without also reaching this check. That is
   the point: this check fails permissively -- a pull request it does not see is
   published with a standard description and nobody is prompted -- so it must not
   be reading a different, narrower set than the notes are.

   The `|| echo` is not decoration. A `(#N)` suffix can name something that is
   not a pull request in this repository: a revert, a hand-written subject, or a
   commit cherry-picked from elsewhere. `gh pr view` exits non-zero on those, and
   without the branch the number would be skipped in silence -- which is the
   failure mode this whole check exists to close. Treat any `UNRESOLVED` line as
   something to look at by hand before releasing, not as a pass.

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
   whether an affected version already shipped. Name the tiebreaker every time,
   not only when the call is close: **default to the more conservative
   treatment**. State it even when the call reads as clear-cut, and say that it
   did. A reader cannot tell from a recommendation alone whether it was near the
   line, so the rule that produced it is part of the recommendation; and the one
   case where the tiebreaker matters most is the one where the recommending
   agent was most confident it did not.

Report the specific failure and stop on any check.

### Phase 3: Release Notes and Version Confirmation

Generate notes, present them, and confirm the version with the user.

1. Gather commits: `git log --oneline "$(cat wip/release-range.txt)"`. Each
   subject carries the conventional-commit type, the description, and the `(#N)`
   suffix, so this one read has everything the notes are written from.
2. Cross-check against `wip/release-prs.txt` from Phase 1 -- the release's
   membership. Every number in that file must appear in a subject step 1
   gathered, and no other pull request may be credited. It is a check, not a
   second gather: the file was derived from this same range, so a disagreement
   means one of the two reads went wrong and the notes should not be written
   until you know which.
3. Group by type (features, fixes, other)
4. Draft user-facing notes:
   - Focus on user impact
   - One sentence per change
   - Highlight breaking changes prominently
   - Handle security-labeled PRs per user's Phase 2 decision

5. **Print the notes in chat** so the user can read them, followed by
   `cat wip/release-unattributed.txt` under a short heading such as "In the
   release, not in a pull request". Phase 1 already printed this list; repeating
   it here puts it in front of the author at the moment they are deciding
   whether the notes are complete.

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
UI. This file and Phase 1's three release-contents files
(`wip/release-range.txt`, `wip/release-prs.txt`,
`wip/release-unattributed.txt`) are cleaned per the standard
pre-merge wip/ cleanup convention.

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
| 1 | `wip/release-prs.txt` is empty but the range has commits | Read `wip/release-unattributed.txt`: if every commit is listed there, the repository is not writing `(#N)` suffixes (the merge strategy changed) and the derivation's assumption no longer holds |
| 1 | `wip/release-range.txt` holds `HEAD` on a repo that has tags | `git describe` found no `v*` tag from this commit -- check you are on the release branch and that tags are fetched (`git fetch --tags`) |
| 2 | `UNRESOLVED #N` from the security check | The `(#N)` names something that is not a pull request here (a revert, a hand-written subject, a cherry-pick). Check it by hand before releasing |
| 2 | Dirty tree | `git stash` or commit |
| 2 | CI failing | Fix and push |
| 2 | Tag exists | `git push --delete origin v<version>` |
| 2 | Draft exists | `gh release delete v<version> --yes` |
| 2 | Blockers open | Resolve the listed issues first |
| 4 | Draft creation fails | Check `gh auth status` |
| 5 | Dispatch fails | Check workflow exists and permissions |
| 6 | Workflow fails | `gh run view <id> --log-failed` |
| 6 | Timeout | Check URL printed at timeout |
