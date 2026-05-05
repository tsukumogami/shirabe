# Exploration Findings: gha-doc-validation

## Core Question

What should shirabe's reusable GitHub Actions validation system look like — what tiers of validation exist, what each tier validates, and how downstream repos consume them? This is the starting point for a public vision document.

## Round 1

### Key Insights

- **Only Plan has CI validation today; four other formats have none.** The `validate-plan.sh` + `check-plan-docs.yml` pair is the only doc-type CI check in shirabe. Design, PRD, VISION, and Roadmap have zero CI-enforced validation — only agent-side `transition-status.sh` mutators that run during skill execution. A PR can land a design doc with a missing required field and nothing catches it. (existing-validation)

- **The private tools repo contains a full design-doc validation suite** — 4 workflows and ~10 modular scripts (`frontmatter.sh`, `sections.sh`, `status-directory.sh`, `implementation-issues.sh`, `mermaid.sh`). These exist in tsuku as byte-for-byte copies with no sync mechanism. The user's decision: draw inspiration, don't reference or depend on it. Shirabe becomes the new canonical home. (script-copy-pattern)

- **The GHA reusable workflow pattern is technically clean and already has a live example in the codebase.** `workflow_call` runs in the caller's repo context by default — no file copying needed. `required: false` secrets enable graceful AI tier degradation. koto's `check-template-freshness.yml` + shirabe's `check-templates.yml` caller is a working proof of the pattern. (reusable-gha-patterns)

- **Five doc formats (Design, PRD, VISION, Roadmap, Plan) all have static-checkable invariants.** Four rules apply across all: required frontmatter field presence, closed-enum status validity, frontmatter/body status sync, required section presence. Plan has the richest additional structural rules. Decision produces only ephemeral wip artifacts — nothing to validate in CI. (doc-format-schemas)

- **The AI tier has clear design but no demand artifact.** The jury-validation prompts in PRD and VISION skills are ready-made inputs for GHA AI validation. Haiku is cheap (~$0.001–0.003/doc) and sufficient. The tier must annotate, not gate. But no issue, acceptance criteria, or roadmap entry requests this capability — it's a design hypothesis, not a stated requirement. (ai-validation, adversarial-demand)

- **Plan's `schema: plan/v1` pattern is the model for the whole system.** It's the only format with a versioned schema field, and it's the only format with CI validation. Not a coincidence. Extending this pattern to all formats gives validators a reliable anchor and enables future evolution of each format independently.

### Tensions

- **AI tier: v1 commitment vs. future direction.** The user's direction: future work. Vision doc acknowledges it, doesn't commit to it.
- **Single workflow vs. per-format workflows.** The user's direction: single configurable workflow; start with no config, add options incrementally.

### Gaps

- **`cross-repo-references.md` not found.** Multiple format specs reference this file for the cross-repo upstream field format. Validators checking upstream field integrity will need this spec defined first.
- **Mermaid diagram validation explicitly deferred.** The private tools suite has `mermaid.sh` (1024 lines, 21 rules), but this is out of scope per PRD and issue #4's own acceptance criteria.
- **Grandfathering / cutoff dates.** The private tools scripts use a hardcoded cutoff date to exempt pre-existing docs from new checks. A reusable system needs a configurable equivalent — otherwise old docs in downstream repos fail new validators on day one.

### Decisions

- Single configurable reusable workflow, no config required at launch, expand incrementally.
- Private tools repo: inspiration only, not referenced, not a migration dependency.
- AI tier: future work; vision doc acknowledges direction, does not define requirements.
- Schema/versioning (frontmatter-derived, extending `schema: plan/v1`): part of the vision, foundational to validation.

### User Focus

The user is focused on the static validation tier as the launchable capability, wants the AI tier acknowledged but not committed, wants schema/versioning as a foundational element that makes everything else more reliable, and wants the vision doc to be a public-facing commitment to the direction — not a detailed design.

## Accumulated Understanding

The shirabe GHA validation system is a two-layer architecture: a **static/deterministic tier** (immediate commitment) and a **semantic/AI tier** (future direction). The vision doc covers the first layer with enough clarity to drive implementation, and names the second as a direction without committing to it.

**The static tier** provides reusable GitHub Actions workflows that downstream repos consume via `uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1`. No scripts are copied; all validation logic lives in shirabe. The pattern already exists in the codebase (koto's `check-template-freshness.yml`) and is technically clean.

**What the static tier validates, and how:**
All five persistent doc formats (Design, PRD, VISION, Roadmap, Plan) share four universal checks: frontmatter field completeness, status enum validity, frontmatter/body status synchronization, and required section presence. Individual formats add structural rules (Plan's Mermaid syntax and issue table format; VISION's public-repo section exclusion rules; Roadmap's reserved section requirements). Validation is driven by the format's frontmatter schema field (extending `schema: plan/v1` to all formats), which gives validators a stable anchor and enables format evolution independently.

**What makes this tractable:**
- The validate-plan.sh script is a production-quality template with tested exit codes, awk-based frontmatter extraction, and git-tracking upstream checks. These patterns replicate to other formats.
- The GHA reusable workflow pattern is well-understood; koto already publishes one that shirabe calls.
- The transition-status.sh scripts for Design, PRD, VISION, and Roadmap already know the allowed status values and required content preconditions — these are the source of truth for what CI should enforce.

**What the AI tier eventually validates (future work):**
Semantic completeness that static analysis can't check: whether a section is substantively filled vs. syntactically present, whether a PRD requirement is testable, whether a VISION thesis is a hypothesis vs. a problem statement, whether a design doc's alternatives section contains genuine alternatives vs. strawmen. Non-blocking (annotate, not gate) because API key availability is optional and LLM judgment has false-positive risk. The existing jury-validation prompts in PRD and VISION skills are the content foundation for this tier when it's built.

**Open questions for the vision doc to address:**
1. Which formats are in scope for v1 of the static tier? (Plan is already done in non-reusable form; Design and PRD seem highest value to add next.)
2. How does the schema/versioning field propagate to existing docs without breaking them? (Grandfathering / cutoff date approach.)
3. Where does the `cross-repo-references.md` spec live, and does CI check upstream field format?
4. Does the static tier run as a required PR check (blocking) or an advisory check?

## Decision: Crystallize
