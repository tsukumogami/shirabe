# Decision 8: Compiled Agent Prompt Template for Decision Skill

## Question

What should the compiled agent prompt template for decision skill invocations
look like?

## Background

The decision framework design (Decision 4) specifies that parent skills
"pre-compile the decision skill's phases into a single prompt" when spawning
Task agents. The self-validation surfaced this as an open item: during the
design's own production, agent prompts for Clusters A and B were ad-hoc. Each
described what to decide and pointed at research files, but didn't follow a
reusable template.

Three reference patterns inform this decision:

1. **Plan Phase 4's agent-prompt.md** (~220 lines): a self-contained template
   with role statement, context injection (full design doc inlined), input
   contract (issue-specific variables via `{{PLACEHOLDER}}`), conditional
   sections (skeleton mode, execution mode, complexity), output contract (file
   path + structured summary), and validation rules. The parent compiles it by
   substituting placeholders. The agent never reads external files for its
   core workflow -- everything is in the prompt.

2. **Plan Phase 4's orchestration** (phase-4-agent-generation.md): the parent
   reads the template once, builds per-issue contexts, substitutes placeholders,
   spawns all agents in parallel with `run_in_background: true`, collects via
   TaskOutput, validates, retries on failure.

3. **The invocation model research** (sub-operation lead): recommends the Task
   agent pattern for multi-decision contexts. Defines input/output contracts
   (decision_context in, decision_result out). Notes that agents receive
   everything inline and don't load phase files from disk.

## Evaluation Criteria

- **Token cost**: how many tokens per agent invocation?
- **Agent reliability**: can agents follow the prompt without losing track?
- **Maintainability**: does changing a decision phase require updating the template?
- **Fast-path/full-path branching**: how cleanly does the template handle both?
- **Proven pattern alignment**: does it match what already works in shirabe?

## Options

### Option A: Single monolithic template

One markdown file (~250-350 lines) with all 7 phases inlined. Conditional
sections for fast-path (phases 0, 1, 2, 6) vs full-path (all phases).
Parent fills in variables and sends the whole thing.

Structure:
```
# Agent: Decision Evaluation
Role statement
## Input Contract
  {{QUESTION}}, {{OPTIONS}}, {{CONSTRAINTS}}, {{BACKGROUND}}, {{PREFIX}}, {{COMPLEXITY}}
## Context
  {{BACKGROUND}} inlined
## Phase 0: Context and Framing (all paths)
  Instructions...
## Phase 1: Research (all paths)
  Instructions...
## Phase 2: Alternative Presentation (all paths)
  Instructions...
{{#if FULL_PATH}}
## Phase 3: Validation Bakeoff (full path only)
  Instructions...
## Phase 4: Peer Revision (full path only)
  Instructions...
## Phase 5: Cross-Examination (full path only)
  Instructions...
{{/if}}
## Phase 6: Synthesis and Report (all paths)
  Instructions...
## Output Contract
  File output + structured summary format
```

**Token cost**: ~2,500-3,500 tokens for fast-path, ~4,000-5,000 for full-path.
Comparable to plan's agent prompt (~220 lines, ~2,000-3,000 tokens including
the inlined design doc placeholder). The background context injection adds
variable cost on top.

**Agent reliability**: HIGH. Plan Phase 4 proves this works at similar scale.
Agents follow a 220-line self-contained prompt reliably. The decision template
is longer but structurally simpler (sequential phases vs plan's conditional
complexity around skeleton mode, execution mode, and downstream dependents).

**Maintainability**: MODERATE concern. Changing a phase means editing the
template. But phases are compact (80-160 lines each in the phase files, which
compress to 20-40 lines of instructions in the compiled template). The template
is the single source of truth for agent behavior, which is actually simpler
than maintaining separate phase files that must stay consistent with a template.

**Fast-path/full-path**: handled via conditional inclusion. The parent checks
`complexity` ("standard" vs "critical") and includes or excludes phases 3-5.
Two variants of the same template, or one template with conditional markers.

**Pattern alignment**: direct match with plan Phase 4's agent-prompt.md. Same
structure: role, context, instructions, output contract.

### Option B: Phased template with orchestration header

A header section (~80 lines) with the input contract, orchestration
instructions, and phase index. Followed by phase sections that the agent reads
sequentially. Similar to how implement/work-on structures its multi-phase
workflow.

Structure:
```
# Agent: Decision Evaluation
## Orchestration
  Read phases sequentially. Write artifacts after each phase.
  Fast path: execute phases 0, 1, 2, 6 only.
  Full path: execute all phases 0-6.
## Input Contract
  {{QUESTION}}, {{OPTIONS}}, etc.
## Phase 0: Context and Framing
  [phase content]
## Phase 1: Research
  [phase content]
...
## Output Contract
  [summary format]
```

