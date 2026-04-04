# Lead: What patterns from the private tools plugin should be adopted?

## Findings

### Gap Analysis: Private vs Public Skills

The private tools plugin has 49 skills. Shirabe has 11. But many of the private skills are already installed into the workspace as `tsukumogami:*` plugin skills (visible in the skill list), meaning they're accessible at runtime even though they don't live in shirabe's source. The gap analysis below focuses on what matters structurally for the VISION doc workflow question.

**Already in shirabe as first-class skills (11):**
decision, design, explore, plan, prd, private-content, public-content, release, review-plan, work-on, writing-style

**In private plugin AND installed as tsukumogami:* workspace skills (38+):**
approve, bash-development, bug-report, ci, cleanup, command-authoring, competitive-analysis, complete-milestone, decision-record, design-doc, docstatus, done, fix-pr, github-milestone, go-development, groom, implement, implementation-diagram, implement-doc, issue, issue-drafting, issue-filing, issue-introspection, issue-staleness, just-do-it, merged, nodejs, planning-context, pr-creation, prepare-release, qa, qa-explore, release-planning, roadmap, rust-development, skill-authoring, spike-report, sprint, state-management, triage, try-it, upstream-context, web-development

### The 5 "Deferred" Artifact Types

Shirabe's crystallize framework lists 5 deferred types: Roadmap, Spike Report, Decision Record, Competitive Analysis, and Prototype. However, the current state is more nuanced than "deferred" implies:

1. **Decision Record** -- Already shipped in shirabe. The `decision` skill handles Tier 3-4 decisions. The `phase-5-produce-decision.md` handoff exists and routes to `/decision`. The private `decision-record` skill is a format/validation reference (ADR structure, lifecycle, frontmatter schema), not a workflow driver. Shirabe's `/decision` skill IS the workflow. What's missing is only the static reference document that defines ADR formatting rules.

2. **Spike Report** -- Production template exists in shirabe's `phase-5-produce-deferred.md`. The explore skill can already produce spike reports directly in Phase 5. The private `spike-report` skill adds lifecycle rules (Draft -> Complete), validation rules, label lifecycle (needs-spike -> tracks-plan), and quality guidance. These are reference standards, not workflow drivers.

3. **Roadmap** -- Production template exists in shirabe's `phase-5-produce-deferred.md`. Explore can produce roadmaps. The private `roadmap` skill adds per-feature `needs-*` annotations, lifecycle (Draft -> Active -> Done), `/plan` integration for decomposing roadmaps into issues, and sequencing rationale quality checks.

4. **Competitive Analysis** -- Production template exists in shirabe's `phase-5-produce-deferred.md` with public-repo rejection logic. The private `competitive-analysis` skill adds lifecycle (Draft -> Final), validation rules, quality guidance for each section, and the immutable-snapshot philosophy (finalized analyses don't change; write a new one).

5. **Prototype** -- Handled as "unsupported" in `phase-5-produce-deferred.md`. No private skill exists for prototypes either. Both plugins treat prototypes as code artifacts that fall outside document workflows.

### Pattern Categories

The private plugin's skills fall into three categories relevant to VISION:

**Category A: Artifact format/validation references** (decision-record, spike-report, roadmap, competitive-analysis, design-doc, planning-context)
These define document structure, frontmatter schema, lifecycle states, label transitions, and validation rules. They're consumed by other skills (explore, plan, work-on) as references. They don't drive workflows themselves.

**Category B: Workflow orchestrators** (implement-doc, complete-milestone, sprint, implement, groom, triage)
These are multi-phase workflow drivers. implement-doc orchestrates implementing all issues from a design doc in a single PR. complete-milestone validates milestone completion. sprint sets up isolated clone directories for feature work. These are operational patterns.

**Category C: Development/CI helpers** (go-development, bash-development, rust-development, nodejs, web-development, pr-creation, ci, qa, etc.)
Language-specific and CI/review patterns. Peripheral to artifact workflows.

### Relevance to VISION Doc Workflow

A VISION document workflow (project idea -> requirements) would need:

1. **Roadmap** -- VISION naturally decomposes into a roadmap of features. The roadmap artifact type is the bridge between "I have a project idea" and "I have a set of features to write PRDs for."

2. **Spike Report** -- Feasibility questions arise during vision exploration ("Can we even do X?"). The spike report captures go/no-go decisions that gate whether features enter the roadmap.

3. **Decision Record** -- Architectural decisions made during visioning need permanent records. Already partially shipped via `/decision`.

4. **Competitive Analysis** -- Market research during visioning. Private-only, so irrelevant for shirabe's public scope.

5. **Prototype** -- Not a document artifact. Remains out of scope for both plugins.

### What's Really Missing in Shirabe

The "deferred" framing is misleading. Shirabe already produces 3 of the 5 deferred types (roadmap, spike, competitive analysis) through `phase-5-produce-deferred.md`. What it lacks are the **reference standards** that define quality bars, lifecycle management, and validation rules for those produced artifacts. The private plugin has these as standalone skills that other workflows (plan, work-on, triage) consume.

