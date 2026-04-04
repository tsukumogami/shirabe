# Current-State Analysis: Roadmap vs Plan Artifact Relationship

## Side-by-Side Comparison

### Frontmatter Fields

| Field | Roadmap | Plan | Relationship |
|-------|---------|------|--------------|
| `status` | Required (Draft/Active/Done) | Required (Draft/Active/Done) | Identical values and semantics |
| `theme` | Required (1 paragraph) | -- | Roadmap-only |
| `scope` | Required (1 paragraph) | -- | Roadmap-only (Plan uses Scope Summary section instead) |
| `schema` | -- | Required (`plan/v1`) | Plan-only |
| `execution_mode` | -- | Required (`single-pr` / `multi-pr`) | Plan-only |
| `upstream` | -- | Optional (path to source doc) | Plan-only |
| `milestone` | -- | Required (milestone name) | Plan-only |
| `issue_count` | -- | Required (integer) | Plan-only |

**Frontmatter overlap: 1 of 7 distinct fields shared (14%).** The `status` field is the only common element, with identical allowed values.

### Required Sections

| Section | Roadmap | Plan | Relationship |
|---------|---------|------|--------------|
| Status | 1st (lifecycle state) | 1st (lifecycle state) | Identical purpose and position |
| Theme | 2nd (initiative + why sequencing matters) | -- | Roadmap-only |
| Scope Summary | -- | 2nd (1-2 sentence description) | Plan-only (analogous to frontmatter `scope` in roadmap) |
| Features | 3rd (ordered list with names, deps, status, needs annotations) | -- | Roadmap-only |
| Decomposition Strategy | -- | 3rd (walking skeleton / horizontal / feature-by-feature) | Plan-only |
| Issue Outlines | -- | 4th (single-pr mode structured outlines) | Plan-only |
| Implementation Issues | -- | 5th (table with links, deps, complexity) | Plan-only |
| Sequencing Rationale | 4th (why features ordered this way) | -- | Roadmap-only (analogous to Implementation Sequence) |
| Dependency Graph | -- | 6th (Mermaid diagram) | Plan-only |
| Implementation Sequence | -- | 7th (critical path, parallelization) | Plan-only (analogous to Sequencing Rationale) |
| Progress | 5th (which features done/in-progress/not-started) | -- | Roadmap-only (analogous to strikethrough tracking in Plan) |

**Section overlap: 1 of 10 distinct sections identical (Status). 2 pairs are analogous (Scope, Sequencing). 7 are unique to one type.**

### Lifecycle States

| State | Roadmap | Plan | Relationship |
|-------|---------|------|--------------|
| Draft | Under development, feature list may change | Plan being written during /plan phases | Identical name, analogous meaning |
| Active | Feature list locked, execution in progress | Implementation underway | Identical name, analogous meaning |
| Done | All features delivered or dropped | Implementation complete | Identical name, analogous meaning |

**Lifecycle overlap: 100% identical states.** Both use Draft -> Active -> Done with the same linear progression. Transition triggers differ (human approval vs issue creation for Active; all features complete vs all issues closed for Done).

### Transition Rules

| Rule | Roadmap | Plan |
|------|---------|------|
| Draft -> Active | Human must approve; feature list complete | multi-pr: GitHub issues created; single-pr: /implement-doc starts |
| Active -> Done | All features terminal (delivered or dropped) | multi-pr: all issues closed; single-pr: PR merged |
| Done -> any | Forbidden (historical record) | Implicit (moved to done/ directory) |
| Active -> Draft | Forbidden | Not specified |

**Transition overlap: Same state machine shape. Triggers are different but structurally parallel** (approval gate -> execution gate -> completion gate).

### Validation Rules

| Rule Category | Roadmap | Plan |
|---------------|---------|------|
| Frontmatter completeness | status, theme, scope required | schema, status, execution_mode, milestone, issue_count required |
| Status consistency | Frontmatter status must match body Status section | Frontmatter status must match body Status section |
| Section ordering | All 5 sections present and in order | All 7 sections present and in order |
| Minimum content | At least 2 features | At least 1 issue (implied by issue_count) |
| Status gating | Must be Active to serve as upstream for /prd or /plan | Must be Draft or Active to be consumed by /work-on or /implement-doc |
| File location | `docs/roadmaps/ROADMAP-<name>.md` (no movement) | `docs/plans/PLAN-<topic>.md` (moves to `done/` on completion) |

**Validation overlap: Same pattern (frontmatter check + status consistency + section ordering + status gating). Different specific fields and thresholds.**

### Work Item Granularity

| Aspect | Roadmap | Plan |
|--------|---------|------|
| Primary unit | Feature | Issue |
| Granularity | PRD-level (one feature = one PRD) | Implementation-level (one issue = one PR or code change) |
| Tracking mechanism | Needs annotations (`needs-design`, `needs-spike`, etc.) | Complexity labels (`simple`, `testable`, `critical`) |
| Dependencies | Feature-to-feature, explicit in Features section | Issue-to-issue, in table + Mermaid graph |
| Status tracking | Per-feature status in Features section | Strikethrough in table + class changes in Mermaid |
| Downstream artifacts | PRDs, design docs, spike reports | Code PRs |

### Label System

| Aspect | Roadmap | Plan |
|--------|---------|------|
| Label type | `needs-*` annotations per feature | Complexity labels per issue |
| Purpose | Indicate what upstream artifact is needed | Indicate validation depth required |
| Values | needs-design, needs-spike, needs-prd, needs-decision | simple, testable, critical |
| Applied by | /plan during decomposition | /plan during decomposition |

