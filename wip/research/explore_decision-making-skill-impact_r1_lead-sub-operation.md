# Research: Decision Skill as Reusable Sub-Operation

Lead 3 from explore scope: how does a parent skill invoke the decision skill?

## 1. Existing Sub-Operation Patterns

Four distinct invocation patterns exist in shirabe today.

### Pattern A: Shell Script Execution (synchronous, deterministic)

**Where**: plan Phase 7 (`create-issues-batch.sh`), plan Phase 4 (`render-template.sh`,
`build-dependency-graph.sh`), work-on Phase 0 (`extract-context.sh`), design
(`transition-status.sh`).

**How it works**: The orchestrating skill runs a bash script via the Bash tool. The
script receives structured input (JSON on stdin or positional arguments), performs
deterministic work (GitHub API calls, template rendering, file parsing), and returns
structured output (JSON on stdout). The skill parses the output and continues.

**Contract**: stdin/args in, stdout JSON out, exit code for success/failure. Scripts
write files to known paths (e.g., `wip/IMPLEMENTATION_CONTEXT.md`). The skill
reads those files after the script exits.

**Characteristics**: Fully synchronous. No LLM reasoning. Deterministic. Resumable
via file existence checks. Scripts use `set -euo pipefail` and return JSON summaries.

### Pattern B: Parallel Agent Spawning (async, LLM-powered)

**Where**: plan Phase 4 agent generation, explore Phase 0 triage (Stages 1 and 2).

**How it works**: The orchestrating skill spawns multiple Task tool calls in a single
message with `run_in_background: true`. Each agent gets a self-contained prompt with
all context inlined. Agents write output files and return structured summaries. The
orchestrator collects results via TaskOutput with timeouts.

**Plan Phase 4 specifics**: Agents write `wip/plan_<topic>_issue_<id>_body.md` files.
Return structured summaries (status, complexity, file path). Orchestrator validates
outputs, retries on failure, falls back to template rendering. Compiles a manifest
JSON that downstream phases consume.

**Explore Phase 0 specifics**: Triage agents are lighter -- they return 3-5 line
assessments directly to chat (no file output). The orchestrator synthesizes by
majority vote. Two sequential stages, each with 3 parallel agents.

**Characteristics**: Async via `run_in_background`. Each agent is fire-and-forget
with a prompt containing all needed context. No agent-to-agent communication.
Orchestrator handles collection, validation, retry, and synthesis.

### Pattern C: Skill Reading (inline, context-loading)

**Where**: All skills read helper skills (writing-style, public-content,
private-content) by reading their SKILL.md. Plan reads phase reference files
sequentially. Design reads phase files.

**How it works**: The orchestrating skill uses the Read tool to load a reference
file, then follows its instructions inline. No separate process or agent is spawned.
The loaded content becomes part of the current conversation's instruction set.

**Characteristics**: Synchronous. No context boundary -- the loaded instructions
execute in the calling skill's context. Good for guidance and templates. Bad for
autonomous multi-step workflows that need isolation.

### Pattern D: Slash Command Delegation (user-initiated)

**Where**: Explore Phase 0 triage suggests the user run `/work-on`. Plan output
suggests the user run `/work-on` on individual issues.

**How it works**: The current skill completes, then tells the user to invoke another
skill. No programmatic invocation -- the user types the command.

**Characteristics**: Fully decoupled. Clean context boundary. But requires user
intervention, so not suitable for automated sub-operation invocation.

## 2. How Should a Parent Invoke the Decision Skill?

Four options, evaluated against the decision skill's requirements.

### Option 1: Spawn as Agent (Task tool)

The parent builds a prompt containing the decision question, options, and evaluation
criteria. Spawns a Task agent that follows the decision skill's phases. Agent writes
output files and returns a structured summary.

**Pros**: Clean context isolation. Parallel decisions possible (design needs 3-5
concurrent decisions). Follows the established plan Phase 4 pattern. Agent can
run the full 7-phase workflow autonomously.

**Cons**: Context duplication -- all relevant design context must be serialized into
the prompt. Agent has no access to the parent's conversation history. The decision
skill's 7 phases are heavyweight for a sub-agent (research, bakeoff, peer review,
cross-examination). Token cost is high per decision. Retry and validation add
orchestration complexity in the parent.

**Fit**: Best for parallel multi-decision orchestration (design skill running 3-5
decisions simultaneously). The plan Phase 4 pattern directly applies.

### Option 2: Read SKILL.md and Follow Inline

The parent reads the decision skill's SKILL.md and executes its phases within its
own conversation context. No agent boundary.