**Token cost**: same as Option A. The content is identical, just organized
differently. No token savings.

**Agent reliability**: EQUIVALENT to Option A. Whether you call it "sections
of one template" or "header plus phases," the agent sees the same prompt.
The distinction is about human readability, not agent behavior.

**Maintainability**: EQUIVALENT to Option A. Same file, same editing pattern.

**Fast-path/full-path**: same conditional inclusion approach.

**Pattern alignment**: this is really just Option A with different heading
conventions. The implement skill's multi-phase template pattern works because
the orchestrator (lead agent) reads phase files from disk sequentially. For
a compiled prompt, there's no disk reading -- the agent gets everything at
once. The "phased" structure is cosmetic.

### Option C: Minimal dispatch template

A short template (~40-60 lines) with just the input contract, decision
question, and a pointer to the decision SKILL.md. The agent reads SKILL.md
itself and follows the phases. The parent doesn't compile phase instructions.

Structure:
```
# Agent: Decision Evaluation
## Your Task
  Evaluate the decision question below using the decision skill workflow.
## Input
  {{QUESTION}}, {{OPTIONS}}, etc.
## Skill Reference
  Read skills/decision/SKILL.md for the full workflow.
  Read phase files as directed by SKILL.md.
## Output Contract
  [summary format]
```

**Token cost**: LOW for the prompt itself (~500-800 tokens). But the agent
then reads SKILL.md (~200-400 tokens) and each phase file (80-160 tokens
each, 7 files = 560-1,120 tokens) via Read tool calls. Total token budget
is similar or higher than Option A when you count tool call overhead.

**Agent reliability**: LOWER. The agent must navigate a multi-file workflow
autonomously: read SKILL.md, determine which phase file to read next, read
it, follow instructions, determine the next file, etc. Each file-read is a
tool call that costs a round trip. Plan Phase 4 specifically avoids this
pattern -- it compiles everything into the prompt rather than having agents
read files, because agents that must navigate file structures are less
reliable than agents that follow inline instructions.

