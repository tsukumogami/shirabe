# Release Notes Flow: Local Skill to GitHub Release

Research lead: How should release notes flow from the user to the GitHub
release in a workflow_dispatch model?

## Approach 1: `gh release create --notes-file` (local creation)

The skill runs `gh release create <tag> --notes-file release-notes.md`
directly from the developer's machine.

**How it works.** The skill generates notes, presents them in `$EDITOR`
for review, then creates the release via the GitHub API (which is what
`gh release create` does under the hood). No CI workflow involved in
release creation itself.

**Multi-paragraph support.** Full markdown, no escaping issues, no size
limits beyond GitHub's release body limit (which is generous -- terraform-
provider-aws publishes 13KB+ release notes routinely).

**Human editability.** The skill can open `$EDITOR` or write a temp file
for the user to review/edit before creation. This is the most natural
editing experience.

**CI integration.** This is the key weakness. If CI needs to run checks
before publishing (build artifacts, run tests, sign binaries), then
creating the release locally either (a) skips those checks or (b) requires
a two-step dance: create as draft locally, CI promotes to published.

**Implications.**
- Requires the developer to have `gh` authenticated with release
  creation permissions (repo scope or fine-grained write:releases).
- No audit trail in CI -- the release appears to come from the user's
  account, not a bot. This can actually be desirable.
- Works well if CI's job is only to react to the release (build on
  release event), not to gate it.
- `gh release create` already handles the draft-then-publish pattern for
  asset uploads (documented in `--help`): it creates a draft, uploads
  assets, then publishes. We could use this same pattern.

**Verdict.** Best option for simple projects where CI doesn't gate
releases. For gated releases, combine with Approach 4 (draft + promote).

## Approach 2: Workflow Dispatch Input Field

The skill passes release notes as a `workflow_dispatch` input string, then
CI uses that string to create the release.

**How it works.** Define a workflow input:
```yaml
on:
  workflow_dispatch:
    inputs:
      release_notes:
        description: 'Release notes (markdown)'
        required: true
        type: string
```

Trigger with:
```bash
gh workflow run release.yml -f release_notes="$NOTES"
```

**Multi-paragraph support.** GitHub workflow_dispatch string inputs support
up to 65,535 characters. That's plenty -- the terraform-provider-aws
release notes above are ~13KB (about 13,000 chars), well within the limit.

**Escaping.** This is where it gets messy. The `gh workflow run -f`
flag passes values as-is via the API, so newlines work. However:
- Shell escaping is fragile. Multi-line content with quotes, backticks,
  and special characters needs careful handling.
- The `--json` flag via stdin is safer: `echo "$NOTES" | gh workflow run
  release.yml --json` reads structured JSON from stdin, avoiding shell
  escaping entirely.
- In the workflow, the input arrives as `${{ github.event.inputs.release_notes }}`.
  Using this in a shell step requires careful quoting to avoid injection.

**Human editability.** The user can edit before the skill dispatches, but
they can't easily edit after dispatch. If they spot a typo, they'd need to
re-run the workflow or edit the release after creation.

**CI integration.** Good -- CI has full control. It can run tests, build
artifacts, and create the release in a single workflow.

**Verdict.** Workable but brittle. Shell escaping of markdown content with
code blocks, quotes, and special characters is a persistent source of bugs.
The `--json` stdin approach mitigates this but adds complexity.

## Approach 3: Commit Notes to a File

The skill writes release notes to a file (e.g., `RELEASE-NOTES.md`) and
commits it. CI reads the file from the commit SHA.

**How it works.**
1. Skill generates notes, user edits them.
2. Skill commits the file to the release branch or a tag.
3. Workflow dispatch (or tag push) triggers CI.
4. CI reads the file and uses it for `gh release create --notes-file`.

**Multi-paragraph support.** Perfect -- it's just a file.

**Human editability.** The user can edit the file with any tool before the
skill commits it. They can also amend the commit if they spot issues.