**Pros**: Full access to parent's conversation context. No serialization overhead.
Simple to implement -- just read and follow. Resumable via the parent's existing
wip/ artifact checks.

**Cons**: Pollutes the parent's context window with decision skill instructions.
Can't run decisions in parallel. The parent becomes a monolithic workflow that's
harder to reason about. If the decision skill changes, every parent that reads it
gets the new behavior (good for updates, risky for breaking changes).

**Fit**: Best for single-decision use cases (explore crystallizing to a decision
record). Matches the helper skill reading pattern.

### Option 3: Invoke via Slash Command

The parent suggests `/decision <question>` and the user invokes it.

**Pros**: Cleanest separation. User stays in control. Each decision gets its own
conversation context.

**Cons**: Breaks workflow continuity. User must manually transfer context between
skills. Can't automate multi-decision orchestration. The design skill needs 3-5
decisions before it can proceed -- manual handoff for each is impractical.

**Fit**: Only for standalone decision-making (user directly wants a decision record).
Not viable as a sub-operation pattern.

### Option 4: Call a Script

Wrap the decision skill's logic in a shell script that takes structured input and
produces structured output.

**Cons**: The decision skill requires LLM reasoning (research, evaluation, synthesis).
Shell scripts can't do that. This pattern only works for deterministic operations.

**Fit**: Not viable. The decision skill is fundamentally an LLM-powered workflow.

### Recommendation: Hybrid (Option 1 for multi-decision, Option 2 for single)

**Multi-decision context (design skill)**: Use the Task agent pattern (Option 1).
The design skill spawns one agent per decision question, all in parallel. Each agent
runs the decision skill's phases autonomously. This matches plan Phase 4's proven
pattern. The design skill orchestrates collection, validation, and cross-decision
assumption checking.

**Single-decision context (explore crystallize)**: Use inline execution (Option 2).
The explore skill reads the decision skill's SKILL.md and follows its phases within
its own context. Simpler, no context serialization needed, and explore already has
all the relevant context loaded.

## 3. Working Directory Convention

### Current Convention

All skills use `wip/` with topic-scoped prefixes:

| Skill | Pattern | Example |
|-------|---------|---------|
| plan | `wip/plan_<topic>_<artifact>.md` | `wip/plan_artifact-workflow_analysis.md` |
| explore | `wip/explore_<topic>_<artifact>.md` | `wip/explore_skill-extensibility_scope.md` |
| design | `wip/design_<topic>_<artifact>.md` | `wip/design_skill-extensibility_summary.md` |
| work-on | `wip/IMPLEMENTATION_CONTEXT.md` | Fixed name (no topic scoping) |
| research | `wip/research/<command>_<phase>_<role>.md` | `wip/research/explore_r1_lead-sub-op.md` |

### Proposed Mapping for the Decision Skill

The decision skill wants a "working directory" parameter. Rather than introducing
actual subdirectories, map it onto the existing flat `wip/` convention with a
composite prefix that encodes the parent context.

**Standalone invocation** (user runs `/decision`):
```
wip/decision_<topic>_<artifact>.md
```
Example: `wip/decision_cache-strategy_research.md`

**Sub-operation invocation** (parent skill delegates):
```
wip/<parent>_<parent-topic>_decision_<decision-id>_<artifact>.md
```
Example: `wip/design_skill-extensibility_decision_1_research.md`

The `<decision-id>` is a sequence number (1, 2, 3) assigned by the parent when it
has multiple decisions. For single-decision cases, use `decision_1` or just
`decision`.

**Why not subdirectories?** The existing convention is flat files in `wip/`. All
resume logic uses glob patterns like `wip/plan_<topic>_*.md`. Subdirectories would
break existing resume checks and cleanup patterns. The composite prefix preserves
the flat structure while encoding hierarchy.

**The "working directory" parameter** maps to a prefix string:
- Parent passes: `prefix = "design_skill-extensibility_decision_1"`
- Decision skill uses: `wip/${prefix}_<artifact>.md`
- Parent knows the prefix, so it can glob for results: `wip/design_skill-extensibility_decision_1_*.md`

## 4. Input/Output Contract

### Input (what the parent passes)

For the Task agent pattern, the parent serializes into the prompt:

```yaml
decision_context:
  question: "Which cache invalidation strategy should we use?"
  prefix: "design_skill-extensibility_decision_1"
  options:            # Optional: pre-identified alternatives
    - name: "TTL-based"
      description: "..."
    - name: "Event-driven"
      description: "..."
  constraints:        # Evaluation criteria
    - "Must support < 100ms latency"
    - "Must work with existing Redis infrastructure"
  background: |       # Relevant context from the parent's domain
    The system currently uses...
  execution_config:
    skip_research: false    # Parent may skip if it already did research
    skip_peer_review: false # Parent may skip for low-stakes decisions
```

