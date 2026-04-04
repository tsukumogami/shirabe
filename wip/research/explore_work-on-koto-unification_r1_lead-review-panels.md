# Lead: Review panels as koto gates

## Findings

### Koto Gate System Capabilities

Koto v0.6.0 implements three gate types in `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-5/public/koto/src/gate.rs`:

1. **command** (`type: "command"`): Runs a shell command, passes if exit code is 0, returns `{exit_code, error}`
2. **context-exists** (`type: "context-exists"`): Checks if a key exists in the session context store, returns `{exists, error}`
3. **context-matches** (`type: "context-matches"`): Checks if context content matches a regex pattern, returns `{matches, error}`

Key design properties:
- Gates are evaluated without short-circuiting; all gates run regardless of individual results
- Each gate returns both an `outcome` (Passed/Failed/TimedOut/Error) for control flow and a structured `output` JSON object for evidence injection
- Gates are declared in template states with optional `override_default` values for recording/overriding results
- Gates cannot be extended with new types at runtime (lines 70-80 in gate.rs show fixed type handling)

### Current /implement-doc Workflow: Scrutiny and Review Panels

The `/implement-doc` skill orchestrates review panels entirely via skill markdown and the workflow-tool controller. The workflow template at `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-5/private/tools/claude/workspace/_claude/command_assets/tools/internal/controller/implement-workflow-template.md` shows:

**Scrutiny Panel (STATE: implemented, Step 5, lines 138-182):**
- Three agents spawned in parallel: completeness-scrutiny, justification-scrutiny, intent-scrutiny
- Each agent reads `/private/tools/plugin/tsukumogami/shared/agent-prompts/scrutiny-review-decisions.md`
- Each returns JSON with `blocking_count`, `advisory_count`, `summary`, `detail_file`
- Orchestrator collects all three results, evaluates if any `blocking_count > 0`
- If blocking: orchestrator reads detail files and spawns implementing agent with feedback, loops back to scrutinized state
- If all clear: transitions to scrutinized state (line 211-212)

**Code Review Panel (STATE: scrutinized, step 1, lines 219-249):**
- Three agents spawned in parallel: pragmatic-reviewer, architect-reviewer, maintainer-reviewer
- Each reads `reviewer-review-issue.md` with focus parameter (pragmatic/architect/maintainer)
- Each returns JSON with `blocking_count`, `advisory_count`, `summary`, `detail_file`
- Orchestrator evaluates blocking count
- If blocking: spawns implementing agent with feedback, loops back to scrutinized state (re-review)
- If all clear: saves reviewer results to `wip/reviewer_results_{{ISSUE}}.json` and proceeds to QA/push (line 270-300)

**QA Validation (STATE: scrutinized, step 4b, lines 284-301 if testable scenarios exist):**
- Spawns tester agent with issue number and testable scenario IDs
- Tester reads `tester-validate-issue.md`
- Returns `{all_passed, passed, failed, summary, detail_file}`
- If failed: orchestrator spawns implementing agent to fix, loops back
- If passed: proceeds to push

### How Panels Differ from Gates

**Similarities to gates:**
- Both act as validation checkpoints between state transitions
- Both use structured output JSON that the orchestrator evaluates
- Both support re-running or looping if conditions aren't met

**Key Differences:**
- **Multi-step orchestration**: Each review panel is a sequence of parallel agent spawns + conditional logic, not atomic commands
- **Context accumulation**: Panel results (detail files with full findings) inform the next phase, not just a binary pass/fail
- **Looping within states**: The panels can loop the implementing agent within the same state (implemented -> feedback -> implemented again) vs. gates that block transitions
- **Determinism**: Agent behavior depends on code context (git diff, issue mapping, design doc) not just input data; results are not reproducible overrides
- **No control-flow routing**: Gates support `when` clauses for routing based on output values (e.g., `when: {exit_code: 0}`); panels return blocking/advisory counts but have no built-in routing

### Review Panel Orchestration Location

All panel orchestration logic is in the workflow template markdown (implement-workflow-template.md, lines 98-301):
- **Not in koto**: Koto only knows about gates as declared in the template state
- **Not in state schema**: The IssueEntry schema has `reviewer_results` field but no scrutiny results field; scrutiny is transient within the "implemented" state loop
- **In skill markdown**: The orchestrator (agent reading the directive) spawns agents, collects results, decides looping/advancement

### Integration Options Analysis

**Option A: Review panels as command gates**

Wrap each panel (or the aggregate) as a command gate script:
- Gate command spawns the three agents in parallel and aggregates results
- Gate returns `exit_code 0` if all agents have `blocking_count: 0`, non-zero otherwise
- Problem: Agents need access to orchestrator context (PR number, issue details, branch, CI state). A shell script wrapping cannot reconstruct this.
- Problem: Agent spawning is not idempotent; re-running a gate would re-run all three agents, doubling effort on resume
- Problem: Gate output schema is fixed (`{exit_code, error}`); cannot carry detail_file paths or per-agent blocking counts
- Verdict: Not viable without custom gate type

**Option B: Review panels as context-exists gates**

