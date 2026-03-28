# /prd Scope: reusable-release-system

## Problem Statement

Repos in the tsukumogami ecosystem (tsuku, koto, niwa, shirabe) maintain independent, copy-pasted release workflows that have already caused version drift bugs (koto #81, shirabe manifest drift). There's no shared release skill or reusable workflow — each repo reinvents the prepare-release dance independently. The current org-level /release and /prepare-release skills are tightly coupled to a tag-push-first pattern that doesn't work for repos requiring version-stamped commits before tagging (like Claude Code plugins where the marketplace reads version from the tagged commit).

## Initial Scope

### In Scope
- A new release skill published from shirabe that replaces /release and /prepare-release
- A reusable GitHub Actions workflow (workflow_call) handling the Maven-style prepare-release dance
- A hook contract (.release/set-version.sh, .release/post-release.sh) for repo-specific version file updates
- Release notes flow: skill creates draft GH release, CI promotes after prepare-release dance
- User personas: repo owner (configures and runs releases), repo consumer (installs/updates from releases)
- Multi-ecosystem support: Go binaries (tsuku, niwa), Rust binaries (koto), Claude Code plugins (shirabe)
- Rolling dev sentinel pattern (e.g., 0.3.1-dev) for repos that maintain version files

### Out of Scope
- Automatic semver computation (human picks the version)
- Migrating tsuku/koto/niwa's existing release.yml as part of this work (they adopt later)
- Changelog generation tooling (release notes are human-reviewed)
- Package registry publishing (crates.io, npm) — GitHub releases only
- Build/publish automation (each repo keeps its own build jobs)

## Research Leads
1. **Repo owner workflow**: What's the step-by-step user experience from "decide to release" through "release is live"? How does it differ by repo type?
2. **Repo consumer experience**: How do consumers discover updates? What changes (if anything) about the consumer experience across repo types?
3. **Adoption path for existing repos**: What does a repo owner do to adopt the reusable system? What files do they create? What existing workflows do they replace?
4. **Release skill boundaries**: What does the skill do vs what the workflow does? Where's the handoff?
5. **Error and rollback scenarios**: What happens when a release fails mid-way? What does recovery look like for each failure point?

## Coverage Notes
- The exploration established the technical patterns (Maven dance, draft-promote, hooks) but didn't define the user-facing behaviors in detail
- The exact interaction between "skill creates draft" and "CI runs prepare-release dance" needs to be specified as a user-observable sequence
- How the skill discovers what version to release (user input? commit analysis? both?) wasn't settled
- Pre-release/beta versioning was mentioned but not explored
- How the skill and workflow version themselves (since they're published from shirabe) needs definition

## Decisions from Exploration
- PRD before design: define behaviors and personas before technical architecture
- New release skill in shirabe: replaces org-level /release and /prepare-release, not a modification to them
- Reusable workflow published from shirabe: other repos call via workflow_call
- Build/publish stays repo-specific: each repo's build matrix is too different to abstract
- Hook contract uses convention-based scripts: .release/set-version.sh and .release/post-release.sh
- Draft-release-then-promote for release notes: skill creates draft, CI promotes after prepare-release dance
- Rolling dev sentinel (e.g., 0.3.1-dev) over fixed sentinel (0.0.0-dev): enables update detection for HEAD users
