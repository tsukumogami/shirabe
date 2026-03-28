# Exploration Findings: reusable-release-system

## Core Question

What should a reusable release system look like that any repo in the tsukumogami ecosystem can adopt, aligned with industry-standard patterns?

## Round 1

### Key Insights

- Draft-release-then-promote solves release notes cleanly: skill creates draft GH release with full markdown, CI runs the prepare-release dance, promotes to published (release-notes lead)
- Two optional hooks suffice: set-version.sh (stamp version files) and post-release.sh (repo-specific cleanup). Build/publish stays repo-specific (hook-contract lead)
- Release-please's extra-files config is elegant for simple cases but its PR gate and TypeScript plugins don't fit our model (release-please lead)
- Reusable workflows run in caller context — can call repo-local scripts after checkout. Max 10 inputs. Versioned via @v1 floating tag (reusable-GHA lead)
- No Claude Code plugin ships reusable CI workflows today — shirabe would be first (plugin-CI lead)
- Demand validated at narrow level (version drift bugs in koto #81, shirabe drift, issue #4 asks for reusable workflows). Broad reusable system demand is weaker but copy-paste already caused bugs (adversarial lead)
- Each repo's build matrix is too different to abstract — reusable workflow handles orchestration (version stamp, tag, dev bump, promote), not builds (user-journey lead)

### Tensions

- Scope breadth vs single-maintainer reality: reusable system for 4 repos vs one person. But copy-paste already caused bugs.
- Shell hooks vs declarative config: hooks are more flexible but config is simpler for common cases.
- Reusable workflow scope: "release core" vs complete solution. Repos still need their own build jobs.

### Gaps

- Exact interaction between draft-release and Maven-style prepare dance
- Concrete example of a caller's release.yml

### Decisions

- PRD is the right artifact: user wants to define behaviors before architecture
- Scope includes a new release skill in shirabe replacing org-level /release and /prepare-release
- Reusable workflow published from shirabe for other repos to adopt

### User Focus

User wants to define what needs to be built (behaviors, personas, user journeys) before how. PRD first, design doc second. Shirabe is one instance of the user base, not the only one.

## Accumulated Understanding

The reusable release system has three components: (1) a new release skill published from shirabe that replaces /release and /prepare-release, (2) a reusable GitHub Actions workflow that handles the Maven-style prepare-release dance (version stamp, commit, tag, dev bump, commit, push, promote draft release), and (3) a hook contract (.release/set-version.sh and .release/post-release.sh) that repos implement for their specific version files.

The skill handles the human side: checklist management, release notes generation/review, draft release creation, and workflow dispatch. The reusable workflow handles the automation: calling set-version.sh, committing, tagging, bumping to dev, promoting the draft. Repos keep their own build/publish jobs that depend on the reusable workflow's output.

Industry alignment: Maven's prepare-release dance (the universal pattern), release-please's extra-files concept (declarative version file updates), draft-release-then-promote (standard GH pattern for gated releases).

## Decision: Crystallize
