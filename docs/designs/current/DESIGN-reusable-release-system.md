---
status: Proposed
upstream: docs/prds/PRD-reusable-release-system.md
problem: |
  placeholder
decision: |
  placeholder
rationale: |
  placeholder
---

# DESIGN: Reusable Release System

## Status

Proposed

## Context and Problem Statement

The tsukumogami ecosystem has four public repos with different build toolchains
(Go+Rust, Rust, Go, JSON manifests) that each implement their own release workflow.
The technical challenge is building a single release pipeline that handles the
Maven-style prepare-release dance -- version stamp, commit, tag, dev bump, commit,
push -- while delegating repo-specific concerns (which files contain versions, how
binaries are built) to convention-based hooks.

Three architectural constraints shape the design:

1. **The tag must point to a commit with correct version files.** The Claude Code
   marketplace reads plugin.json at the tagged commit. Go and Rust repos inject
   version at build time from the tag, but repos with static version files need
   them stamped before the tag is created.

2. **CI must own the commit-tag-push sequence.** The release skill runs locally and
   can't reliably push to branch-protected main. A workflow_dispatch workflow runs
   with appropriate permissions and performs all git mutations server-side.

3. **Existing build workflows must keep working.** Tsuku's 520-line release.yml,
   koto's cross-compilation pipeline, and niwa's goreleaser workflow are all
   tag-triggered. The new system's tag push must trigger these unchanged.

The system spans three components: a release skill (local, handles the human side),
a reusable GitHub Actions workflow (server-side, handles git mutations), and a hook
contract (repo-local scripts that the workflow calls).

## Decision Drivers

- **Version correctness by construction**: The tag must always point to a commit with
  matching version files. No window where the tag exists with wrong versions.
- **Ecosystem diversity**: Go (ldflags), Rust (Cargo.toml), JSON manifests (plugin.json),
  and no-version repos must all work with the same workflow.
- **Adoption friction**: A new repo should adopt the system by adding one workflow file
  and optionally one hook script. No reusable workflow changes needed.
- **Failure recoverability**: Every failure point must have a documented recovery path
  that doesn't require git surgery.
- **Existing workflow compatibility**: Tag push from the reusable workflow must trigger
  existing tag-triggered build/release workflows without modification.
- **Independent operation**: The workflow must be usable from the GitHub UI without the
  skill. The skill must be usable without the workflow.
- **Hook contract stability**: The hook interface is a public API. Changes are breaking.
