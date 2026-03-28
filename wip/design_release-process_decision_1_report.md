<!-- decision:start id="release-flow-end-to-end" status="assumed" -->
### Decision: Release flow end-to-end

**Context**

Shirabe is a Claude Code skills plugin whose marketplace listing reads the version from
plugin.json at the tagged commit. Two pre-decided constraints shape this decision: (1)
manifests must be updated before tagging (commit-first), and (2) main carries a 0.0.0-dev
sentinel that's only replaced at release time. The org already has /prepare-release and
/release skills -- /prepare-release creates a checklist issue, and /release creates an
annotated tag locally and pushes it to trigger a release workflow.

Koto uses a tag-triggered release pattern with a finalize-release job that commits back
to main. Shirabe needs a similar pattern but simpler: no binaries to build, just manifest
version stamping and a GitHub release.

**Assumptions**

- The Claude Code marketplace resolves plugin version by reading plugin.json at the tagged
  ref. If wrong: the tag-must-match-manifest constraint is unnecessary, and any approach
  would work.
- The /release skill can accommodate a repo-specific pre-tag step (updating manifests and
  committing) without a full rewrite. If wrong: the skill needs a hook mechanism first.
- RELEASE_PAT secret is available for the finalize-release job to push commits back to
  main (same pattern koto already uses).

**Chosen: /release skill updates manifests locally before tagging**

The /release skill handles manifest updates as a pre-tag step. The full flow:

1. `/prepare-release` creates a release checklist issue (unchanged).
2. `/release <issue>` validates the checklist, generates release notes.
3. `/release` replaces 0.0.0-dev with the release version in both
   `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
4. `/release` commits the manifest change: `chore(release): set version to <version>`.
5. `/release` creates an annotated tag on that commit with release notes as the message.
6. `/release` pushes the tag to origin.
7. A tag-triggered GitHub Actions workflow (`release.yml`, triggered on `v*` tags):
   a. Creates a GitHub release using the tag's annotation as release notes.
   b. Runs a finalize-release job that checks out main, resets both manifests to
      0.0.0-dev, commits (`chore(release): reset version to 0.0.0-dev`), and pushes.

This means the tag always points to a commit where plugin.json has the correct version.
Main normally carries 0.0.0-dev, briefly has the real version during the release commit,
and returns to 0.0.0-dev after finalize-release.

**Rationale**

This approach minimizes moving parts. The /release skill already creates tags locally --
adding a commit before the tag is a small, natural extension. The tag-triggered workflow
pattern matches koto's existing release.yml, keeping cross-repo consistency. No special
permissions beyond the existing RELEASE_PAT are needed. The workflow itself is trivial
(no build matrix, no binary artifacts) -- just create a GH release and reset the sentinel.

workflow_dispatch would split the release logic between the local skill and a server-side
workflow, making debugging harder and requiring the release notes to be passed as a
workflow input (awkward for multi-paragraph notes). A release branch adds git-flow
complexity with no offsetting benefit for a project this simple.

**Alternatives Considered**

- **workflow_dispatch orchestration**: Server-side workflow accepts version input, updates
  manifests, commits, tags, and creates the release. Rejected because it moves local
  operations to CI unnecessarily, reduces testability, and requires passing release notes
  through workflow inputs. Also breaks consistency with koto's tag-triggered pattern.

- **Release branch with updated manifests**: Create a short-lived release branch, update
  manifests there, tag, push. Rejected because it introduces branch management overhead
  (creation, cleanup) without clear benefit. The version commit on main is no worse than
  koto's finalize-release commit.

**Consequences**

The release commit (version stamp) and the finalize commit (sentinel reset) will both
appear on main's history. This is two extra commits per release -- acceptable given
shirabe's low release frequency and consistent with koto's pattern.

The /release skill needs a shirabe-specific pre-tag hook. This could be implemented as a
conditional check for `.claude-plugin/plugin.json` existence, or as a configurable
pre-tag script. The exact mechanism is a separate implementation detail.

The release.yml workflow for shirabe will be much simpler than koto's -- no build matrix,
no artifact uploads. Just extract release notes from the tag annotation and call
`gh release create`.
<!-- decision:end -->