**CI integration.** Clean. CI reads from a known path at a known commit.
No escaping, no size limits, no API gymnastics.

**Downsides.**
- Adds a commit to the repo that's purely for release mechanics. This
  pollutes the git history unless you're disciplined about cleanup.
- If the file persists in the repo, you need conventions: does it get
  cleared after release? Does each release have its own file?
- Race condition: if someone pushes between the notes commit and the
  workflow trigger, CI might read the wrong state. Using the commit SHA
  (not branch HEAD) fixes this.

**How others do it.** goreleaser supports a `--release-notes` flag that
reads from a file. Many projects keep a CHANGELOG.md that gets committed
as part of the release prep. The file-based approach is well-established.

**Verdict.** Clean and reliable if you accept the extra commit. Best for
projects that already maintain a changelog file.

## Approach 4: Draft Release via API, CI Promotes

The skill creates a draft release via the GitHub API. CI finds the draft,
optionally attaches artifacts, then publishes it.

**How it works.**
1. Skill generates notes, user reviews/edits.
2. Skill calls `gh release create <tag> --draft --notes-file notes.md`.
3. Skill triggers `workflow_dispatch` with just the tag name (simple
   string, no escaping issues).
4. CI finds the draft release for that tag, builds artifacts, attaches
   them, runs final checks, then publishes:
   `gh release edit <tag> --draft=false`

**Multi-paragraph support.** The notes are written via `--notes-file`,
so full markdown with no escaping concerns.

**Human editability.** The user can edit via `$EDITOR` before the skill
creates the draft. They can also edit the draft on GitHub's web UI after
creation but before CI publishes it -- this gives a second editing
opportunity.

**CI integration.** CI receives a simple tag string via workflow_dispatch.
It doesn't need to handle release notes at all -- just finds the existing
draft and promotes it. This cleanly separates authoring from publishing.

**Error handling.** If CI fails, the draft remains. The user can fix the
issue and re-trigger. No orphaned releases or partial states.

**Precedent.** `gh release create` itself uses this pattern for asset
uploads: it creates a draft, uploads, then publishes. GitHub's immutable
releases feature (documented in `gh release create --help`) explicitly
supports this: "Draft releases can be modified or deleted, and the
associated git tags can be modified or deleted as well."

**Verdict.** Best overall approach. Clean separation of concerns, full
markdown support, multiple editing opportunities, simple CI interface.

## Approach 5: Release Checklist Issue Body

The `/prepare-release` skill already creates a checklist issue. Release
notes could live in that issue body, and CI reads them via the API.

**How it works.**
1. Skill creates a release checklist issue with notes in a fenced section.
2. User edits the issue body on GitHub if needed.
3. CI parses the issue body to extract the release notes section.
4. CI creates the release with those notes.

**Multi-paragraph support.** Issue bodies support full markdown.

**Human editability.** Good -- GitHub's issue editor is familiar. Multiple
people can review/edit the notes before release.

**Downsides.**
- Parsing release notes from an issue body is fragile. You'd need
  delimiters (e.g., `<!-- RELEASE-NOTES-START -->`) and hope nobody
  accidentally edits them.
- Coupling between the issue format and CI parsing logic. If the issue
  template changes, CI breaks.
- The issue serves two purposes (checklist + notes), making it harder to
  reason about.
- Issue body edits don't trigger workflow runs, so you still need a
  separate trigger mechanism.

**Verdict.** Tempting because the issue already exists, but fragile in
practice. The parsing requirement adds unnecessary complexity.

## Approach 6: How Major Projects Handle This

### Terraform Providers (HashiCorp)
Release notes are maintained in a CHANGELOG.md file. The release process
reads from this file. Their release notes are extensive (13KB+ for
terraform-provider-aws v6.38.0). The changelog is committed as part of
development, not release prep.

