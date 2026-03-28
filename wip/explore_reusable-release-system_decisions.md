# Exploration Decisions: reusable-release-system

## Round 1
- PRD as target artifact: User wants to define behaviors and personas before technical architecture
- Scope includes new release skill in shirabe: Replaces org-level /release and /prepare-release, not a modification to them
- Reusable workflow published from shirabe: Other repos call it via workflow_call, keeping the orchestration DRY
- Build/publish stays repo-specific: Each repo's build matrix is too different to abstract into the reusable workflow
- Hook contract uses convention-based scripts: .release/set-version.sh and .release/post-release.sh, not declarative config (repos need arbitrary logic)
- Draft-release-then-promote for release notes: Skill creates draft GH release with markdown notes, CI promotes after the prepare-release dance
