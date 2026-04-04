# Exploration Findings: work-on-koto-unification

## Core Question

How should we evolve work-on into a unified implementation workflow that handles free-form tasks, single issues, and full plan execution -- replacing both the current work-on (koto-backed) and the private /implement workflow (workflow-tool-backed) -- while migrating to koto v0.6.0's structured gate output and first-class override system?

## Round 1

### Key Insights

1. **Three-layer architecture emerged.** Koto owns per-issue state advancement (one workflow per issue). A skill-layer orchestrator owns the issue queue (dependency graph, next-issue selection, auto-skip). Review panels stay in skill markdown (multi-agent orchestration that gates can't express). (Leads 2, 3, 4, 5, 6)

2. **Gate migration is mechanical.** All 8 gates have clear v0.6.0 mappings. Context-exists gates get `gates.X.exists: true` when clauses. Command gates get `gates.X.exit_code: 0`. Override defaults use built-in sensible values. Main work: move from implicit boolean blocking to explicit structured when-clause routing. (Lead 1)

3. **Entry routing works with koto today.** The `entry` state accepts a `mode` enum. Adding `plan_backed` routes via `when` conditions. Paths converge at `analysis`. Post-analysis divergence for multi-issue requires skill-layer handling. (Lead 4)

4. **Cross-issue context via hierarchical keys.** Per-issue context under `issue-<N>/` prefixes in a central session. Script-generated snapshots keep context window bounded to ~5 KB per transition even with 50+ issues. (Lead 7)

5. **Koto explicitly deferred hierarchical states.** The engine design cites this as a "later phase" feature. Multi-issue orchestration is outside koto's scope by design. The orchestrator pattern (per-issue koto + queue manager) aligns with koto's intended architecture. (Lead 2)

6. **Koto replaces workflow-tool's state machine and directive generation.** Template variable interpolation, per-issue state transitions, and PLAN doc parsing shift to the skill layer. Dependency resolution and auto-skip are potential koto feature requests but can be handled by the orchestrator. (Lead 5)

### Tensions

1. **Orchestrator complexity vs koto simplicity.** The orchestrator absorbs logic that was in compiled Go (workflow-tool). Skill markdown may not be the best home for dependency graph resolution and queue management.

2. **State: two sources of truth.** Per-issue koto state files + orchestrator manifest of issues/dependencies. Koto's context store is opaque (no schema, no cross-key queries). The workflow-tool JSON state pattern works but duplicates state tracking.

3. **Feature requests vs workflow redesign.** Dependency resolution and auto-skip could be koto features or orchestrator responsibilities. Implementing in orchestrator ships sooner; koto features would be cleaner long-term.

### Gaps

- Lead 5 (gap categorization) agent didn't write its research file; only summary available
- Orchestrator design not investigated: how does it manage per-issue koto workflows and handle resume?
- PLAN doc parsing location undetermined: helper script vs skill layer vs koto extension

### Decisions

- **Orchestrator stays in skill layer, not koto**: all leads converge on this
- **Gate migration is a prerequisite, not a blocker**: mechanical work, can proceed independently
- **Review panels don't move to gates**: stay in skill markdown
- **Per-issue koto workflows, not monolithic**: N state files, not one embedded state file

### User Focus

Auto-mode: findings are convergent with no major contradictions. Architecture is clear. Proceeding to crystallize.

## Decision: Crystallize

## Accumulated Understanding

The unification of work-on and /implement into a single workflow skill has a clear three-layer architecture:

**Layer 1: Koto per-issue state machine.** Each issue (whether from a plan, a GitHub issue, or a free-form task) gets its own koto workflow. Koto handles the existing 17-state machine: gates enforce prerequisites (branch exists, context artifact present, CI passing), evidence routing handles transitions, and the v0.6.0 override system provides auditable gate bypasses. Gate migration from legacy to structured output is mechanical.

**Layer 2: Skill-layer orchestrator.** For plan-backed execution with multiple issues, a skill-layer orchestrator manages the queue: reads the PLAN doc, builds a dependency graph, selects the next ready issue, initializes a per-issue koto workflow, and assembles cross-issue context. For single-issue and free-form modes, the orchestrator is trivial (one issue, no dependencies). The orchestrator replaces workflow-tool's `controller next` command.

**Layer 3: Shared components.** Review panels (scrutiny, code review, QA) remain as skill-markdown-orchestrated agent sequences. Cross-issue context uses koto's hierarchical context keys with script-generated snapshots to bound context window. Entry routing uses koto's evidence routing at the `entry` state with a 3-way `mode` enum.

Key open questions are implementation-scoped: orchestrator design (skill markdown vs helper script), PLAN doc parsing location, and whether to file koto feature requests for dependency resolution or handle it entirely in the orchestrator.