### release-please (Google)
Uses a dedicated "release PR" whose body contains the generated changelog.
When the PR merges, release-please creates the GitHub release from the PR
body content. The PR body is auto-generated from conventional commits and
updated on each push to the branch. Human edits to the PR body are
preserved across updates (release-please detects manual changes).

Key detail: release-please doesn't use workflow_dispatch at all. It reacts
to push events on the default branch and manages its own state via release
PRs.

### semantic-release
Fully automated -- generates release notes from commit messages and
publishes directly. No human review step. Their own releases are small
(~357 chars for v25.0.3). This works for projects with strict commit
conventions but doesn't support human-edited notes.

### goreleaser
Supports multiple note sources: auto-generated from commits, read from a
file (`--release-notes`), or fetched from a URL. The file-based approach
is most common. goreleaser typically runs in CI after a tag push.

### VS Code Extensions (vsce)
The `vsce publish` command publishes to the VS Code marketplace. Release
notes typically live in CHANGELOG.md. GitHub releases are created
separately, often manually or via a workflow triggered by tag push.

### Common patterns
The dominant approaches are:
1. **Changelog file in repo** (Terraform, VS Code) -- committed during
   development, read during release.
2. **PR body** (release-please) -- auto-generated, human-editable,
   consumed on merge.
3. **Fully automated** (semantic-release) -- no human review.

None of the major projects use workflow_dispatch inputs for release notes.

## Approach 7: release-please Deep Dive

release-please's flow:
1. Watches for commits on the default branch.
2. Maintains a "Release PR" that accumulates unreleased changes.
3. The PR title follows a pattern: `chore(main): release <pkg> <version>`.
4. The PR body contains the full changelog in markdown.
5. On each new commit, release-please updates the PR body with new entries.
6. When the PR is merged, release-please creates the tag and GitHub release.

The PR body serves as both the preview and the source of truth. This is
elegant but tightly coupled to release-please's PR-driven model. It
doesn't translate directly to a workflow_dispatch model.

**What we can learn:** Separating "note authoring" from "release
publishing" is the right pattern. release-please does this via a PR.
We can do it via a draft release (Approach 4).

## Comparison Matrix

| Criterion               | 1: Local gh | 2: Dispatch Input | 3: File Commit | 4: Draft+Promote | 5: Issue Body |
|--------------------------|-------------|-------------------|----------------|-------------------|---------------|
| Multi-paragraph          | Full        | Full (65KB limit) | Full           | Full              | Full          |
| Escaping concerns        | None        | Significant       | None           | None              | N/A (parsing) |
| Human editability        | $EDITOR     | Before dispatch   | Before commit  | $EDITOR + Web UI  | Web UI        |
| CI integration           | Weak        | Good              | Good           | Good              | Fragile       |
| Simplicity               | High        | Medium            | Medium         | Medium            | Low           |
| Post-dispatch editing    | N/A         | No                | No             | Yes (web UI)      | Yes           |
| Git history pollution    | None        | None              | One commit     | None              | None          |
| Separation of concerns   | Poor        | Poor              | Fair           | Excellent         | Poor          |

## Recommendation

**Approach 4 (Draft Release + CI Promote) is the strongest option.**

The flow would be:
1. Skill generates release notes from commit history / PR summaries.
2. Skill presents notes in `$EDITOR` for user review.
3. Skill creates a draft release: `gh release create <tag> --draft -F notes.md`
4. Skill triggers workflow_dispatch with just the tag (a simple string).
5. CI finds the draft, builds, tests, attaches artifacts, publishes:
   `gh release edit <tag> --draft=false`

This gives us:
- Full markdown with zero escaping issues.
- Two editing windows: local `$EDITOR` and GitHub web UI.
- Clean CI interface: workflow only needs a tag string.
- Graceful error handling: draft survives CI failures.
- No git history pollution.
- Pattern already used by `gh release create` itself for asset uploads.

**Fallback consideration:** If we later want to support repos where the
skill user doesn't have release creation permissions, Approach 3 (commit
a file) works as a fallback. CI can read the file and create the release
itself.
