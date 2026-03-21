# Lead 4: Multi-Decision Orchestration and Assumption Invalidation

## Research Questions

1. How are decision questions identified from a design problem?
2. How do parallel decisions run and what coordinates them?
3. How does cross-validation work after all decisions complete?
4. What happens when an assumption is invalidated?
5. How does resumability work mid-cross-validation?

## Current State Analysis

### How the design skill handles decisions today

The design skill treats the entire design as a single decision. Phase 1 fans out
advocate agents (one per approach, max 5) that investigate in parallel. Phase 2
presents them side-by-side and the user selects one. Phases 3-4 deepen the chosen
approach. Phase 4.4 ("Implicit Decision Review") catches additional decisions that
emerged during architecture writing -- these are lightweight (no advocate agents),
just structured format appended to Considered Options.

The considered-options-structure reference file already supports multiple decisions
per design doc (Decision 1, Decision 2, etc.), and Phase 2 step 2.4 says "group
related decisions if the design involves multiple independent choices." But the
current workflow only produces multiple decisions through Phase 3's organic
discovery and Phase 4.4's implicit decision audit -- not through deliberate
up-front identification.

### How parallelism works in the plan skill

Plan's Phase 4 (agent-based issue generation) is the closest parallel-agent
orchestration pattern. It spawns N agents simultaneously via the Task tool with
`run_in_background: true`, collects results via TaskOutput with timeout handling,
validates outputs, retries failures, and compiles a manifest. Key patterns:

- All agents launched in a single message (N parallel Task calls)
- Each agent writes output to a file, returns only a summary
- A manifest tracks status per agent (PASS/VALIDATION_FAILED/ERROR)
- Retry logic: first retry with simplified prompt, second failure falls back to template
- Timeout handling: 60-second cap per agent, fallback to synchronous call

## Findings

### Q1: Decision question identification

Currently, Phase 1 reads Context and Problem Statement plus Decision Drivers,
then brainstorms candidate *approaches* -- treating the design as one big
question. With a multi-decision model, Phase 0 or early Phase 1 needs a new step:
**decision question extraction**.

This step would:
1. Read the problem statement and decision drivers
2. Identify independent decision axes (questions where options for one don't
   constrain options for another -- the split criterion from
   considered-options-structure.md)
3. Present the decision questions to the user for confirmation before spawning
   any advocates

The "When to Split Into Multiple Decisions" guidance in
considered-options-structure.md already defines the split criterion: "options for
one question don't affect options for another." This is the right test, but
applying it requires judgment. The design skill orchestrator (not sub-agents)
should perform this identification, since it requires understanding the full
problem scope.

