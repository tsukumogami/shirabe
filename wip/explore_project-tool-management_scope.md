# Explore Scope: project-tool-management

## Visibility

Public

## Core Question

How should shirabe adopt tsuku's `.tsuku.toml` project-level tool management for local development and CI? This is a friction log exercise: the deliverable is both a working config and a catalog of UX issues to file against tsuku. tsuku 0.9.0 was recently released and may have addressed friction points from the original exploration.

## Context

Tsuku shipped project-level tool management via `.tsuku.toml` -- a TOML file declaring required tools and version constraints. Discovery walks up from cwd, `tsuku install` (no args) batch-installs everything. Shirabe depends on koto (>= 0.2.1), gh, jq, python3, and claude for various workflows. CI currently installs tools manually (e.g., `tsuku install tsukumogami/koto -y` in validate-templates.yml). An earlier exploration (round 1 on this branch) identified friction points including undocumented org-scoped recipe support, missing adoption guides, and partial recipe coverage. tsuku 0.9.0 has since shipped, potentially fixing some of these. The tsuku-user plugin was just installed and may assist with the adoption flow.

## In Scope

- Creating and configuring `.tsuku.toml` for shirabe
- Declaring koto and any other tools with appropriate version pinning
- Updating CI workflows to use project config instead of manual installs
- Collecting friction throughout the process (UX issues, gaps, surprises)
- Evaluating what 0.9.0 fixed vs. what remains from the original friction log

## Out of Scope

- Adopting `.tsuku.toml` in other repos (just shirabe for now)
- Changes to tsuku itself (we're filing issues, not fixing them)
- Broader new contributor onboarding experience

## Research Leads

1. **What changed in tsuku 0.9.0 that affects `.tsuku.toml` adoption?**
   Check release notes and merged PRs to see which original friction points (org-scoped recipes, missing adoption guide, tool discovery) are resolved vs. still open.

2. **What does the end-to-end setup experience look like on 0.9.0?**
   Walk through `tsuku init`, declaring tools, `tsuku install`. This is the core friction log surface -- the literal "create and use" flow with current tooling.

3. **Which tools should shirabe declare, and at what version pinning?**
   koto is required (>= 0.2.1 per README). gh, jq are used in scripts and CI. Need to check which have tsuku recipes, whether org-scoped names work in config, and decide pinning strategy.

4. **How should CI workflows change to use `.tsuku.toml`?**
   validate-templates.yml currently does its own `tsuku install tsukumogami/koto`. Release workflows use gh and jq. What's the intended CI pattern -- `tsuku install -y` with no args?

5. **Does the tsuku-user plugin provide useful guidance for `.tsuku.toml` adoption?**
   Test whether it helps with setup, config editing, or troubleshooting. If it doesn't cover project config, that's itself a friction finding.

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
      references -- not paraphrases.
   4. What behavior change counts as success? Look for acceptance criteria,
      stated outcomes, measurable goals in issues or linked docs.
   5. Is it already built? Search the codebase and existing docs for prior
      implementations or partial work.
   6. Is it already planned? Check open issues, linked design docs, roadmap
      items, or project board entries.

   ## Calibration

   Produce a Calibration section that explicitly distinguishes:

   - **Demand not validated**: majority of questions returned absent or low
     confidence, with no positive rejection evidence. Flag the gap.
   - **Demand validated as absent**: positive evidence that demand doesn't exist
     or was evaluated and rejected.

   Do not conflate these two states.