The actual gaps for a VISION workflow are:

1. **Roadmap reference standard** -- How /plan decomposes a roadmap into per-feature issues with needs-* labels. Without this, a produced roadmap is a static document with no downstream integration.

2. **Spike report reference standard** -- Lifecycle, validation, label transitions. Without this, produced spikes lack quality enforcement and can't be tracked by plan/work-on.

3. **ADR reference standard** -- Format rules that /decision and /explore already partially enforce but without a canonical reference. The decision skill handles workflow; the missing piece is the document standard that other skills can validate against.

4. **Planning context** -- The scope/visibility detection logic that determines which sections appear in documents. Already in private plugin, already installed as tsukumogami:planning-context. Shirabe's skills inline this logic rather than referencing a shared standard.

## Implications

### Ship Independently, Not With VISION

The 5 deferred artifact types do NOT need to ship alongside a VISION doc workflow. Here's why:

1. **Shirabe already produces these artifacts.** The phase-5-produce-deferred.md templates work today. What's missing is post-production quality enforcement, not production capability.

2. **VISION is a new artifact type, not a prerequisite for existing ones.** A VISION doc workflow would consume roadmaps, spikes, and ADRs as downstream artifacts. But those artifact types function without VISION -- they're already being used through explore -> crystallize -> produce.

3. **The reference standards are independently valuable.** Adding roadmap/spike/ADR reference skills to shirabe improves quality for existing workflows (explore, plan, work-on) regardless of whether a VISION workflow exists.

4. **Competitive analysis stays private.** Since shirabe is public and competitive analysis is private-only, this artifact type can only exist in the private plugin. It's already there. No action needed for shirabe.

### Recommended Adoption Order

**Phase 1 (independent, do first):**
- Spike report reference standard -- simplest lifecycle (2 states), already produced by explore
- Decision record reference standard -- /decision skill exists, just needs the formatting companion
- Roadmap reference standard -- most complex (lifecycle + plan integration), but highest value for multi-feature work

**Phase 2 (with or after VISION):**
- VISION doc type as a new artifact type in the crystallize framework
- VISION -> Roadmap decomposition pathway
- Planning context as a shared skill (currently inlined in multiple places)

**Do not adopt into shirabe:**
- Competitive analysis (private-only)
- Prototype (not a document artifact)
- Category B orchestrators (implement-doc, complete-milestone, sprint) -- these are operational workflows that work as tsukumogami:* plugin skills and don't need to move into shirabe's core

## Surprises

1. **The "deferred" label understates current capability.** Shirabe already produces 3 of the 5 deferred types. The crystallize framework identifies them, and phase-5-produce-deferred.md writes them. What's deferred is lifecycle management and validation, not production.

2. **The private plugin's artifact reference skills are format standards, not workflow drivers.** I expected find self-contained workflows. Instead, they're reference documents consumed by other skills -- closer to schema definitions than command implementations.

3. **The private plugin has 38+ skills installed as tsukumogami:* workspace skills.** The gap between shirabe and the private plugin is much smaller than the directory listing suggests. Most private skills are already accessible to users via the tsukumogami plugin installation.

4. **Roadmap is the most architecturally significant gap.** It's the only deferred type with deep /plan integration (per-feature needs-* annotations, issue decomposition, tracking labels). The others are lighter additions.

## Open Questions

1. **Should reference standards live in shirabe or stay in the private plugin?** Currently the private plugin owns the canonical format definitions, and shirabe inlines simplified versions. Moving them to shirabe would make them available to public contributors but creates a maintenance dual-source risk.

2. **Does a VISION doc need its own artifact type, or is it a Roadmap with a different entry point?** A VISION doc that decomposes into features with PRD/design needs is structurally identical to a Roadmap with needs-* annotations. The difference might be scope (VISION = strategic, Roadmap = tactical) rather than format.

3. **How should /plan handle roadmap decomposition differently from design doc decomposition?** The private roadmap skill describes per-feature needs-* labels that /plan uses, but shirabe's /plan skill doesn't reference this pattern.

4. **What happens to the tsukumogami:* installed skills when reference standards move to shirabe?** Would the private plugin versions become thin wrappers that delegate to shirabe, or would they diverge?

## Summary

Shirabe already produces 3 of the 5 "deferred" artifact types through explore's Phase 5 -- what it actually lacks are the reference standards (lifecycle rules, validation, label integration) that give those artifacts quality enforcement and downstream workflow integration. These reference standards should ship independently before any VISION doc workflow, since they improve existing explore/plan/work-on workflows regardless of whether VISION exists. The biggest open question is whether VISION is truly a new artifact type or simply a strategic-scope Roadmap with a different entry point, since their structure (multi-feature sequencing with per-feature needs annotations) appears identical.