**Maintainability**: HIGH for phase changes (edit the phase file, template
doesn't change). But this is deceptive: the template's output contract must
still match what the phase files produce. If Phase 6's output format changes,
the template's output contract section is stale. The indirection creates a
consistency risk that Option A avoids by putting everything in one place.

**Fast-path/full-path**: the SKILL.md must explain both paths, and the agent
must correctly interpret which path to follow based on the complexity input.
This works for human agents reading phase files sequentially, but for a
spawned Task agent, the additional interpretation step is a reliability risk.

**Pattern alignment**: MISALIGNED. This is Pattern C (skill reading) from the
invocation research, not Pattern B (parallel agent spawning). The research
explicitly recommends Pattern B for multi-decision contexts, where agents get
self-contained prompts. Plan Phase 4 chose compiled prompts over file-reading
for exactly this reason.

## Analysis

Options A and B are functionally identical. The "phased template with
orchestration header" framing doesn't change what the agent sees or how it
behaves -- it's a human-readability distinction within the same file. There's
no technical difference to evaluate.

Option C trades template maintenance cost for agent reliability cost. That's
the wrong tradeoff for a sub-agent pattern where reliability is the binding
constraint. A Task agent that fails costs a retry (more tokens, more latency).
A template that needs editing when a phase changes costs a developer 5 minutes.
The retry cost dominates.

The real question is: does Option A's maintenance burden matter in practice?

The decision skill has 7 phases. The compiled template condenses each phase's
instructions to their essential steps (skip the rationale, skip the resume
checks that don't apply to sub-agents, skip the "next phase" pointers). A
phase that's 120 lines as a standalone file becomes 25-40 lines of compiled
instructions. When a phase changes, the developer updates both the phase file
(for inline/standalone execution) and the template (for agent execution).
That's two files, but the template section is short and the change is
mechanical.

Plan Phase 4's agent-prompt.md has been stable despite changes to the plan
skill's phases. The template captures the agent's behavioral contract, not
the full phase specification. Minor phase tweaks (wording, ordering within a
phase) don't propagate to the template. Only structural changes (new required
output, new input parameter, new phase added) require template updates.

## Decision

<!-- decision:start id="prompt-template-format" status="confirmed" -->
### Decision: Compiled agent prompt template format

**Question:** What should the compiled agent prompt template for decision
skill invocations look like?

**Evidence:** Plan Phase 4's agent-prompt.md (220 lines) proves that
self-contained compiled templates work reliably for Task agents. The template
follows a fixed structure: role, context, instructions, output contract. Agents
don't read external files. The invocation model research recommends this
pattern for multi-decision contexts. Options A and B are functionally identical
(same content, different heading style). Option C introduces file-navigation
reliability risk that plan Phase 4 specifically avoided.

**Choice:** Option A -- single monolithic template with conditional fast-path
sections.

Concrete template structure:

```
# Agent: Decision Evaluation

You are evaluating a decision question as part of a parent workflow.

## Your Task

Evaluate the question below through structured phases and produce a decision
report. Write all artifacts to wip/ files. Return only a structured summary.

## Decision Context

### Question
{{QUESTION}}

### Pre-Identified Options (if any)
{{OPTIONS}}

### Constraints
{{CONSTRAINTS}}

### Background
{{BACKGROUND}}

### Configuration
- Prefix: {{PREFIX}}
- Path: {{PATH}} (standard = phases 0,1,2,6 | critical = all phases 0-6)

## Phase Instructions

### Phase 0: Context and Framing
[Condensed: frame the question, identify stakeholders, define evaluation
criteria from constraints. Write wip/{{PREFIX}}_framing.md]

### Phase 1: Research
[Condensed: investigate codebase and prior art relevant to the question.
Write wip/{{PREFIX}}_research.md]

### Phase 2: Alternative Presentation
[Condensed: enumerate options (using pre-identified + discovered), evaluate
each against criteria. Write wip/{{PREFIX}}_alternatives.md]

### Phase 3: Validation Bakeoff (critical path only)
[Condensed: prototype or simulate top 2 alternatives, compare concrete
results. Write wip/{{PREFIX}}_bakeoff.md]

### Phase 4: Peer Revision (critical path only)
[Condensed: argue for the non-leading option, find weaknesses in the
leading option. Write wip/{{PREFIX}}_revision.md]

### Phase 5: Cross-Examination (critical path only)
[Condensed: adversarial challenge of the recommendation, stress-test
assumptions. Write wip/{{PREFIX}}_cross-exam.md]

### Phase 6: Synthesis and Report
[Condensed: synthesize findings into decision block format. Write
wip/{{PREFIX}}_report.md with full decision block.]

## Output Contract

Write the decision report to: wip/{{PREFIX}}_report.md

Return ONLY this structured summary:
  Status: COMPLETE | INCOMPLETE | ERROR
  Chosen: <option name>
  Confidence: <high|medium|low>
  Assumptions: <comma-separated list>
  Report: wip/{{PREFIX}}_report.md
```

The parent (design skill's Phase 2) reads this template once, substitutes
variables per decision question, and spawns agents in parallel. Each agent
gets a ~3,000-4,000 token self-contained prompt (before background injection)
and never reads phase files from disk.

**Alternatives considered:**
- Phased template with orchestration header (Option B): functionally identical
  to Option A; the heading structure difference is cosmetic, not behavioral
- Minimal dispatch template (Option C): lower prompt tokens but higher total
  cost (tool call overhead), lower reliability (agents must navigate files),
  misaligned with the proven plan Phase 4 pattern

**Assumptions:**
- Decision skill phases will compress to 25-40 lines each in compiled form
  (based on plan's compression ratio: 400-line phase file to ~30 lines in
  agent prompt)
- Background context injection will add 500-2,000 tokens depending on the
  decision (design doc excerpts, prior decision results for coupled decisions)
- Fast-path/full-path branching via conditional section inclusion is reliable
  (the parent simply omits phases 3-5 for standard complexity)

**Consequences:** Template and phase files are dual-maintained. Phase file
changes that affect agent behavior require a template update. This is
acceptable: plan's agent-prompt.md has been stable and the update cost is
low for the reliability gain.
<!-- decision:end -->

## Implementation Notes

1. The template file lives at `skills/decision/references/templates/agent-prompt.md`,
   matching plan's template location pattern.

2. The parent substitutes these variables:
   - `{{QUESTION}}` -- the decision question text
   - `{{OPTIONS}}` -- YAML list of pre-identified options (or "None")
   - `{{CONSTRAINTS}}` -- YAML list of evaluation constraints
   - `{{BACKGROUND}}` -- relevant context from the parent's domain (design doc
     excerpts, prior decision outputs for coupled decisions, codebase findings)
   - `{{PREFIX}}` -- wip/ file prefix (e.g., `design_foo_decision_1`)
   - `{{PATH}}` -- "standard" or "critical" (controls which phases execute)

3. For standard-path compilation, the parent strips phases 3-5 from the
   template before substitution. This is simpler than having the agent
   interpret a conditional -- the agent sees only the phases it should execute.

4. The output contract follows plan Phase 4's pattern: write full output to
   a file, return only a structured summary. This conserves the parent's
   context window when collecting results from 3-5 parallel agents.

5. The design skill's Phase 2 orchestration mirrors plan Phase 4 exactly:
   read template, build per-decision contexts, substitute, spawn in parallel,
   collect via TaskOutput, validate structured summaries, retry on failure.
