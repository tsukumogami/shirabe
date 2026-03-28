<!-- decision:start id="build-workflow-coordination" status="assumed" -->
### Decision: How the reusable workflow coordinates with build workflows and draft promotion

**Context**

The reusable release workflow performs a Maven-style version dance: set release version, commit, tag, bump to dev version, commit, push branch, push tag. The tag push then triggers repo-specific build workflows (tsuku, koto, niwa) that compile binaries and upload them to the GitHub release. Those builds take 10-30 minutes. The draft release should only be promoted to public after builds succeed and upload their artifacts.

The core tension: the reusable workflow finishes before build workflows start. It can't promote the draft itself for repos with builds, but repos without builds (shirabe) need immediate promotion. The existing codebase already has `finalize-release` jobs in tsuku and koto that handle post-build promotion and verification.

**Assumptions**

- All repos will adopt draft-then-promote. Koto currently creates a non-draft release directly; niwa has GoReleaser `draft: true` but no promotion step. Both will need updates regardless of which option is chosen.
- `workflow_run` is an acceptable trigger mechanism for cross-workflow coordination. It's GitHub's native solution for this pattern.
- The reusable workflow runs as a `workflow_call` target invoked by each repo's caller workflow.

**Chosen: Reusable release workflow does NOT promote; a companion reusable finalize workflow handles promotion. Repos with builds trigger finalize via `workflow_run` after their build workflow completes. Repos without builds call finalize inline as a sequential job.**

The system provides two reusable workflows:

1. **`release.yml`** -- performs the version dance through tag push. Outputs the tag name and release URL. Never promotes.
2. **`finalize-release.yml`** -- accepts a tag name, optionally verifies artifact count, promotes the draft (`--draft=false`).

Each repo wires these up according to its needs:

- **Repos without builds (shirabe):** the caller workflow calls `release.yml` then `finalize-release.yml` as sequential jobs. Single workflow file, two jobs, immediate promotion.
- **Repos with builds (tsuku, koto, niwa):** the existing tag-triggered build workflow runs as usual. A thin `on: workflow_run` workflow triggers when the build workflow completes and calls `finalize-release.yml`. The finalize workflow verifies artifacts are present before promoting.

This extracts the pattern that already exists in tsuku's `finalize-release` job and koto's `finalize-release` job into a reusable component.

**Rationale**

The five alternatives evaluated along reliability, platform alignment, consistency, and migration cost. Three were eliminated early:

- **Wait-and-Poll (C)** was unanimously rejected. Polling across workflow boundaries introduces race conditions, wastes compute, and fights the platform's design. GitHub provides `workflow_run` for exactly this use case.
- **Output-Based Chaining (D)** delegates all coordination to callers, defeating the purpose of a reusable system. Every repo would reimplement the same promotion logic.
- **Never-Promote (B)** has the right instinct (separation of concerns) but applies it too rigidly, forcing simple repos into unnecessary two-workflow complexity without offering inline finalization.

The real contest was between **Promote-Immediately with override (A)** and **Companion finalize workflow (E)**:

Alternative A is simpler for tsuku specifically (zero changes to its existing `finalize-release` job) and uses a single reusable workflow with a `skip_promotion` boolean. But the flag creates an inconsistent mental model: "the reusable workflow promotes, except when it doesn't." Getting the flag wrong leads to premature promotion (missing binaries in a public release) or orphaned drafts.

Alternative E trades one boolean flag for a consistent two-workflow model where every repo follows the same pattern. The finalize workflow is thin (~20 lines of reusable YAML) and mirrors logic that already exists in tsuku and koto. The `workflow_run` mechanism is GitHub's native answer to "do X after Y completes," so the approach is platform-aligned rather than fighting it.

The migration cost difference is modest. Tsuku's existing `finalize-release` job can either be replaced with a call to the reusable finalize workflow or kept alongside it during transition. Koto needs a draft-then-promote switch regardless. Niwa needs a promotion step regardless.

**Alternatives Considered**

- **Promote-Immediately with Per-Repo Override (A)**: Single reusable workflow with `skip_promotion` input. Rejected because the conditional promotion creates split ownership of a critical operation. A single boolean controls whether a release goes public -- that's the wrong place for a flag. Migration cost advantage over E is real but small.
- **Never-Promote with Separate Finalize (B)**: Two reusable workflows, but no inline option for simple repos. Rejected because it forces all repos through the two-workflow path even when unnecessary. E subsumes B's good parts.
- **Wait-and-Poll (C)**: Reusable workflow polls for build completion. Rejected for fundamental reliability issues: race conditions on run matching, wasted compute during polling, fragile timeout tuning, and API rate limit exposure.
- **Output-Based Caller Chaining (D)**: Reusable workflow outputs tag/URL, callers handle promotion. Rejected because it provides data without behavior. Each repo would independently implement promotion, which is the opposite of reusable.

**Consequences**

The reusable release system ships as two workflows instead of one. This means:
- Every repo needs a caller workflow that calls both (simple repos: sequential jobs; build repos: `workflow_run` bridge)
- The finalize workflow becomes a single point of truth for "what does promotion mean" -- artifact verification, checksums, and `--draft=false` all live in one place
- Future repos get a clear template: "do you have builds? Add a workflow_run trigger. No builds? Add a second job."
- The `workflow_run` default-branch limitation means finalize workflow changes can only be fully tested after merge to main. This is acceptable because the finalize workflow is thin and changes rarely.
<!-- decision:end -->
