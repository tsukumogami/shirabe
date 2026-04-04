# Architecture Analysis: Roadmap-Plan Relationship Model

## Lead 4: Relationship Model Options

### Option A: Separate Types (Current Design)

Roadmap and Plan are fully independent artifact types. Roadmap has its own
frontmatter schema (status/theme/scope), file location (`docs/roadmaps/`),
required sections (Status, Theme, Features, Sequencing Rationale, Progress),
and lifecycle (Draft -> Active -> Done). Plan has `schema: plan/v1`, lives at
`docs/plans/`, and has entirely different required sections (Status, Scope
Summary, Decomposition Strategy, Issue Outlines, Implementation Issues,
Dependency Graph, Implementation Sequence).

**Trade-offs:**

- Complexity: Low per-type, but grows with each new type. Each has its own
  validation rules, lifecycle, and consuming skill logic.
- Duplication: Moderate. Both have status fields, lifecycle state machines,
  and sequential section ordering rules. The lifecycle pattern
  (Draft -> Active -> Done) is identical.
- Flexibility: High. Each type can evolve independently. Roadmap added
  per-feature `needs-*` annotations without touching Plan format.
- Learning curve: Higher. Users must learn two formats. The relationship
  (roadmap feeds into /plan which produces a PLAN doc) adds a layer of
  indirection.
- Impact on existing code: None -- this is the status quo.

### Option B: Shared Base with Specializations

Define a common artifact base (frontmatter fields like status, lifecycle
states, file location pattern) and specialize for each type. The base would
own: status field, lifecycle state machine (Draft/Active/Done), upstream
linking, and the Status section. Each specialization adds its type-specific
sections and frontmatter fields.

**Trade-offs:**

- Complexity: Medium. The shared base simplifies lifecycle management but
  adds an abstraction layer. Specializations must declare which base
  behaviors they override.
- Duplication: Low. Lifecycle logic, status validation, and upstream linking
  are defined once.
- Flexibility: Medium. Adding a new artifact type means implementing the
  base interface plus specialization. Changes to the base affect all types.
- Learning curve: Medium. Once users learn the base pattern, new types
  are predictable. But the base-vs-specialization split adds conceptual
  overhead.
- Impact on existing code: Significant. The Go `parsePlanDoc()` function
  in workflow-tool hardcodes `schema: plan/v1` detection and Plan-specific
  frontmatter fields (execution_mode, issue_count, milestone). The
  `isPlanDoc()` function uses both frontmatter schema and PLAN- filename
  prefix. Introducing a shared base means either: (a) a new schema version
  that both types share, or (b) keeping separate schemas but factoring
  common validation into shared Go functions. The /implement skill
  explicitly requires `schema: plan/v1` -- a shared base would need to
  preserve this contract or migrate consumers.

### Option C: Single Type with Level/Mode Field

One PLAN artifact with a `level` field: `portfolio` (what roadmaps do today)
or `implementation` (what plans do today). The portfolio mode uses Features
sections; the implementation mode uses Issue Outlines and Implementation
Issues sections.

**Trade-offs:**

- Complexity: Low type count, but high per-type branching. Every consumer
  must check the level field and branch behavior. The /plan skill already
  branches on `input_type: roadmap` -- this would formalize that branching
  into the artifact schema itself.
- Duplication: Lowest. Single frontmatter schema, single lifecycle, single
  file location pattern.
- Flexibility: Low. Portfolio-level and implementation-level artifacts have
  fundamentally different section structures. Forcing them into one format
  means either: (a) many optional sections that are "N/A" depending on mode,
  or (b) a format so generic it loses the structural guarantees that make
  each type useful. The current Plan doc's Issue Outlines section has nothing
  in common with Roadmap's Features section.
- Learning curve: Lowest initial (one type to learn), but the mode-dependent
  behavior creates hidden complexity. "This section is required in portfolio
  mode but forbidden in implementation mode" is harder to internalize than
  "Roadmaps have Features, Plans have Issues."
- Impact on existing code: Very high. The Go `parsePlanDoc()` function
  parses Issue Outlines sections with specific heading patterns
  (`### Issue N: ...`). Portfolio mode would need a parallel parser for
  Features sections. The `PlanMetadata` struct would need the level field,
  and `isPlanDoc()` would match both modes. The /implement skill
  explicitly checks for `schema: plan/v1` and parses Issue Outlines -- it
  would need to reject portfolio-level plans or handle them differently.
  State file schema (`source_doc_type: "plan"`) becomes ambiguous.

### Option D: Hierarchy (Roadmap Contains Plans)

Roadmap is a plan-of-plans. A Roadmap artifact contains references to
child Plan artifacts, one per feature. The Roadmap tracks progress across
Plans the way a Plan tracks progress across issues.

**Trade-offs:**

- Complexity: High structural complexity. Three levels of nesting: Roadmap ->
  Plan -> Issues. The existing two-level model (Plan -> Issues) is already
  the most complex artifact relationship in the system.
- Duplication: Low -- each level has a distinct role.
- Flexibility: High. New features on a roadmap get their own Plan, which
  independently progresses through its lifecycle. Roadmap progress is
  derived from child Plan statuses.