### File Location and Movement

| Aspect | Roadmap | Plan |
|--------|---------|------|
| Path pattern | `docs/roadmaps/ROADMAP-<name>.md` | `docs/plans/PLAN-<topic>.md` |
| Movement on completion | None (stays in place) | Moves to `docs/plans/done/` |
| Naming convention | kebab-case after `ROADMAP-` | kebab-case after `PLAN-` |

---

## Difference Classification

### Fundamental Differences (cannot be parameterized away)

1. **Abstraction level.** Roadmaps operate at portfolio level (features -> PRDs); Plans operate at implementation level (issues -> PRs). This is the defining distinction. A roadmap's "feature" is a Plan's "upstream document." These are different levels in a work breakdown hierarchy, not different views of the same level.

2. **Work item semantics.** Roadmap features track artifact production (PRDs, designs, spikes). Plan issues track code implementation (or, when fed by a roadmap, artifact production -- but this is the roadmap-input special case, not the Plan's primary mode). The default work item type differs.

3. **Dependency visualization.** Plans have a formal Mermaid dependency graph with defined node formats, status classes, and rendering rules. Roadmaps express dependencies as prose annotations in the Features section. This isn't just a format difference -- it reflects that Plan dependencies are machine-consumable (used by /work-on to determine readiness) while Roadmap dependencies are human-readable guidance.

4. **Execution machinery.** Plans integrate with GitHub (milestones, issues, labels) and downstream skills (/work-on, /implement-doc). Roadmaps integrate with /plan as an input, not with execution tools directly. Plans are executable; roadmaps are directive.

5. **Progress tracking mechanism.** Plans use strikethrough + Mermaid class transitions (machine-readable state changes). Roadmaps use a prose Progress section (human-updated narrative). Different mechanisms reflecting different automation levels.

### Incidental Differences (different naming for the same concept)

1. **Scope expression.** Roadmap uses frontmatter `scope` field; Plan uses a "Scope Summary" body section. Same concept (bounding what's included), different location.

2. **Sequencing rationale.** Roadmap has "Sequencing Rationale" section; Plan has "Implementation Sequence" section. Both explain ordering constraints and parallelization opportunities.

3. **File movement policy.** Roadmaps don't move; Plans move to `done/`. This is a convention choice, not a fundamental constraint. Either approach could apply to either type.

4. **Minimum content threshold.** Roadmaps require 2+ features; Plans imply 1+ issues. The specific number is a policy choice.

5. **Needs annotations vs complexity labels.** Both are per-item classification systems applied during /plan decomposition. The label vocabularies differ because the work item types differ, but the structural role (classify items for downstream routing) is the same.

---

## Overlap Quantification

### Structural Elements

| Category | Shared | Roadmap-only | Plan-only | Overlap % |
|----------|--------|--------------|-----------|-----------|
| Frontmatter fields | 1 (status) | 2 (theme, scope) | 4 (schema, execution_mode, upstream, milestone, issue_count) | 14% |
| Required sections | 1 (Status) | 4 (Theme, Features, Seq Rationale, Progress) | 6 (Scope Summary, Decomp Strategy, Issue Outlines, Impl Issues, Dep Graph, Impl Sequence) | 9% |
| Lifecycle states | 3 (Draft, Active, Done) | 0 | 0 | 100% |
| Transition rules | 2 (Draft->Active, Active->Done) | 2 (Done->any forbidden, Active->Draft forbidden) | 0 specific | ~50% |
| Validation patterns | 3 (frontmatter check, status consistency, section ordering) | 1 (min 2 features) | 2 (schema version, execution mode gating) | 50% |

### Conceptual Patterns

| Pattern | Present in Roadmap | Present in Plan | Shared? |
|---------|-------------------|-----------------|---------|
| Status-gated consumption by downstream skills | Yes | Yes | Yes |
| Per-item dependency tracking | Yes (prose) | Yes (table + Mermaid) | Analogous |
| Per-item classification labels | Yes (needs-*) | Yes (complexity) | Analogous |
| Progress tracking | Yes (Progress section) | Yes (strikethrough + Mermaid) | Analogous |
| Scope bounding | Yes (frontmatter) | Yes (body section) | Analogous |
| Ordering rationale | Yes (Sequencing Rationale) | Yes (Implementation Sequence) | Analogous |
| Naming convention (ARTIFACT-name.md) | Yes | Yes | Yes |

### Overall Assessment

**Raw structural overlap: ~25%.** Only Status section and lifecycle states are truly identical. Most frontmatter and sections are unique to one type.

**Conceptual pattern overlap: ~70%.** Both artifacts follow the same meta-pattern: frontmatter with status -> ordered sections -> lifecycle states -> validation rules -> downstream skill integration. They share the same architectural skeleton but fill it with different content.

**The relationship is hierarchical, not parallel.** A Roadmap is consumed by /plan to produce a Plan. They sit at adjacent levels in the work breakdown structure (portfolio -> implementation). The conceptual overlap comes from both being "structured planning artifacts with lifecycle tracking," but they plan at different granularities for different audiences.

---

## Key Finding

Roadmap and Plan share a common *meta-structure* (status-gated lifecycle, ordered sections, validation rules, downstream skill integration) but diverge on *content semantics* (features vs issues, portfolio vs implementation, directive vs executable). The 5 fundamental differences -- abstraction level, work item semantics, dependency visualization, execution machinery, and progress tracking -- are not parameterizable. They reflect genuinely different roles in the workflow hierarchy. The shared patterns suggest a common base interface or protocol, but the specializations are deep enough that treating them as "modes of one type" would require significant contortion.