Agents write results to context store (e.g., `scrutiny/completeness.json`), gate checks if context key exists:
- Feasible but inverts the orchestration model
- Gate only checks existence/regex, not blocking counts or validity
- Orchestrator would still need to read context after gate passes to decide if loop back or advance
- Removes the determinism advantage (agents still run, can fail; gate just confirms they ran)
- Verdict: Possible but doesn't simplify orchestration, just adds a read from context store

**Option C: Keep review panels in skill markdown, use koto only for state tracking**

Current approach; panels remain orchestrated by skill markdown directives.
- Retains full control over looping, feedback, and re-runs
- Verdict: Maintains status quo; doesn't unify

**Option D: New koto gate type for agent-based validation**

Extend koto with a new `agent` or `panel` gate type that:
- Spawns multiple agents in parallel
- Collects structured output from each
- Returns aggregated result with per-agent blocking counts and detail file references
- Supports routing based on blocking count thresholds
- Problems:
  - Requires new gate type definition in koto, which is out of scope for this investigation
  - Requires agent spawning to be coordinated by koto (or gate script), losing skill-level control
  - Agents need access to prompt context (source doc, issue details, branch) which gates don't naturally provide

### Structured Output for Routing

Work-on template uses gates for simple checks (context-exists, command status); none use structured output routing. The scrutiny/review panels use blocking_count for routing but are orchestrated in markdown, not gates.

If panels became gates, the `when` clause could become:
```yaml
scrutiny_gate:
  type: agent-panel
  agents: [completeness-scrutiny, justification-scrutiny, intent-scrutiny]
  return_on_any_blocking: true

transitions:
  - target: rework
    when:
      scrutiny_gate: {blocking_count: ">0"}
  - target: scrutinized
    when:
      scrutiny_gate: {blocking_count: "=0"}
```

But this requires a new gate type.

### Determinism and Overridability

Currently:
- Scrutiny panel is non-deterministic (agents run on code state, can produce different results on retry)
- No override mechanism exists (agents always run unless skipped via evidence)

If panels became gates:
- Gate output can be recorded and overridden via `koto overrides record`
- Could introduce overridability, but requires agents to be deterministic (they aren't)
- Overriding a scrutiny result would mean skipping scrutiny entirely, not replaying it

## Implications

1. **Koto's gate system is not designed for multi-agent validation**: Gates are atomic command/context checks, not orchestration primitives for spawning sub-agents and aggregating results.

2. **The skill markdown approach is the right level of abstraction** for review panels: it preserves the orchestrator's ability to inspect intermediate results, loop intelligently, and route based on per-agent blocking counts.

3. **Unification is not about formalization; it's about cohesion**: The scrutiny and review panels don't need to become gates. What they need is:
   - Consistent structured output format (already have: blocking_count, summary, detail_file)
   - Clear integration points in the state machine (already have: implemented and scrutinized states with looping)
   - Possibly context storage for panel results to support resumption and evidence injection (partial, needed for QA results)

4. **A hybrid approach is more viable**: Keep panels in markdown, but standardize their context input/output format and use koto gates for simpler upstream/downstream checks (e.g., "code compiled", "tests passed", "branch exists"). Panels remain as orchestrated task sequences, gates handle yes/no conditions.

## Surprises

1. **No scrutiny state in state schema**: The IssueEntry schema has `reviewer_results` but no `scrutiny_results`. Scrutiny is entirely transient within the "implemented" state loop (lines 100-212 of template). This makes scrutiny lightweight but means no evidence trail is persisted for auditing.

2. **QA validation happens twice**: Once per-issue in scrutinized state (lines 284-301) and again at PR level in completing state (lines 402-418). The per-issue QA feeds into reviewer feedback; PR-level QA validates total coverage across all issues.

3. **Review panels already support dynamic feedback loops**: The template shows agents being re-run within the same state (e.g., "return to step 1" for re-review after addressing feedback, line 268). This is more flexible than any gate type, which only support transitions between states.

## Open Questions

1. **Could scrutiny results be persisted to context for evidence injection?** Currently detail files are written to `wip/` but not captured in state. Would persisting scrutiny JSON to context (e.g., `scrutiny/<focus>.json` per agent) enable better resume-ability and audit trails?

2. **Is the blocking_count threshold configurable or always "> 0"?** The template checks `if any scrutiny agent has blocking_count > 0` but doesn't show how blocking_count is interpreted. Is a count of 2 different from 1? Should there be a severity threshold?

3. **How do agents receive branch and PR context for spawning?** Agent prompts (scrutiny-review-decisions.md, reviewer-review-issue.md) reference git operations like `git diff HEAD~1` but don't show how they know which branch to use. Is branch context passed via environment, or are agents expected to infer it from `git status`?

4. **Could gate outputs be injected into agent prompts?** For example, if a "code compiles" gate passed, could that output be available in the reviewer agent's context? This would reduce agent re-work.

## Summary

Koto's gate system is not designed for agent-driven multi-step validation; it handles atomic command/context checks. The /implement-doc scrutiny and review panels are correctly orchestrated in skill markdown as conditional sequences, not gates. Rather than formalizing panels as gates (which would require a new koto gate type), unification should focus on standardizing panel output format and using koto gates for simpler binary checks, creating a hybrid model where panels remain as orchestrated task sequences and gates handle yes/no conditions.

