---
name: release
description: >-
  Single-command release workflow. Analyzes conventional commits to recommend a
  version bump, validates preconditions, generates release notes for review,
  creates a draft GitHub release, dispatches the reusable release workflow, and
  monitors progress. Works with any repo that adopts the shirabe release
  workflows. Falls back to skill-only mode (draft + manual tag) when no
  workflow is detected. Use when cutting a release: "release 0.3.0", "release",
  "cut a new version".
argument-hint: '[version] [--dry-run]'
---

# Release Skill

Cut a release with a single command. The skill handles version selection,
precondition checks, release notes, draft creation, workflow dispatch, and
monitoring. It works with repos that have adopted the shirabe reusable release
workflows and falls back gracefully for repos that haven't.

## Invocation

```
/release [version] [--dry-run]
```

- **`/release`** -- analyzes commits and recommends a version
- **`/release 0.3.0`** -- uses the specified version (accepts `v0.3.0` too)
- **`/release --dry-run`** -- previews the release without side effects

## Workflow

### Phase 1: Version Selection

If no version argument is provided, analyze conventional commits since the last
release tag to recommend a bump level:

```bash
# Find last release tag
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")

# If no tag exists, this is the first release
if [ -z "$LAST_TAG" ]; then
  # Offer empty editor for first release notes
  echo "No previous release found. This will be the first release."
  # Ask user for version
fi
```

Count commits by conventional commit prefix since `$LAST_TAG`:

| Prefix | Bump signal |
|--------|------------|
| `feat!:`, `fix!:`, `BREAKING CHANGE` | major |
| `feat:` | minor |
| `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:` | patch |

Present the analysis:

```
Since v0.2.0 (14 commits):
  3 feat:  (minor signal)
  8 fix:   (patch signal)
  2 docs:  (no bump)
  1 feat!: (major signal)

Recommended: v0.3.0 (minor)

Release as v0.3.0? [enter version or Y to accept]
```

The user confirms or overrides. The version argument accepts both `0.3.0` and
`v0.3.0` forms -- normalize internally to separate the bare version (`0.3.0`)
and the tag (`v0.3.0`).

### Phase 2: Precondition Checks

Validate before any side effects:

1. **Clean working tree**: `git status --porcelain` must be empty
2. **CI green on HEAD**: Query `gh api repos/{owner}/{repo}/commits/{sha}/status`
   and check for `state: success`
3. **No existing tag**: `git tag -l v<version>` must return empty
4. **No existing draft release**: `gh release view v<version>` must return 404

If any check fails, report the specific failure and stop. Don't proceed
with partial checks -- all must pass.

### Phase 3: Release Notes

Generate notes from commits and PRs since the last release:

1. Gather commits: `git log --oneline $LAST_TAG..HEAD`
2. Gather merged PRs: `gh pr list --state merged --base main --search "merged:>$LAST_TAG_DATE"`
3. Group by conventional commit type (features, fixes, other)
4. Draft user-facing notes following the release-planning style guide:
   - Focus on user impact, not implementation details
   - One sentence per change
   - Highlight breaking changes prominently
5. Present the draft for user review and editing

The user can edit, approve, or regenerate the notes.

### Phase 4: Draft Release Creation

Create a draft GitHub release with the reviewed notes:

```bash
gh release create "v<version>" \
  --draft \
  --title "v<version>" \
  --notes-file /tmp/release-notes-<version>.md
```

The draft is the persistent artifact -- it survives workflow failures and
is editable in the GitHub UI. It also serves as the data channel: the
reusable workflow reads the notes from the draft rather than receiving
them as a workflow input.

### Phase 5: Workflow Dispatch

Detect the release workflow by scanning `.github/workflows/*.yml` for files
containing a reference to the shirabe reusable release workflow (look for
`tsukumogami/shirabe/.github/workflows/release.yml` in `uses:` lines).

If found, dispatch it:

```bash
gh workflow run <workflow-file> \
  -f version=<version> \
  -f tag=v<version> \
  -f ref=main
```

Three inputs only. The draft release already holds the notes. The `dry-run`
and `dev-suffix` inputs exist on the workflow for manual dispatch from the
GitHub UI but the skill doesn't use them -- dry-run is handled locally by the
skill (Phase 0), and dev-suffix uses the workflow's default.

**Skill-only mode**: If no release workflow is found in `.github/workflows/`,
skip dispatch and print manual instructions:

```
No release workflow detected. To complete the release:

  git tag -a v<version> -m "Release v<version>" && git push origin v<version>

The draft release with your notes is ready at: <url>
```

### Phase 6: Monitoring

After dispatch, monitor the workflow run:

1. Record the dispatch timestamp
2. Poll `gh run list --workflow=<name> --limit=5 --json databaseId,createdAt,status,conclusion`
   every 10 seconds
3. Use timestamp correlation to match the dispatched run (created within 30
   seconds of dispatch time)
4. While polling (up to 5 minutes):
   - Print status updates: "Workflow queued...", "Workflow in progress..."
   - **On success**: Verify draft was promoted via
     `gh release view v<version> --json isDraft`. Print release URL.
   - **On failure**: Print failure details. Suggest
     `gh run view <id> --log-failed`.
   - **On timeout** (still running after 5 minutes): Print the workflow run
     URL and exit gracefully:
     "Workflow still running -- monitor at <url>"

The 5-minute window covers simple repos (plugins, config). Build-heavy repos
(tsuku, koto) will typically time out, and the user checks the GitHub UI.

## Dry-Run Mode

When `--dry-run` is passed:

1. Run Phase 1 (version selection) normally
2. Run Phase 2 (precondition checks) normally
3. Run Phase 3 (note generation) normally -- show the draft
4. **Skip** Phase 4 (don't create the draft)
5. **Skip** Phase 5 (don't dispatch the workflow)
6. Print a summary of what would have happened:

```
DRY-RUN: Would create draft release v0.3.0 with the notes above.
DRY-RUN: Would dispatch <workflow-file> with:
  version=0.3.0 tag=v0.3.0 ref=main
DRY-RUN: The workflow would:
  - Call .release/set-version.sh 0.3.0
  - Commit and tag v0.3.0
  - Call .release/set-version.sh 0.3.1-dev
  - Commit and push
```

## Error Recovery

Each phase has a specific recovery path:

| Phase | Failure | Recovery |
|-------|---------|---------|
| 2 | Dirty working tree | `git stash` or commit changes |
| 2 | CI failing | Fix CI, push, wait for green |
| 2 | Tag exists | Delete tag: `git push --delete origin v<version>` |
| 2 | Draft exists | Delete draft: `gh release delete v<version> --yes` |
| 4 | Draft creation fails | Check `gh auth status`, retry |
| 5 | Dispatch fails | Check workflow file exists, check permissions |
| 6 | Workflow fails | `gh run view <id> --log-failed`, fix and re-dispatch |
| 6 | Workflow timeout | Check URL printed at timeout |

## Interaction with Existing Skills

This skill replaces both `/prepare-release` and `/release` from the org-level
tools. It combines preparation (note generation, checklist) and execution
(dispatch, monitoring) into a single command. The draft GitHub release replaces
the checklist issue as the persistent tracking artifact.
