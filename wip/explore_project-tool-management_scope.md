# Explore Scope: project-tool-management

## Visibility

Public

## Core Question

How should shirabe adopt tsuku's new `.tsuku.toml` project-level tool management, both for local development and CI? We're treating this as a friction log exercise to surface UX issues worth filing back against tsuku.

## Context

Tsuku recently shipped project-level tool management via `.tsuku.toml` -- a TOML file declaring required tools and version constraints. Discovery walks up from cwd, `tsuku install` (no args) batch-installs everything. Shirabe already depends on koto (>= 0.2.1), gh, jq, python3, and claude for various workflows. CI currently installs tools manually (e.g., `tsuku install tsukumogami/koto -y` in validate-templates.yml). The user wants to adopt `.tsuku.toml` and collect a friction log of the adoption experience to help tsuku improve the process.

## In Scope

- Creating and configuring `.tsuku.toml` for shirabe
- Declaring koto and any other tools with appropriate version pinning
- Updating CI workflows to use project config instead of manual installs
- Collecting friction throughout the process (UX issues, gaps, surprises)

## Out of Scope

- New contributor onboarding experience (broader than this exploration)
- Adopting `.tsuku.toml` in other repos (just shirabe for now)
- Changes to tsuku itself (we're filing issues, not fixing them)

## Research Leads

1. **What does the end-to-end `.tsuku.toml` setup experience look like?**
   Walk through `tsuku init`, declaring tools, and `tsuku install`. This is the core friction log surface -- the literal "create and use" flow.

2. **Which tools should shirabe declare, and at what version pinning?**
   koto is required (>= 0.2.1 per README). gh, jq, python3 are also used in scripts and CI. Need to check which have tsuku recipes and decide pinning strategy (exact, prefix, latest).

3. **How should CI workflows change to use `.tsuku.toml` instead of manual tool installs?**
   validate-templates.yml currently does its own `tsuku install tsukumogami/koto`. Release workflows use gh and jq. What's the intended CI pattern -- `tsuku install` with no args?

4. **What are the security and permission constraints for `.tsuku.toml` in CI?**
   The design doc mentions 0600 permission checks and root guards. GitHub Actions runners may not match those assumptions. Need to understand if CI is a supported use case.

5. **Does tsuku document a recommended adoption path for existing projects?**
   Is there a guide, a skill, or prior art for "I have a repo, I want to add .tsuku.toml"? If not, that's itself a friction finding.

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
