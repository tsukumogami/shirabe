# /prd Scope: gha-doc-validation

## Problem Statement

shirabe defines five doc formats (Design, PRD, VISION, Roadmap, Plan) with frontmatter schemas, status lifecycles, and required sections — but only Plan has any CI validation, and that validation is non-reusable (hardcoded path, runs only in shirabe's own repo). Repos that adopt shirabe's doc formats have no way to enforce structural correctness in CI without copying validation scripts manually, which creates a maintenance burden and means updates never reach downstream repos automatically. Validation logic needs to live in one place (shirabe) and be consumed via a reusable GHA workflow so improvements reach all adopters on every run.

## Initial Scope

### In Scope

- Reusable GitHub Actions workflow (`validate.yml`) hosted in shirabe, callable via `uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1` from any downstream repo
- Static/deterministic validation tier covering all five persistent doc formats: frontmatter field completeness, status enum validity, frontmatter/body status synchronization, required section presence, and format-specific structural rules (Mermaid syntax in Plan, reserved section presence in Roadmap, public-repo section exclusion in VISION, etc.)
- Schema versioning: a `schema: <format>/<version>` frontmatter field for all doc formats (Plan already uses `schema: plan/v1`), giving validators a stable anchor and enabling format evolution
- Configuration-driven design: one reusable workflow with optional config input; start with no config required and add configuration options incrementally
- Version pinning via tags (`@v1`) so downstream repos can control when they upgrade
- Thin caller workflow template: approximately 10 lines, one `uses:` reference, no scripts to copy

### Out of Scope

- AI-powered semantic validation tier (future direction — acknowledged but not in v1 requirements)
- Mermaid diagram validation (explicitly deferred: the existing validator needs architectural splitting before it can ship portably)
- Non-GHA CI systems
- Per-format separate reusable workflows (one configurable workflow is the design)
- Migration of any specific downstream repo's existing copied scripts (the new system serves future adopters; migration is downstream repos' choice)
- Decision records (no persistent committed format to validate)
- Cross-repo upstream field format validation (depends on `cross-repo-references.md` spec that isn't currently accessible)

## Research Leads

1. **What should the acceptance criteria look like for "reusable workflow" consumption?** Exploration established the thin-caller pattern and `workflow_call` semantics, but hasn't defined what a downstream repo's setup PR should look like end-to-end. The PRD needs concrete acceptance criteria grounded in a worked example.

2. **Which formats are in scope for v1 vs. later releases?** Plan already has a (non-reusable) validator. Design seems highest-value to add next (most used upstream dependency). The PRD needs to decide whether v1 covers all five formats or starts with a subset.

3. **How does the schema versioning field propagate to existing docs?** The `schema: plan/v1` pattern is proven for Plan. Adopting it for Design, PRD, VISION, and Roadmap means existing docs in downstream repos are missing the field. Grandfathering approach (cutoff date, optional enforcement) needs to be defined as a requirement.

4. **What does the user story look like for a downstream repo maintainer adopting this?** The PRD needs user stories. Exploration surfaced the gap (koto and niwa have design docs with no CI validation) but didn't define the specific personas and their acceptance criteria.

## Coverage Notes

- **AI tier**: explicitly deferred. The PRD should acknowledge the tier exists as a future direction and note that the `ANTHROPIC_API_KEY` secret mechanism is already proven in shirabe's `run-evals.yml`. Requirements for the AI tier are not part of this PRD.
- **Grandfathering / cutoff date**: the research found that the private tools validation suite uses a hardcoded check-cutoff date to exempt pre-existing docs. The PRD needs to define how this works as a configurable requirement, not hardcode it.
- **Blocking vs. advisory**: the static tier should run as a required PR check (blocking), not advisory. This decision wasn't fully surfaced in exploration — the PRD should make it explicit as a requirement.
- **Runner quota**: all compute for downstream repos' validation runs against shirabe's GitHub Actions minutes. The PRD should note this as a known limitation and whether v1 needs a solution (e.g., docs on using the `@github-token` context for billing to the caller's org).

## Decisions from Exploration

- **Single configurable reusable workflow**: one `validate.yml` with config-driven behavior; no config required at launch; add options incrementally. Per-format separate workflows are out.
- **Private tools repo: not referenced**: shirabe is the new canonical home for all doc validation logic. No dependency on or reference to prior script copying patterns.
- **AI semantic validation tier: future work**: vision doc acknowledges direction but does not define requirements or acceptance criteria for it.
- **Schema and versioning: foundational**: the frontmatter-derived `schema: <format>/<version>` field (extending Plan's existing `schema: plan/v1`) is part of the system's foundation, not an optional enhancement.