For the inline pattern, the parent just reads the decision SKILL.md and sets
these values as conversation context before starting the phases.

### Output (what the parent gets back)

**File output** (written to wip/):
- `wip/${prefix}_research.md` -- research findings
- `wip/${prefix}_alternatives.md` -- evaluated alternatives
- `wip/${prefix}_bakeoff.md` -- validation bakeoff results
- `wip/${prefix}_report.md` -- final decision report

**Structured summary** (returned to parent via agent response or inline):

```yaml
decision_result:
  status: "COMPLETE"           # COMPLETE | INCOMPLETE | ERROR
  chosen: "Event-driven"
  confidence: "high"           # high | medium | low
  rationale: "..."
  assumptions:                 # Critical for cross-decision validation
    - "Redis cluster available"
    - "Event bus latency < 10ms"
  rejected:
    - name: "TTL-based"
      reason: "Can't guarantee consistency under partition"
  report_file: "wip/design_skill-extensibility_decision_1_report.md"
```

The `assumptions` field is critical. When the design skill runs multiple decisions
in parallel, it needs each decision's assumptions to check for cross-decision
conflicts. If Decision 2 assumes "single database" but Decision 3 chose "sharded
storage," the design skill detects the conflict and can restart Decision 2.

### Format Adapters

The decision result maps to different output formats depending on the consumer:

| Consumer | Target Format | Adapter Logic |
|----------|--------------|---------------|
| Design doc | Considered Options section | Map chosen/rejected to options table, rationale to discussion |
| Explore crystallize | ADR format | Map to Context/Decision/Consequences structure |
| Standalone | Decision report | Use report_file directly |

The adapter lives in the parent skill, not the decision skill. The decision skill
produces one canonical format; parents transform it for their context.

## 5. Resume After Decision Completes

### Sync (Inline) Pattern

When the parent reads the decision SKILL.md and follows inline:

1. Decision phases execute sequentially within the parent's context
2. Each phase writes its wip/ artifact using the provided prefix
3. When the decision completes, the parent has the result in its context
4. Parent continues to its next phase

Resume works through the standard artifact existence check. If the parent is
interrupted mid-decision, it resumes by checking which decision artifacts exist:
```
if wip/${prefix}_report.md exists     -> decision complete, skip to parent's next step
if wip/${prefix}_bakeoff.md exists    -> resume at decision phase 6
if wip/${prefix}_alternatives.md exists -> resume at decision phase 4
...
```

This is straightforward and matches how plan phases resume today.

### Async (Agent) Pattern

When the parent spawns Task agents for parallel decisions:

1. Parent spawns N agents (one per decision), all with `run_in_background: true`
2. Each agent runs the full decision workflow and writes artifacts
3. Parent collects results via TaskOutput with timeouts
4. Parent validates each result's structured summary
5. Parent checks for cross-decision assumption conflicts
6. If conflicts found, parent re-spawns affected decisions with updated constraints
7. When all decisions are stable, parent continues

**Resume for the parent**: The parent checks which decision report files exist:
```
for each decision_id in 1..N:
  if wip/${parent_prefix}_decision_${decision_id}_report.md exists:
    mark as complete, read the report
  else:
    mark as pending, re-spawn agent
```

This matches plan Phase 4's resume pattern -- check manifest, re-spawn missing agents.

**Resume for the agent**: If an agent is interrupted, the parent re-spawns it. The
new agent checks existing artifacts for its prefix and resumes at the appropriate
decision phase. This requires the decision skill's phase files to support resume
checks (which they should, following the existing pattern).

### Timeout and Failure Handling

Follow plan Phase 4's established patterns:
- 60-second timeout per TaskOutput call
- First failure: retry with simplified prompt
- Second failure: mark as incomplete, parent reports to user
- Agent errors: capture in structured summary, parent aggregates

## Summary

The decision skill fits cleanly into shirabe's existing sub-operation patterns.
Two invocation modes cover the use cases: Task agents for parallel multi-decision
orchestration (design skill), inline execution for single decisions (explore).
The working directory maps onto the flat `wip/` convention using composite prefixes
that encode the parent-decision hierarchy. The input/output contract centers on a
structured decision context (in) and decision result with assumptions (out), where
assumptions enable cross-decision conflict detection. Resume logic follows the
artifact-existence-check pattern already proven across all shirabe skills.