- Learning curve: Highest. Users must understand the full hierarchy before
  they can work at any level. The existing flow
  (roadmap -> /plan -> PLAN doc -> /implement) already has 4 steps.
- Impact on existing code: Moderate. Roadmap format would add child
  references (similar to how Plans reference issues). The /plan skill
  already handles roadmap decomposition into planning issues -- the
  hierarchy model would formalize this into explicit parent-child linking.
  New tracking fields needed: roadmap frontmatter gains `child_plans[]`,
  Plan frontmatter gains `parent_roadmap`. The /complete-milestone skill
  would need to cascade completion checks upward.

## Lead 5: What Would Break If We Unified Them?

### Hard Constraints from the Codebase

**1. `parsePlanDoc()` in workflow-tool (Go binary)**

The function at `private/tools/claude/workspace/_claude/command_assets/tools/cmd/workflow-tool/main.go`
performs line-by-line parsing of Plan frontmatter and Issue Outlines sections.
Key assumptions hardcoded in Go:

- Frontmatter must contain `schema: plan/v1` (or default to it)
- `PlanMetadata` struct expects: Schema, Status, ExecutionMode, Upstream,
  Milestone, IssueCount
- Issue Outlines are parsed via `### Issue N: <title>` heading patterns
- `isPlanDoc()` uses dual detection: frontmatter schema OR `PLAN-` filename prefix

A unified type would require either extending this parser to handle portfolio-level
content, or adding a second parser function. The filename-based detection
(`PLAN-` prefix) would conflict if roadmaps used the same prefix.

**2. /implement skill (PLAN-only consumer)**

The /implement skill (`private/tools/plugin/tsukumogami/skills/implement/SKILL.md`)
explicitly states: "PLAN doc is the only input. Don't accept design docs
directly -- route through /shirabe:plan first." It reads `schema: plan/v1`
frontmatter, checks for `execution_mode` (single-pr/multi-pr), and
auto-detects `deliverable_type` from issue content. A portfolio-level
artifact would have no implementable issues -- /implement would need to
reject it or handle it as a no-op.

**3. /plan skill (roadmap consumer, PLAN producer)**

The /plan skill (`skills/plan/SKILL.md`) treats roadmaps as *input* and
PLANs as *output*. When `input_type: roadmap`, it switches to
feature-by-feature decomposition where each roadmap feature becomes a
planning issue. Unifying the types would collapse the input/output
distinction -- the skill would be transforming a PLAN into a PLAN, which
is conceptually circular.

**4. State file schema**

The state management skill uses `source_doc_type: "plan"` to identify
what /implement is working from. If roadmaps were also plans, this field
loses its discriminating power. The `execution_mode` field (single-pr/multi-pr)
doesn't apply to portfolio-level work. The `deliverable_type` field
(code/docs/mixed) doesn't apply to planning-issue-only work.

**5. File location conventions**

Plans live at `docs/plans/PLAN-<topic>.md`. Roadmaps live at
`docs/roadmaps/ROADMAP-<name>.md`. The /plan skill's input detection
uses filename patterns to distinguish input types:
`docs/roadmaps/ROADMAP-*.md` -> roadmap, `docs/plans/PLAN-*.md` -> error
(can't plan a plan). Unifying types would require new disambiguation logic.

**6. Lifecycle asymmetries**

Roadmaps: Draft -> Active requires human approval of feature list.
Active -> Draft is forbidden. Plans: Draft -> Active is triggered by
issue creation (multi-pr) or /implement start (single-pr). These are
different enough that a shared lifecycle state machine would need
type-conditional transition rules.

### Summary of Breaking Changes by Option

| Constraint | Option B (Shared Base) | Option C (Single Type) | Option D (Hierarchy) |
|------------|----------------------|----------------------|---------------------|
| parsePlanDoc() | Factor common parsing | Major rewrite needed | Add parent linking |
| /implement | Unchanged | Must reject portfolio mode | Unchanged |
| /plan input/output | Unchanged | Circular: PLAN -> PLAN | Add child tracking |
| State file schema | Add base fields | Ambiguous source_doc_type | Add parent_roadmap |
| File locations | Keep separate | Merge to single path | Keep separate |
| Lifecycle | Extract shared base | Conditional transitions | Cascade completion |

### Recommendation

Option A (separate types) is the pragmatic choice given the current codebase.
The Go parser, /implement consumer, and /plan producer all assume Plan and
Roadmap are distinct. Option B (shared base) is the best evolution path if
the artifact type count grows -- it reduces duplication without collapsing
the type distinction that consumers rely on. Options C and D introduce
complexity disproportionate to their benefits: C fights the fundamental
structural differences between portfolio and implementation artifacts, and
D adds nesting depth that increases cognitive load without clear user value.

If the PRD wants to reduce duplication between Roadmap and Plan, the
practical path is Option B applied incrementally: extract shared lifecycle
validation into helper functions, standardize frontmatter conventions
(status field format, upstream linking), and document the shared patterns
in a reference. This avoids the breaking changes of full unification while
capturing the reuse benefits.
