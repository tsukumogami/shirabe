# Exploration Findings: release-process

## Core Question

How should shirabe handle releases so that the git tag, plugin.json version, and marketplace.json version are always in sync — with the version set automatically at release time rather than maintained manually in the manifests?

## Round 1

### Key Insights

- **Marketplace reads version from plugin.json at the tagged commit** (marketplace-caching lead). Version is the sole cache-busting signal — if two refs have the same version, Claude Code skips the update. The version must be correct in the committed file at the tag.
- **Commit-first-then-tag is the only correct approach** (atomic-workflow lead). Koto's post-tag-commit pattern doesn't work for plugins because the marketplace reads from the tagged ref. Manifests must be updated before tagging.
- **Sentinel value (0.0.0-dev) is the simplest drift prevention** (pr-validation lead). Exact-match CI check, no semver logic needed. Contributors can't accidentally cause drift.
- **No plugin in the ecosystem automates this** (superpowers lead). Superpowers uses manual versioning with no CI automation. The official Anthropic marketplace doesn't even track versions — it points to main. This is an unsolved problem.
- **Koto's pattern is conceptually useful but needs inversion** (manifest-injection lead). Koto commits after tagging (acceptable for workflow defaults). Shirabe must commit before tagging (required for marketplace correctness).
- **Demand is self-initiated but technically justified** (adversarial-demand lead). No external requests exist, but version drift already occurred (0.2.0 manifests vs 0.1.0 tag). Marketplace caching makes this a correctness bug, not cosmetic.

### Tensions

- The existing /release skill pushes a tag first, then CI reacts. Marketplace correctness requires manifests updated before the tag. The skill flow needs adaptation for shirabe — either a pre-tag manifest update step, or a dispatch-based workflow that replaces tag-push-first with commit-tag-push.
- Sentinel approach means plugin.json on main shows 0.0.0-dev, not the current release. Users browsing the repo see an uninformative version. Trade-off: correctness automation vs human-readable manifests on main.

### Gaps

- How the /release skill integrates repo-specific pre-tag steps. Need to check if it supports hooks or customization.
- Whether RELEASE_PAT is already configured org-wide or needs per-repo setup.

### Decisions

- Commit-first-then-tag (Approach B) selected over post-tag-commit (Approach A)
- Sentinel value on main selected over real versions
- Design doc identified as the target artifact
- Adversarial demand acknowledged — technical correctness justifies the work despite no external requests

### User Focus

Auto-mode: User requested full automation with version set at release time, integration with org's existing /prepare-release and /release skills, and patterns from tsuku/koto adapted for shirabe's plugin context.

## Accumulated Understanding

Shirabe needs a release process that updates plugin.json and marketplace.json versions before tagging, because Claude Code's marketplace reads version from plugin.json at the tagged commit. The recommended approach: manifests contain a sentinel value (0.0.0-dev) on main, a release workflow takes the version as input, updates manifests, commits, tags the commit, and creates a GitHub release. CI validates that manifests contain the sentinel on every PR. The /release skill needs adaptation to run a pre-tag manifest update for shirabe, or the workflow uses dispatch-trigger instead of tag-trigger. Neither koto, tsuku, nor superpowers have solved this specific problem — shirabe's approach would be novel in the ecosystem.

## Decision: Crystallize
