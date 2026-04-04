# Lead: Controller loop in koto

## Findings

### Koto's Core Model: State Machine Per Workflow, Not Per Issue

Koto is architected as an event-sourced state machine with one state file (JSONL log) per workflow. The unified `koto next` design (DESIGN-unified-koto-next.md) describes a single state machine that governs transitions: states, evidence requirements, gates, and integrations are all per-workflow entities. There is no built-in construct for "iterate over N items, each advancing through sub-states." Koto tracks `current_state` globally (the `to` field of the last transition event) and current evidence scoped to the current state. There are no nested workflows, per-item state buckets, or issue-level sub-machines.

**Evidence:** DESIGN-unified-koto-next.md, section "Event Taxonomy" and "State File Format." The state file is JSONL with a single current state derived from the last `transitioned` event. The template format (Layer 2: Evidence routing, template-format.md) declares `accepts` and `when` blocks per state, not per issue. Multi-workflow support is horizontal (multiple state files like `koto-workflow1.state.jsonl`, `koto-workflow2.state.jsonl`), not vertical (sub-workflows nested within a state).

### No Dependency-Graph-Driven Issue Queue in Koto

Koto has no built-in "controller next" pattern. The `koto next` command returns the next action to take in the current workflow, but all action is for a single workflow instance. It does not:
- Maintain an array of issues with per-issue status (pending, in_progress, implemented, scrutinized, pushed, completed, ci_blocked)
- Rebuild a dependency graph to find the next ready issue
- Pick the issue with all dependencies completed
- Auto-skip issues blocked by failed dependencies
- Interpolate issue-specific variables into templates

Koto's template variables are workflow-global, declared at `koto init` time via `--var KEY=VALUE` and stored in the `WorkflowInitialized` event. They are not scoped per issue or refreshed mid-workflow. The DESIGN-shirabe-work-on-template.md documents this as a "needs-design" capability: template variable substitution (`--var` support) exists in the roadmap but with the caveat that it applies to gate command strings and directive text, not to picking the next issue from a queue.

**Evidence:** DESIGN-shirabe-work-on-template.md, section "Capability Map," lists "Deterministic steps auto-execute" under "Platform gap: Default action execution," and "Template variables" as a separate needs-design item. DESIGN-koto-template-format.md states variables are "declared at the root level" (once per workflow). DESIGN-unified-koto-next.md, section "Solution Architecture," shows variables stored in `WorkflowInitialized` event, not per-issue.

### Multi-Issue Workflows: The Gap

workflow-tool's core pattern is:
1. Load issues array (each with status: pending/in_progress/implemented/scrutinized/pushed/completed/ci_blocked)
2. Rebuild dependency graph from issues[].dependencies
3. Find next ready issue: first `pending` with all deps completed, or resume an `in_progress` one
4. Select template based on source doc type
5. Interpolate variables (issue number, title, agent type, previous summary) into directive
6. Return JSON directive with action, issue number, status, and interpolated text

Koto cannot express this. The architectural mismatch:
- **State machine scope**: Koto's state machine is per-workflow (one current state across all issues). workflow-tool's scope is per-issue (each issue has a status that progresses through states). Koto would need one state file per issue, then an outer orchestrator to manage the queue and invoke `koto next` for each.
- **Dependency evaluation**: Koto has no built-in dependency graph. Gates check command exit codes and context existence, not "are my dependencies completed?" Dependency checking would live outside koto, in orchestration code.
- **Variable scoping**: Koto variables are workflow-wide (set at init, unchanged). workflow-tool interpolates issue-number, issue-title, etc. per issue. Each `koto next` call for issue #42 would need to have been initialized with `--var ISSUE_NUMBER=42`, requiring the orchestrator to manage per-issue initialization.
- **Queue selection logic**: Koto has no mechanism to query "which issues are ready?" and pick one. The orchestrator must maintain the issues array, compute the dependency graph, and decide which issue to activate.

**Evidence:** DESIGN-shirabe-work-on-template.md proposes a single koto template with a 17-state machine for the work-on workflow. It does not address multi-issue orchestration; it documents work-on as a single linear flow per issue. The design notes that koto is automation-first (deterministic steps execute by default) but does not propose stacking issues or dependency-driven selection.

### Koto's Intended Architecture for Multi-Issue Work: Orchestrator + Multiple State Files

Koto's design foresees this exact gap. In DESIGN-koto-engine.md, section on alternative libraries, the authors note:

> "Hierarchical states may be useful in a later phase (multi-issue orchestration) and the library can be adopted then if needed."

And in DESIGN-koto-engine.md under "Multiple State Files":

> "When multiple state files exist in the state directory, commands that operate on a single workflow (`next`, `transition`, `query`, `rewind`) require a `--state <path>` flag. If exactly one state file exists, it's used automatically."

The intended architecture is:
- One koto workflow per issue, with one state file per issue
- An outer orchestrator (skill, SKILL.md, or Go code) manages the queue: loads the issues array, computes the dependency graph, finds the next ready issue, creates a koto workflow for that issue if needed, and calls `koto next` with `--state koto-issue-#42.state.jsonl`
- The orchestrator handles all issue-specific variable interpolation (issue number, title, etc.)

