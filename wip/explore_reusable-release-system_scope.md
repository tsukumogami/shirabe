# Explore Scope: reusable-release-system

## Visibility

Public

## Core Question

What should a reusable release system look like that any repo in the tsukumogami ecosystem (Go binaries, Rust binaries, Claude Code plugins, CLIs) can adopt — and how should it align with industry-standard release patterns like Maven release, release-please, and semantic-release?

## Context

Earlier exploration of shirabe's release process revealed that baking repo-specific logic into the org's generic /release skill is the wrong approach. The conversation evolved toward: (1) a workflow_dispatch-based CI workflow that owns the full commit-tag-release-bump dance, (2) repo-local scripts like `set-version.sh` that the workflow calls, and (3) a new release skill published from shirabe that replaces the current org-level /release and /prepare-release skills.

The user wants to define the user-facing behaviors (PRD) before the technical architecture (design doc). Key personas are repo owners (who configure and run releases) and repo consumers (who install/update from releases). Shirabe is one instance of the user base, not the only one.

Prior research established: Maven's prepare-release dance is the universal pattern (version stamp, commit, tag, dev bump, commit). Release-it and semantic-release use repo-local hooks/plugins. The Claude Code marketplace reads version from plugin.json at the tagged ref. Koto and tsuku currently use tag-triggered workflows with finalize-release jobs.

## In Scope

- User personas and their workflows (repo owner releasing, consumer updating)
- Release skill definition (replaces /release and /prepare-release)
- Reusable GitHub Actions workflow published from shirabe
- Hook contract for repo-specific logic (set-version, build, publish)
- Release notes flow (generation, review, publication)
- Multi-ecosystem support (Go/Rust/plugin/CLI repos)
- Alignment with industry patterns (Maven, release-please, semantic-release, npm)
- How existing repos (tsuku, koto, niwa) would adopt this

## Out of Scope

- Automatic semver computation (human picks the version)
- Migrating tsuku/koto's existing release.yml as part of this work
- Changelog generation tooling (release notes are human-reviewed)
- Package registry publishing (crates.io, npm, etc.) — just GitHub releases for now

## Research Leads

1. **What does the full release-please workflow look like, and how does it handle multi-ecosystem repos?**
   Release-please is Google's approach to the same problem. Understanding its manifest config, commit-based versioning, and plugin model would reveal whether we should adopt its patterns or diverge.

2. **What hook contract would support tsuku (Go+Rust), koto (Rust), niwa (Go), and shirabe (JSON manifests)?**
   Each repo has different version file locations and build steps. The hook contract needs to be minimal but sufficient. What's the smallest set of scripts a repo needs to provide?

3. **How should release notes flow from the user to the GitHub release in a workflow_dispatch model?**
   Maven uses tag annotations. Release-please uses PR bodies. Semantic-release generates from commits. We need a path that supports human-reviewed notes without awkward workarounds for multi-paragraph content.

4. **What do repo owners and consumers actually need from the release experience?**
   Before deciding mechanics, we should understand the user journey. What does a repo owner do today vs what they should do? What does a consumer see? How does update detection work across repo types?

5. **How do reusable GitHub Actions workflows work, and what are the constraints?**
   Shirabe would publish a reusable workflow. What inputs/outputs does it expose? How do callers customize it? What are the limitations (secrets passing, artifact access, permissions)?

6. **What patterns exist for publishing reusable release workflows from plugin/skills repos?**
   Are there examples of Claude Code plugins or similar ecosystems that ship reusable CI workflows alongside their skills? How do they version the workflow itself?

7. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
   You are a demand-validation researcher. Investigate whether evidence supports
   pursuing this topic. Report what you found. Cite only what you found in durable
   artifacts. The verdict belongs to convergence and the user.

   ## Visibility

   Public

   Respect this visibility level. Do not include private-repo content in output
   that will appear in public-repo artifacts.

   ## Six Demand-Validation Questions

   Investigate each question. For each, report what you found and assign a
   confidence level.

   Confidence vocabulary:
   - **High**: multiple independent sources confirm (distinct issue reporters,
     maintainer-assigned labels, linked merged PRs, explicit acceptance criteria
     authored by maintainers)
   - **Medium**: one source type confirms without corroboration
   - **Low**: evidence exists but is weak (single comment, proposed solution
     cited as the problem)
   - **Absent**: searched relevant sources; found nothing

   Questions:
   1. Is demand real? Look for distinct issue reporters, explicit requests,
      maintainer acknowledgment.
   2. What do people do today instead? Look for workarounds in issues, docs,
      or code comments.
   3. Who specifically asked? Cite issue numbers, comment authors, PR
      references — not paraphrases.
   4. What behavior change counts as success? Look for acceptance criteria,
      stated outcomes, measurable goals in issues or linked docs.
   5. Is it already built? Search the codebase and existing docs for prior
      implementations or partial work.
   6. Is it already planned? Check open issues, linked design docs, roadmap
      items, or project board entries.

   ## Calibration

   Produce a Calibration section that explicitly distinguishes:

   - **Demand not validated**: majority of questions returned absent or low
     confidence, with no positive rejection evidence. Flag the gap. Another
     round or user clarification may surface what the repo couldn't.
   - **Demand validated as absent**: positive evidence that demand doesn't exist
     or was evaluated and rejected. Examples: closed PRs with explicit maintainer
     rejection reasoning, design docs that de-scoped the feature, maintainer
     comments declining the request. This finding warrants a "don't pursue"
     crystallize outcome.

   Do not conflate these two states. "I found no evidence" is not the same as
   "I found evidence it was rejected."
