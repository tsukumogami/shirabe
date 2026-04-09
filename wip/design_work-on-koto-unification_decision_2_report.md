<!-- decision:start id="multi-issue-orchestrator" status="assumed" -->
### Decision: Multi-Issue Orchestrator Architecture

**Context**

The work-on skill unification absorbs the /implement workflow's multi-issue execution capability. The current Go workflow-tool controller (controller.go, ~240 lines of orchestration logic) provides dependency graph resolution, next-issue selection, auto-skip of blocked issues, template variable interpolation, and Phase 2 directive generation. Koto replaces per-issue state advancement but has no dependency graph, queue management, or multi-workflow coordination. The orchestrator must live in the skill layer.

Exploration research confirmed that koto's state machine is per-workflow, not per-issue. Variables are workflow-global (set at koto init, never refreshed). The intended architecture is per-issue koto workflows plus an external orchestrator. The question is what form that orchestrator takes: pure SKILL.md instructions, a helper script, a hybrid, or a koto meta-template.

**Assumptions**

- Koto's integration runner (issue #49) will not ship before this design is implemented. If it ships sooner, Option D from the multi-issue-state exploration (external state file + koto integration) becomes viable.
- Plans will have at most ~30 issues. Larger plans would need more aggressive context summarization.
- The agent can reliably invoke helper scripts and parse their structured JSON output.
- Shell is sufficient for the script's JSON operations (jq dependency acceptable). If not, Python is the fallback.

**Chosen: Hybrid Orchestrator (Script for Graph, SKILL.md for Context)**

Split orchestration responsibilities along the deterministic/flexible boundary. A lightweight queue management script handles dependency graph computation, issue selection, auto-skip, and status tracking. The SKILL.md handles PLAN doc parsing, cross-issue context assembly, koto workflow management, and PR-level coordination.

The script (`scripts/plan-queue.sh` or similar) exposes four subcommands:
- `next-issue <manifest>`: Reads the manifest, computes the dependency graph, returns the next ready issue as JSON `{issue_number, title, agent_type, dependencies_met}`
- `mark-complete <manifest> <N>`: Marks issue N as completed, checks if newly unblocked issues exist
- `mark-skipped <manifest> <N> <reason>`: Marks issue N as skipped, auto-skips transitively blocked dependents
- `status <manifest>`: Returns aggregate state (counts by status, blocked issues, overall progress)

The SKILL.md orchestration section handles:
- PLAN doc parsing: extracting issue outlines, dependencies, and metadata into the initial manifest
- Per-issue koto init: calling `koto init <WF> --template work-on.md --var ISSUE_NUMBER=<N>` with variables from the script's response
- Cross-issue context: reading koto context keys (issue-N/summary.md) to assemble PREVIOUS_SUMMARY
- Koto execution loop: calling `koto next` for the current issue until completion
- Post-completion: calling the script's `mark-complete`, then looping back to `next-issue`
- Resume: calling `status` to check manifest state, `koto workflows` to check active work
- Consistency check: verifying that the manifest's status for the active issue matches koto's workflow state

The manifest file (`wip/implement-doc_<name>_state.json`) uses a simplified schema:
```json
{
  "plan_doc": "path/to/PLAN.md",
  "branch": "feature-branch",
  "pr_number": null,
  "issues": [
    {"number": 47, "title": "...", "status": "pending", "dependencies": [46], "agent_type": "coder"}
  ],
  "skipped_issues": [
    {"number": 48, "reason": "dependency_blocked:#47", "blocked_by": [47]}
  ]
}
```

Single-issue mode bypasses the script entirely. The SKILL.md detects single-issue vs plan mode and uses the existing koto-only loop for single issues.

**Rationale**

All four validators converged on the hybrid split as the right responsibility boundary. The dependency graph -- the core of multi-issue orchestration -- requires deterministic code, not prose instructions. An agent interpreting "find the first pending issue whose dependencies are all completed" will make mistakes at scale; a script implementing `checkDependencies()` will not. At the same time, cross-issue context assembly (deciding what PREVIOUS_SUMMARY to include, what decisions to carry forward) benefits from the agent's flexibility and access to koto's context store -- capabilities a script cannot replicate without significant complexity.

The hybrid is a direct functional decomposition of controller.go: the ~100 lines of graph and queue logic go to the script; the ~60 lines of variable building and context assembly go to SKILL.md; the ~80 lines of template extraction and interpolation are handled by koto itself. Nothing is lost; each piece goes where it fits best.

**Alternatives Considered**

- **SKILL.md-Embedded Orchestrator**: All logic in prose instructions. Rejected because dependency graph operations in natural language are unreliable for >5 issues. The agent may miss transitive blocks, fail to auto-skip, or select blocked issues. Not testable. Acceptable for single-issue mode (which the hybrid preserves).

- **Full Script Orchestrator**: Script handles everything including directive generation and context assembly. Rejected because the script scope is too broad. Context assembly requires reading koto state, assembling summaries from prior issues, and making judgment calls about what context matters -- all things the agent does well and a script does poorly. The script's rigid JSON response format cannot adapt to different information needs at different workflow states.

- **Koto Meta-Workflow**: A second koto template manages the queue as a state machine. Rejected because koto provides no help with the dependency graph (still needs a script), adds significant complexity (two coordinated templates, nested workflows, cross-workflow state), and is premature given koto's current capabilities. Koto's roadmap includes "hierarchical states in a later phase" -- this alternative should be revisited when that ships.

**Consequences**

What becomes easier:
- Graph operations are testable and deterministic (script has unit tests in CI)
- Resume is reliable (script reports queue state, koto reports workflow state)
- Single-issue mode has zero orchestrator overhead
- The script is small enough (~100-150 lines) to maintain alongside the SKILL.md
- Future migration to koto meta-template is possible by replacing the script with koto orchestrator states

What becomes harder:
- Two state sources must stay synchronized (manifest tracks issue status, koto tracks workflow state). A reconciliation check mitigates this.
- PLAN doc parsing remains in SKILL.md as prose instructions, which may fail on unusual PLAN formats. Standardized PLAN templates mitigate this.
- The script needs a language choice (shell + jq, or Python). Shell is always available but fragile; Python is more capable but is a dependency.
- Contributors must understand both the script interface and the SKILL.md orchestration to modify multi-issue behavior.
<!-- decision:end -->
