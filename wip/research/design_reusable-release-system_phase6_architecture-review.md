# Architecture Review: DESIGN-reusable-release-system

Reviewer: architecture-review agent
Date: 2026-03-28

## 1. Is it clear enough to implement?

**Verdict: Yes, with two gaps.**

The design is unusually implementation-ready. The three-layer decomposition
(skill, release workflow, finalize workflow) is well-defined. Caller workflow
templates are copy-pasteable. The hook contract is precise (paths, arguments,
exit codes, skip semantics). The data flow diagram traces a release
end-to-end.

**Gap A: Tag extraction in finalize bridge workflow.** The build-repo
finalize.yml example uses `github.event.workflow_run.head_branch` to get the
tag. This field holds the branch name, not the tag. For tag-triggered
workflows, `head_branch` is the tag ref only when the triggering event was a
tag push. If the existing build workflow triggers on `push: tags: ['v*']`,
this works. But if it triggers on `release` events or `workflow_dispatch`,
`head_branch` will be `main` and finalize will look for the wrong tag. The
design should specify which trigger type it assumes on existing build
workflows or provide a more reliable tag extraction method (e.g., the build
workflow writing the tag to an artifact or output).

**Gap B: Concurrent release race condition.** The design mentions
fast-forward-only pushes and failure on conflict, but doesn't address the
window between "draft created" and "workflow dispatch." If two operators
dispatch for different versions, both drafts exist and the workflow that runs
second will fail at push (non-fast-forward). The first draft is now orphaned.
This is unlikely for four repos with small teams, but the recovery path
("delete orphaned draft, re-run") should be documented.

## 2. Missing components?

**2a: Error recovery playbook.** R11 requires actionable error messages, and
the design mentions "documented recovery path" as a decision driver, but no
concrete error-to-recovery mapping exists. Each failure point (token
validation, set-version hook failure, push conflict, draft not found by
finalize) needs a specific recovery command. This should be a section in the
design or a separate ops doc referenced from it.

**2b: Rollback procedure.** The design covers forward failure (workflow fails,
draft persists, retry). It doesn't cover "release succeeded but the version
is wrong" -- the tag is pushed, builds triggered, and the release needs
reverting. This likely means: delete tag remotely, delete the GH release,
revert the two commits. It's not strictly in scope (PRD calls it out of scope
implicitly) but a one-paragraph note would prevent someone from improvising.

**2c: Workflow versioning mechanics.** The design says callers pin to `@v1`
and shirabe's tags are shared. But it doesn't specify how the `v1` tag is
maintained. Is it a moving tag (updated to point at each minor release)? A
branch? A tag alias? GitHub's reusable workflow resolution depends on this.
Moving tags are the convention but need explicit management -- the release
workflow itself would need to update the major version tag after each shirabe
release.

**2d: `post-release.sh` dropped from the design.** The PRD defines
`post-release.sh` (R3), and the design's hook contract table includes it, but
no workflow step calls it. The release workflow ends at push. The finalize
workflow ends at `--draft=false`. Where does `post-release.sh` run? It should
be a step in finalize-release.yml after promotion, or the hook should be
explicitly deferred/dropped with a note.

## 3. Are the phases correctly sequenced?

**Verdict: Yes, the sequencing is sound.**

Phase 1 (reusable workflows) before Phase 2 (shirabe adoption) is correct --
you need the workflows to exist before bootstrapping.

Phase 2 (shirabe adoption) before Phase 3 (release skill) is a good call.
It means the workflows are battle-tested via manual dispatch before the skill
automates them. If Phase 3 came first, the skill would be dispatching
untested workflows.

Phase 3 (skill) before Phase 4 (ecosystem migration) is correct -- the skill
makes migration faster and provides a consistent interface.

**One concern:** Phase 2 says "verify end-to-end with a dry-run, then cut a
real release." The dry-run tests set-version and commit logic but not the
actual push or tag trigger chain. The first real release is the first test of
push-order behavior, tag-triggered workflow firing, and finalize-release
promotion. Consider whether a pre-release (e.g., `v0.2.0-rc.1`) would be
safer, though the PRD explicitly excludes pre-release versions. At minimum,
document that the first real Phase 2 release is higher risk and should be done
with close monitoring.

## 4. Simpler alternatives overlooked?

**4a: Single workflow with conditional promotion.** The design rejects
"promote-immediately with per-repo override" but the rejection rationale
("boolean controlling whether a release goes public is the wrong abstraction")
is a framing issue, not a technical one. A single workflow with an
`auto-promote` boolean (default true) would eliminate the finalize workflow,
the workflow_run bridge, and the two-workflow mental model. Repos with builds
set `auto-promote: false` and their existing build workflow calls `gh release
edit --draft=false` as its final step (one line, no reusable workflow needed).
This is materially simpler. The design's objection about "getting the flag
wrong" applies equally to forgetting to wire up the finalize bridge. I'd
weigh this alternative more seriously.

**4b: Skip the dev-bump commit entirely.** The design creates two commits per
release (set version, then bump to dev). An alternative: tag the current
commit as-is and have set-version.sh run only once in a follow-up commit. For
repos where version is injected at build time (Go via ldflags, Rust via
build.rs), the set-version hook is unnecessary -- the tag IS the version. Only
shirabe (JSON manifests) needs version-stamped files at the tag. A
`needs-version-stamp: true` input could conditionally run the
stamp-then-tag sequence, saving a commit for most repos. However, this adds
conditional complexity to the workflow, so the uniform two-commit approach is
defensible for four repos.

**4c: Use GitHub's auto-generated release notes.** The design has the skill
generate notes from commit analysis. GitHub can auto-generate notes from PR
titles via `.github/release.yml` configuration. For four small repos, this
might be sufficient and would remove the note-generation phase from the skill
entirely. The skill would just create the draft with `--generate-notes` and
let the user edit in the GitHub UI. This trades agent-quality notes for
simplicity. Worth considering for the MVP, with agent-generated notes as a
later enhancement.

## Summary of findings

| # | Category | Severity | Finding |
|---|----------|----------|---------|
| A | Clarity | Medium | `head_branch` tag extraction in finalize bridge may not work for all trigger types |
| B | Clarity | Low | Concurrent release race condition recovery not documented |
| C | Missing | Medium | No error-to-recovery mapping despite R11 requiring actionable errors |
| D | Missing | Medium | `post-release.sh` hook defined but never called by any workflow step |
| E | Missing | Low | `@v1` tag management mechanics unspecified |
| F | Missing | Low | No rollback procedure for successful-but-wrong releases |
| G | Sequencing | Low | First real release in Phase 2 is untested path; note the elevated risk |
| H | Alternative | Medium | Single workflow with `auto-promote` flag is materially simpler than two workflows + bridge |
| I | Alternative | Low | GitHub auto-generated notes could simplify the skill MVP |