**Evidence:** DESIGN-koto-engine.md, section "Multiple Workflows" and "State File Discovery" (#8). DESIGN-shirabe-work-on-template.md assumes a single 17-state machine per issue, not a dependency-driven queue of issues. The work-on skill would need to layer orchestration code on top of koto to manage the queue.

### Context Store for Shared State, Not Dependency Graphs

Koto provides a context store (separate from the state file) for sharing data across states and across workflow invocations. This is described in DESIGN-local-session-storage.md and DESIGN-koto-next-output-contract.md. The context store is file-based and can store arbitrary JSON. Gates can check context existence (`context-exists` gate type, checks if a key exists) or match content (`context-matches`, regex on content).

This is useful for "did this step complete?" checks (e.g., "is plan.md present?") but not for "which issues are ready?" logic. The context store is not a dependency resolver.

**Evidence:** template-format.md, Layer 3, documents `context-exists` and `context-matches` gate types. Neither can express "check if all dependencies of issue #42 are completed."

## Implications

### For work-on unification:

1. **Koto cannot be the sole answer.** Koto handles workflow state per-issue well (the 17-state machine for work-on applies to each issue independently). But it has no dependency-graph-driven queue. The work-on skill must remain, or be enhanced to invoke koto orchestration.

2. **Option A (Recommended): Orchestrator + Per-Issue Koto**
   - Implement a skill-markdown orchestrator that manages the issues array, dependency graph, and queue selection
   - For each ready issue, initialize a koto workflow: `koto init issue-#42 --template work-on-template.md --var ISSUE_NUMBER=42 --var ISSUE_TITLE="..."`
   - Call `koto next --state koto-issue-#42.state.jsonl` in a loop until the issue reaches a terminal state or blocks
   - The orchestrator handles queue logic; koto handles per-issue state advancement
   - Feasibility: HIGH. This aligns with koto's intended architecture and requires no changes to koto itself.

3. **Option B (Not Recommended): Embed Orchestration in Koto**
   - File a feature request for koto to support sub-workflows or an "iterate over items" construct
   - Wait for koto to implement hierarchical state machines or a queue management API
   - This is explicitly deferred in koto's roadmap ("later phase"). It would be a significant design effort.
   - Feasibility: MEDIUM-LOW. Requires koto changes; not on the current roadmap.

4. **Option C (Partial): Single koto Workflow with Manual Queue**
   - Create a single 17-state work-on template that handles one issue at a time
   - After an issue completes, manually call `koto rewind` and reinitialize with the next issue
   - No dependency checking; the agent or skill decides which issue to work next
   - Feasibility: HIGH, but loses the core value of workflow-tool (automatic "next ready issue" selection)

### For code reduction:
- Option A gives koto's benefit (structured state enforcement, auto-advancement on deterministic steps, atomic persistence) without koto having to solve the orchestration problem
- The skill can shrink by embedding less workflow control logic and delegating to koto; exact reduction depends on how much per-issue procedural work koto's gates auto-execute

### For design decision:
The lead architectural question is answered: **Koto's state machine is per-workflow, not per-issue-within-workflow.** This is not a bug or limitation — it's the intended design. The gap is real and explicit in koto's documentation ("hierarchical states may be useful in a later phase"). Unifying work-on with koto means accepting that koto handles single-issue state, and building an orchestrator above it to manage the queue.

## Surprises

1. **Koto defers hierarchical state machines explicitly.** The engine design cites qmuntal/stateless (which supports hierarchical states) and explicitly rejected it because "the external storage API doesn't match koto's file-based persistence pattern" and "hierarchical states may be useful in a later phase (multi-issue orchestration)." This is not accidental; it's a conscious architectural choice to start with flat machines and add nesting later if needed.

2. **Koto's template format is younger than expected.** The DESIGN-koto-template-format.md and DESIGN-unified-koto-next.md are both "Planned" status as of this writing. The template format with `accepts`/`when` blocks and event-sourced state files is the future direction, not the current implementation. This means koto as it exists today is even further from the controller loop pattern than the planned version.

3. **Variable scoping is workflow-global, not per-issue.** Variables are set once at `koto init` time. There is no "refresh variables for next issue" mechanism. Mixing issues into a single workflow would require one state file per issue or a complete redesign of how variables work.

4. **The work-on design already assumes per-issue workflows.** DESIGN-shirabe-work-on-template.md describes a 17-state machine designed for a single issue. It does not propose "one big workflow with N issue substates." This suggests the architects already settled on Option A (per-issue koto + orchestrator) without explicitly naming it.

## Open Questions

1. **What does the work-on orchestrator look like?** Should it be a skill (SKILL.md with workflow template), Go code, or a combination? The DESIGN-shirabe-work-on-template.md proposes eliminating the existing SKILL.md wrapper, but if we layer koto on top, we might need a thin orchestrator wrapper instead.

2. **How much of the queue logic should live in the orchestrator vs. the skill?** The orchestrator would manage dependency checking and issue selection; should it also handle templating/variable interpolation, or is that the skill's job?

3. **Can koto's context store be leveraged for cross-issue state?** For example, if issues share a context store, could gates like `context-exists` check "has the previous issue completed?" This would reduce orchestrator complexity. Needs prototyping.

4. **What's the performance cost of per-issue state files?** If work-on handles 50 issues in parallel, we'd have 50 JSONL state files. Is this acceptable? Any batching or compression strategies?

5. **Does workflow-tool's `ci_blocked` status map to koto gates or orchestrator logic?** If an issue is blocked by CI, should koto's polling gate handle the retry, or should the orchestrator skip the issue and come back later? This affects the templating strategy.

## Summary

Koto's state machine is per-workflow, not per-issue, and cannot natively express a dependency-graph-driven controller loop. The architectural gap is real and documented in koto's design (hierarchical states deferred to "later phase"). The intended unification path is Option A: build an orchestrator (skill or Go code) that manages the issues array and dependency graph, invoke one koto workflow per issue via `koto init` with issue-specific variables, and let koto handle the deterministic state advancement. This aligns with koto's architecture and requires no changes to koto itself, but leaves orchestration logic outside koto's domain. The biggest open question is whether the orchestrator should be a thin queue-management wrapper or a full skill-markdown workflow, and what performance and usability trade-offs that entails.

