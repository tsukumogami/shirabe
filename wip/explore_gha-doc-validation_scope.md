## Visibility

Public

## Core Question

What should shirabe's reusable GitHub Actions validation system look like — what tiers of validation exist, what each tier validates, and how downstream repos consume them? This is the starting point for a public vision document that defines the scope and shape of the system before implementation work begins.

## Context

shirabe defines several document formats (Design docs, PRDs, VISION docs, Roadmaps, Plans, Decision records, Spike reports, Competitive analyses), each with frontmatter schemas and status lifecycles. Skills manage their lifecycle, and the private tools repo uses internal CI to validate some of these. The PRD explicitly commits to reusable GHA workflows (R5, R6, R6a) but no public reusable workflows exist yet. tsuku has a working example of plan-doc validation (validate-plan.sh + check-plan-docs.yml), but these scripts originated in the private tools repo and were copied into tsuku — the old pattern. The new model is reusable GHA workflows where all validation code lives in shirabe and downstream repos reference it via `uses:` — no script copying. The user wants a public vision document — not a design doc — that captures what the system should be before anyone starts implementing.

## In Scope

- Defining what a "reusable GHA workflow" means for shirabe's doc validation
- Tiered validation: deterministic (always runs) vs. AI-powered (optional, requires ANTHROPIC_API_KEY)
- What each doc format needs validated at the deterministic tier (frontmatter, required sections, status transitions, upstream chain)
- What AI-powered validation could provide that static analysis can't (content quality, completeness, "dev-time content trimmed")
- How downstream repos consume these workflows (thin caller pattern, config-driven)
- Scope of the vision doc itself — what it should cover and at what level of detail

## Out of Scope

- Detailed implementation design (which scripts, how they're structured) — that's for a follow-up design doc
- Per-skill validation details (individual frontmatter schemas) — those are inputs, not outputs
- Mermaid dependency diagram validation (explicitly deferred in PRD due to the 1024-line validator needing architectural work)
- Non-GHA CI systems

## Research Leads

1. **What validation does the existing tsuku plan validation do, and how is it structured for reuse?**
   The validate-plan.sh + check-plan-docs.yml pair is the best internal reference. Understanding what it validates (and what it doesn't) grounds the vision in what's already proven.

2. **What frontmatter schemas and status lifecycles do the current doc formats define?**
   The validation scope depends entirely on what each format requires. Need to inventory all formats and their current rules before describing what the validation system should enforce.

3. **What do other documentation CI frameworks validate, and at what tiers?**
   Several projects validate doc quality in CI (markdownlint, Vale, mdBook, etc.). Understanding what static analysis can and can't catch informs where the AI tier adds distinct value.

4. **What would AI-powered doc validation actually check, and is the ANTHROPIC_API_KEY gating practical?**
   The user described checking whether a doc answers the question it poses, whether dev-time content was trimmed, etc. Need to understand what these checks look like in practice and whether GHA + API key is viable architecture.

5. **What does "reusable GHA workflow" imply for downstream repo setup and version pinning?**
   The PRD describes a thin caller pattern (`uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1`). What does this mean for configuration, secrets handling (for ANTHROPIC_API_KEY), and versioning strategy?

6. **What does the private tools repo script-copying pattern look like, and what gaps does it expose that reusable GHA workflows would fix?**
   The existing validation scripts in tsuku came from the private tools repo via copying. Understanding what that pattern required (what scripts exist, how they're invoked, where duplication occurs) makes the "all code lives in shirabe" model concrete by contrast.

7. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
   You are a demand-validation researcher. Investigate whether evidence supports pursuing this topic. Report what you found. Cite only what you found in durable artifacts. The verdict belongs to convergence and the user.

   ## Visibility

   Public

   Respect this visibility level. Do not include private-repo content in output that will appear in public-repo artifacts.

   ## Six Demand-Validation Questions

   Investigate each question. For each, report what you found and assign a confidence level.

   Confidence vocabulary:
   - **High**: multiple independent sources confirm
   - **Medium**: one source type confirms without corroboration
   - **Low**: evidence exists but is weak
   - **Absent**: searched relevant sources; found nothing

   Questions:
   1. Is demand real? Look for distinct issue reporters, explicit requests, maintainer acknowledgment.
   2. What do people do today instead? Look for workarounds in issues, docs, or code comments.
   3. Who specifically asked? Cite issue numbers, comment authors, PR references.
   4. What behavior change counts as success? Look for acceptance criteria, stated outcomes.
   5. Is it already built? Search the codebase and existing docs for prior implementations.
   6. Is it already planned? Check open issues, linked design docs, roadmap items.

   ## Calibration

   Produce a Calibration section distinguishing "demand not validated" from "demand validated as absent."
