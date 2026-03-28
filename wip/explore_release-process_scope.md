# Explore Scope: release-process

## Visibility

Public

## Core Question

How should shirabe handle releases so that the git tag, plugin.json version, and marketplace.json version are always in sync — with the version set automatically at release time rather than maintained manually in the manifests?

## Context

Shirabe is a Claude Code skills plugin with version declared in two manifest files (.claude-plugin/plugin.json and .claude-plugin/marketplace.json). Currently version 0.2.0 in both manifests, but the only git tag is 0.1.0 — they're already out of sync. The org has existing /prepare-release and /release skills that handle checklist creation, blocker identification, release notes, and tag+publish. Tsuku and koto both derive version from git tags at build/release time rather than maintaining version files manually. The user wants full automation: version set at release time, not maintained in source.

## In Scope

- Version synchronization between git tag, plugin.json, and marketplace.json
- Automation that sets version at release time (not manual bumps)
- Integration with existing /prepare-release and /release org skills
- GitHub Actions release workflow for shirabe
- CI validation that versions are consistent
- How the Claude Code marketplace resolves and caches plugin versions

## Out of Scope

- Individual skill-level versioning (skills don't have versions)
- Binary builds (shirabe has no compiled artifacts)
- Changelog generation beyond what /release already handles
- Publishing to npm or other package registries

## Research Leads

1. **How do koto and tsuku's release workflows handle manifest version injection?**
   Koto's finalize-release job updates a workflow default after tagging; tsuku injects via ldflags. Neither has a plugin.json to update. We need to understand whether their patterns can be adapted for manifest file updates.

2. **What does the Claude Code marketplace expect regarding version, ref, and caching?**
   The marketplace uses version fields to decide whether to update. If two refs have the same version, updates are skipped. We need to understand whether the marketplace reads version from plugin.json at the tagged ref, or from a central registry.

3. **What's the simplest CI workflow that bumps plugin.json + marketplace.json and tags atomically?**
   We need a workflow that, given a version decision, updates both manifests, commits, tags, and creates a GH release — without race conditions or partial states. Should explore tag-triggered vs. manual dispatch approaches.

4. **How does obra/superpowers handle versioning and releases?**
   Superpowers is at v5.0.6 with a similar plugin.json structure. Understanding their release cadence, whether they automate manifest bumps, and how they coordinate with the official marketplace provides a real-world comparison.

5. **What validation should CI run on every PR to prevent version drift?**
   The current manifests drifted from the tag. A CI check could enforce that manifests either match the latest tag or contain a sentinel value that release automation replaces. Need to determine which approach is least friction.

6. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
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
