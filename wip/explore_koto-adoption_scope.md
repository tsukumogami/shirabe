# Explore Scope: koto-adoption

## Visibility

Public

## Core Question

What would it take to convert all shirabe skills to use koto for state persistence, phase gatekeeping, and deterministic verification — and what koto features are missing that need to be built first?

## Context

The /work-on skill already uses koto (init, next, evidence submission, gates). The other 7+ skills (explore, design, prd, plan, decision, release, review-plan) all manage their own state via wip/ files, enforce phase ordering through prose instructions, and handle verification through agent-interpreted checks. The user wants to push deterministic logic out of agent context and into koto, increase visibility into workflow decisions, and identify koto feature gaps that become issues in the koto repo. The output should be a PRD or roadmap for shirabe, with some items blocked by koto feature requests.

## In Scope

- Audit of all shirabe skills: what state they manage, what gates they enforce, what verification they do
- Gap analysis: what skills do in prose that koto could do deterministically
- Koto feature requests: missing primitives (polling/wait gates, decision capture, artifact validation, etc.)
- Phased adoption plan: which skills convert first, what koto features are prerequisites
- PRD or roadmap artifact for shirabe

## Out of Scope

- Actually converting any skill (that's implementation work)
- Designing koto features in detail (that's koto-side work, driven by the feature requests)
- Changes to the /work-on skill (already uses koto)

## Research Leads

1. **Current state: how do each of the non-koto skills manage state, phases, and verification today?**
   Read each skill (explore, design, prd, plan, decision, release, review-plan) and catalog: what wip/ files they create, what resume logic they use, what phase ordering they enforce, what verification checks they run (CI polling, file existence, git state, etc.).

2. **What can koto do today?**
   Read koto's current capabilities: templates, phases, gates, evidence submission, decisions, state files. Understand what primitives are available and what their limitations are.

3. **What does /work-on's koto integration look like in practice?**
   Read the work-on koto template and the skill's koto integration code. Understand the pattern: what works well, what's awkward, what's missing. This is the reference implementation.

4. **What patterns appear across skills that koto could standardize?**
   Look for repeated patterns: "check if file exists then resume at phase N", "poll CI until green", "ask user to confirm", "write findings to wip/", "launch parallel agents and collect results". These are candidates for koto primitives.

5. **What koto features are needed but don't exist?**
   Cross-reference the skill audit (lead 1) with koto's capabilities (lead 2) to identify gaps. Categorize: easy additions, medium features, hard/architectural changes.

6. **Is there evidence of demand for this?** (lead-adversarial-demand)
   You are a demand-validation researcher. Investigate whether evidence supports
   pursuing this topic. Report what you found. Cite only what you found in durable
   artifacts. The verdict belongs to convergence and the user.
