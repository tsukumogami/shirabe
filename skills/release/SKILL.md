---
name: release
description: >-
  Release workflow. Analyzes commits to recommend a version, generates
  release notes for review, creates a draft GitHub release, dispatches
  the reusable workflow, and monitors progress. Falls back to draft +
  manual tag when no workflow is detected.
argument-hint: '[version] [--dry-run]'
---

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

### Phase 1: Version Analysis

Analyze conventional commits since the last release tag:

```bash
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
```

If no tag exists, this is the first release -- ask for version.

Count commits by prefix since `$LAST_TAG`:

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
6. **Security-labeled PRs**: Query `gh pr list --state merged --search "label:security merged:>$LAST_TAG_DATE"`.
   If found, flag them and ask the user how to handle in release notes (standard description,
   redacted, or excluded).

Report the specific failure and stop on any check.

### Phase 3: Release Notes and Version Confirmation

Generate notes, present them, and confirm the version with the user.

1. Gather commits: `git log --oneline $LAST_TAG..HEAD`
2. Gather merged PRs: `gh pr list --state merged --base main --search "merged:>$LAST_TAG_DATE"`
3. Group by type (features, fixes, other)
4. Draft user-facing notes:
   - Focus on user impact
   - One sentence per change
   - Highlight breaking changes prominently
   - Handle security-labeled PRs per user's Phase 2 decision

5. **Print the notes in chat** so the user can read them.

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

- Phases 1-3 run normally (version analysis, checks, notes + confirmation)
- Phase 4-6 are skipped (no draft, no dispatch)
- Print what would happen: which files change, what tag, what dev version

## Error Recovery

| Phase | Failure | Recovery |
|-------|---------|---------|
| 2 | Dirty tree | `git stash` or commit |
| 2 | CI failing | Fix and push |
| 2 | Tag exists | `git push --delete origin v<version>` |
| 2 | Draft exists | `gh release delete v<version> --yes` |
| 2 | Blockers open | Resolve the listed issues first |
| 4 | Draft creation fails | Check `gh auth status` |
| 5 | Dispatch fails | Check workflow exists and permissions |
| 6 | Workflow fails | `gh run view <id> --log-failed` |
| 6 | Timeout | Check URL printed at timeout |
