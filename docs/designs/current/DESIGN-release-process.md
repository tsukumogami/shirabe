---
status: Proposed
problem: |
  Shirabe's plugin.json and marketplace.json versions drift from git tags because
  versions are maintained manually. The Claude Code marketplace reads version from
  plugin.json at the tagged commit, making this a correctness problem: stale versions
  cause users to miss updates. The release process needs to set versions automatically
  at release time and integrate with the org's existing /prepare-release and /release
  skills.
---

# DESIGN: Release Process

## Status

Proposed

## Context and Problem Statement

Shirabe is a Claude Code skills plugin with version declared in two manifest files
(`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`). The Claude Code
marketplace reads the version from `plugin.json` at the specific git ref/sha — the
version field is the sole mechanism for update detection. If two refs have identical
versions, Claude Code treats them as the same and skips the update.

Currently versions are maintained manually. The manifests already drifted: both say
0.2.0 while the only git tag is 0.1.0. No release workflow exists. No CI validates
version consistency.

Exploration found that neither koto nor tsuku face this problem (they have no plugin
manifests). Superpowers, the most prominent Claude Code plugin, uses fully manual
versioning with no automation — this is an unsolved problem in the ecosystem.

Two workflow architectures were evaluated:
- **Approach A (tag-first):** /release pushes tag, then a finalize-release job updates
  manifests and commits to main. This is koto's pattern. It creates a window where the
  tag points to a commit with the wrong version — a correctness problem for marketplace
  resolution.
- **Approach B (commit-first):** Update manifests, commit, then tag that commit. The
  tag always points to correct manifests. Requires the release workflow to take version
  as explicit input rather than deriving from a pushed tag.

## Decision Drivers

- Marketplace correctness: version in plugin.json at the tagged commit must match the
  tag name
- Integration with existing /prepare-release and /release org skills
- Full automation: version set at release time, not maintained manually
- Prevention of version drift between releases
- Simplicity: shirabe has no binaries to build, so the workflow should be minimal
- Consistency with koto/tsuku release patterns where possible

## Decisions Already Made

From exploration convergence (Round 1):

- **Approach B (commit-first, then tag) over Approach A (tag-first):** Marketplace
  reads plugin.json at the tagged commit, so the version must be correct before
  tagging. Approach A creates a window where the tag exists with wrong manifests.
- **Sentinel value (0.0.0-dev) on main over real versions:** Prevents drift, simpler
  CI check, aligns with marketplace caching. Real versions only exist at release tags.
- **Adversarial demand acknowledged but not blocking:** Version drift is a technical
  correctness problem (marketplace serves stale versions), not just a nice-to-have.
  Single-contributor project doesn't invalidate the need.
