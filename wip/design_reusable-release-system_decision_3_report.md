<!-- decision:start id="release-skill-interface" status="assumed" -->
### Decision: Release Skill Interface

**Context**

The reusable release system needs a skill that runs locally in Claude Code and orchestrates the human side of a release: version selection, precondition checks, note generation, draft creation, workflow dispatch, and status reporting. The skill replaces the current two-command split (/prepare-release + /release) with a single /release [version] command.

Three tensions shape the interface design. First, the skill dispatches a workflow_dispatch workflow but `gh workflow run` doesn't return a run ID, making correlation between "what I dispatched" and "what's running" unreliable. Second, repos range from zero-build (shirabe, just a manifest) to 20+ minute builds (tsuku, Go + Rust + GPU), so monitoring that blocks the terminal indefinitely is impractical. Third, the skill must work without any workflow at all (PRD R13), so the interface can't assume a workflow exists.

**Assumptions**

- `gh workflow run` will continue to not return a run ID. If GitHub CLI adds this capability, the correlation logic simplifies but the design still works.
- Workflows triggered by the skill complete within 5 minutes for simple repos (plugin, config-only). Build-heavy repos may take longer.
- The reusable workflow is discoverable by scanning `.github/workflows/` for a file referencing the shirabe release workflow path.

**Chosen: Dispatch-then-Monitor with Graceful Degradation**

The skill interface works as follows:

**Invocation**: `/release [version]`. If version is omitted, the skill analyzes conventional commit prefixes since the last release tag (found via `git describe --tags --abbrev=0 --match 'v*'`) and recommends a bump level. The user confirms or overrides. The version argument accepts both `v0.3.0` and `0.3.0` forms; the skill normalizes internally.

**Precondition checks (PRD R7)**: Before any side effects, the skill validates:
- Clean working tree (`git status --porcelain` is empty)
- CI green on HEAD (`gh api repos/{owner}/{repo}/commits/{sha}/status`)
- No existing git tag for the version (`git tag -l v<version>`)
- No existing draft release for the version (`gh release view v<version>` returns 404)

**Note generation and draft creation (PRD R4, D2)**: The skill gathers commits and PRs since the last release, synthesizes user-facing release notes following the release-planning skill's style guide, presents them for review, and creates a draft GitHub release via `gh release create v<version> --draft --title "v<version>" --notes-file <path>`. The draft is the persistent artifact -- it survives workflow failures and can be edited in the GitHub UI.

**Workflow dispatch**: The skill detects the release workflow by scanning `.github/workflows/*.yml` for a file containing a reference to the reusable release workflow (or a `release` named workflow with `workflow_dispatch` trigger). It dispatches with three inputs:

```
gh workflow run <workflow-file> \
  -f version=0.3.0 \
  -f tag=v0.3.0 \
  -f ref=main
```

No other inputs are needed. The workflow finds the draft release by tag name. The `dry-run` input exists on the workflow for manual dispatch from the GitHub UI, but the skill implements dry-run locally (preview what would happen without dispatching).

**Monitoring**: After dispatch, the skill polls `gh run list --workflow=<name> --limit=5 --json databaseId,createdAt,status,conclusion` every 10 seconds for up to 5 minutes. It identifies the triggered run by timestamp proximity (created within 30 seconds of dispatch time). While polling:
- Prints status updates inline ("Workflow queued...", "Workflow in progress...")
- On success within 5 minutes: verifies the draft was promoted (`gh release view v<version> --json isDraft`), prints the release URL, reports success
- On failure within 5 minutes: prints the failure details and suggests `gh run view <id> --log-failed`
- On timeout (still running after 5 minutes): prints the workflow URL and exits gracefully: "Workflow still running -- monitor at <url>"

**Skill-only mode (PRD R13)**: If no release workflow is found, the skill creates the draft release and prints: "No release workflow detected. To complete the release, tag and push manually: `git tag -a v0.3.0 -m 'Release v0.3.0' && git push origin v0.3.0`". The draft release with curated notes is still valuable on its own.

**Dry-run**: The `--dry-run` flag runs all phases (version recommendation, precondition checks, note generation) but stops before creating the draft or dispatching. It prints what would happen: which files the workflow would stamp, what tag would be created, what the draft release body would contain.

**Rationale**

The 5-minute monitoring window with graceful degradation solves the terminal-blocking problem for repos with heavy builds while still providing in-terminal feedback for the common case. Most release workflows for this ecosystem (plugin manifests, small Go/Rust binaries) complete in under 2 minutes. The tsuku monorepo's multi-platform build is the outlier, and printing a URL after 5 minutes is acceptable there.

Timestamp-based run correlation is imperfect but sufficient. The 30-second window plus retry-with-polling is more reliable than the existing skill's single-shot sleep-and-grab approach. The realistic risk of two releases being dispatched within 30 seconds of each other to the same repo is negligible.

Local dry-run (rather than dispatching with a dry-run flag) catches problems earlier and consumes no CI resources. The workflow still accepts a `dry-run` input for manual dispatch from the GitHub UI, but the skill doesn't use it.

Three workflow inputs (`version`, `tag`, `ref`) are minimal and sufficient. The draft release already exists on GitHub, so no notes or release body need to transit through workflow inputs. This avoids escaping issues and keeps the workflow interface clean.

**Alternatives Considered**

- **Fire-and-Forget Dispatch**: Dispatch and print URL without monitoring. Rejected because the skill should tell users whether the release succeeded. Forcing users to open a browser for every release breaks the "single command" promise of PRD R1.

- **Full-Lifecycle Watch**: Use `gh run watch` to block until the workflow completes, matching the existing /release skill's approach. Rejected because it blocks the terminal indefinitely. Tsuku's release workflow takes 15-20 minutes with cross-platform builds. The correlation problem (sleep 5s, grab latest run) is also more fragile than polled timestamp matching.

**Consequences**

The skill becomes the primary release interface across all repos. It subsumes both the existing /prepare-release (note generation, draft creation) and /release (dispatch, monitoring) skills. Repos get a consistent release experience regardless of build complexity.

The 5-minute timeout means users of build-heavy repos will sometimes need to check the GitHub UI for final status. This is an accepted trade-off -- the alternative is blocking the terminal for 20+ minutes.

The skill-only mode means repos without CI (or repos bootstrapping their first release) can still use the skill for note generation and draft creation. Workflow adoption can happen incrementally.
<!-- decision:end -->