One risk: premature splitting. If decisions are coupled (options for Decision 1
constrain what's viable for Decision 2), splitting them creates false independence.
The cross-validation phase exists to catch this, but it's expensive -- a restart
from Phase 2 of a decision skill instance. Better to err toward fewer, broader
decisions and let the implicit decision review in Phase 4.4 catch sub-decisions
that emerge during architecture work.

### Q2: Parallel decision execution

Each identified decision question would spawn its own decision skill instance.
The natural coordinator is the design skill orchestrator -- Phase 1 becomes
the fan-out point.

The plan skill's Phase 4 pattern maps directly:

- **Fan-out**: Design Phase 1 launches N decision skill instances in parallel
  (one per decision question), each via the Task tool with `run_in_background: true`
- **Input contract**: Each instance receives the problem context, decision drivers,
  and its specific decision question
- **Output contract**: Each instance writes its result (chosen option, alternatives,
  rationale, assumptions) to a wip/ file and returns a summary
- **Collection**: Design orchestrator collects all results, validates completeness

The file naming convention would extend the existing pattern:
`wip/research/design_<topic>_decision-<N>_phase<P>_<artifact>.md`

The scoping prefix `decision-<N>` keeps each decision's artifacts separate while
the `design_<topic>` prefix keeps them within the design's namespace.

A coordination manifest (similar to plan's `manifest.json`) would track each
decision's status:

```json
{
  "decisions": [
    {"id": 1, "question": "...", "status": "complete", "file": "..."},
    {"id": 2, "question": "...", "status": "restarted", "restart_from": "phase-2", "file": "..."}
  ],
  "cross_validation": "pending"
}
```

### Q3: Cross-validation after decisions complete

After all decision instances complete, the design orchestrator needs a
**cross-validation step** -- a new phase or sub-phase that doesn't exist today.

This step would:
1. Read all decision outputs (chosen options + their stated assumptions)
2. For each decision, check if its assumptions hold given peer decisions' outcomes
3. Flag conflicts (Decision 1 assumed X, but Decision 2 chose Y which contradicts X)
4. Present conflicts to the user with recommended resolution

**Who runs this?** The design skill orchestrator, not a new independent phase file.
Reasons:

- Cross-validation requires reading all decision outputs together -- no single
  decision skill instance has that view
- It's a coordination concern, not a decision-making concern
- The orchestrator already owns the decision manifest and resume state

Implementation options:
- **Option A: New Phase 1.5** between current Phase 1 (expand) and Phase 2 (converge).
  This is where decisions fan out and reconverge. Current Phase 2's "present and
  select" role would be absorbed into each decision skill instance.
- **Option B: Sub-step within Phase 2.** After collecting decision outputs,
  Phase 2 runs cross-validation before writing Considered Options. This keeps the
  phase count stable but makes Phase 2 more complex.
- **Option C: Dedicated cross-validation phase file.** A `phase-1b-cross-validation.md`
  that runs after all decision instances complete. The design orchestrator reads
  this file and executes it.

Option C is most consistent with the existing pattern of phase files as focused,
single-concern documents. It avoids overloading Phase 2, and the file naming
(1b) signals it's part of the expansion stage without renumbering later phases.

### Q4: Assumption invalidation and restart

When cross-validation finds a conflict, the spec says restart from an earlier phase
of the conflicting decision. This creates a loop:

```
Decision instances complete
  -> Cross-validation
    -> Conflict found in Decision 2
      -> Decision 2 restarts from Phase 2 (new constraints from Decision 1)
        -> Decision 2 completes with new choice
          -> Cross-validation again (all decisions)
            -> No conflicts -> proceed
```

Key design questions:

**What constitutes an assumption?** Each decision skill instance should explicitly
state its assumptions as part of its output -- "this choice assumes [X] about
the system." Without explicit assumptions, cross-validation devolves into the
orchestrator guessing what each decision depends on.

**Restart granularity:** The spec mentions Phase 2 or Phase 4 of the decision skill.
Phase 2 restart means the decision's approach selection is re-evaluated with new
constraints. Phase 4 restart means the chosen approach stands but architecture
details need adjustment. The cross-validation step determines which:
- Assumption invalidates the choice itself -> restart from Phase 2
- Assumption only affects implementation details -> restart from Phase 4

**Loop termination:** Without a bound, cross-validation could loop indefinitely
(Decision 1 invalidates Decision 2, whose restart invalidates Decision 1, etc.).
A practical bound: max 2 cross-validation rounds. After 2 rounds, escalate to
the user with the remaining conflicts for manual resolution.

**Interaction with design skill phases:** The design skill's own phase tracking
sees decision instances as sub-operations within Phase 1 (or 1-2). The design
skill's resume check looks for artifacts like `wip/research/design_<topic>_phase1_advocate-*.md`.
With the multi-decision model, the resume check needs to look at the coordination
manifest instead -- a single decision restarting doesn't reset the entire design
skill to Phase 1.

### Q5: Resumability during cross-validation

If the session is interrupted mid-cross-validation, the following state must be
persisted:

1. **Coordination manifest** (`wip/design_<topic>_decisions.json`): tracks each
   decision's status (complete/restarted/pending), which cross-validation round
   we're on, and which decisions have been flagged for restart
2. **Decision outputs**: each decision's wip/ files (already persisted by the
   decision skill instances)
3. **Cross-validation findings**: conflicts identified so far, written to
   `wip/research/design_<topic>_cross-validation-r<N>.md`

Resume logic would be:
- If coordination manifest exists with `cross_validation: "in_progress"`:
  read the manifest and cross-validation findings, resume where we left off
- If coordination manifest exists with all decisions "complete" and
  `cross_validation: "passed"`: skip to Phase 2 (write Considered Options)
- If coordination manifest exists with some decisions "restarted":
  re-launch only the restarting decisions, then re-run cross-validation

The manifest is the single source of truth for multi-decision orchestration state.
It must be committed after each state change (decision completes, conflict found,
restart initiated) so that session interruption at any point is recoverable.

## Implications for the Decision Skill

The decision skill itself needs a clean input/output contract:

**Input:**
- Decision question (what needs to be decided)
- Problem context (shared across all decisions)
- Decision drivers (may be filtered per-decision)
- Constraints from peer decisions (for restarts)

**Output (written to wip/ file):**
- Chosen option with rationale
- Alternatives with rejection rationale
- Explicit assumptions ("this choice assumes...")
- Implementation implications

**The decision skill does NOT need to know about multi-decision orchestration.**
It runs in isolation, producing one decision. The design skill orchestrator handles
coordination, cross-validation, and restart logic. This separation keeps the
decision skill reusable outside the design context (explore crystallize, standalone
ADRs, etc.).

## Summary

Multi-decision orchestration adds three new concerns to the design skill: (1) a
decision question extraction step in Phase 0/1 that identifies independent
decision axes from the problem statement, (2) a coordination manifest that tracks
parallel decision skill instances and their state, and (3) a cross-validation
sub-phase (Phase 1b) that checks assumptions across completed decisions and
triggers selective restarts. The cross-validation loop needs a termination bound
(max 2 rounds) to prevent infinite oscillation between coupled decisions. The
decision skill itself stays isolated -- it takes a question, produces a structured
output with explicit assumptions, and knows nothing about peer decisions.
Resumability hinges on the coordination manifest being committed after each state
transition.
