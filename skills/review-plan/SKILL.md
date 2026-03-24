---
name: review-plan
description: Adversarial plan review skill. Challenges a complete plan artifact across
  four categories before issues are created: Scope Gate (A), Design Fidelity (B), AC
  Discriminability (C), and Sequencing/Priority Integrity (D). Produces a structured
  verdict artifact consumed by /plan or returned to the user when called standalone.
  Use when called as a sub-operation by /plan Phase 6, or when the user runs
  /review-plan directly to review an existing plan.
argument-hint: '<plan-artifact-or-topic> [--adversarial]'
---

# Review Plan Skill

`/review-plan` adversarially challenges a complete plan artifact before any issues
are created. It runs four review categories against the plan's wip/ artifacts and
the upstream design doc, then writes a structured verdict to one of two files
depending on outcome.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Overview

The skill sits between `/plan` Phase 5 (Dependencies) and Phase 7 (Creation). It
asks not "does the plan cover the design?" but "would this plan catch the wrong
implementation?" Four categories map to the three failure modes identified in
issue #19:

| Category | Name | Failure mode covered |
|----------|------|---------------------|
| A | Scope Gate | Plan too large or too small for design complexity |
| B | Design Fidelity | Plan inherits a contradiction from the design doc |
| C | AC Discriminability | ACs pass for the wrong implementation |
| D | Sequencing/Priority Integrity | Must-run QA scenarios are deprioritized |

## Execution Modes

### Fast-path (default)

Called as a sub-operation by `/plan` Phase 6. One agent evaluates each category.
Optimized for latency — same coverage as adversarial mode, lower depth.

Invoked via Agent task with:
```
skill: review-plan
args:
  plan_topic: <topic>
  round: <N>
  mode: fast-path
```

Each of the four review categories (phases 1–4) runs with a single agent. The agent
applies heuristic pattern checks and taxonomy-anchored adversarial reasoning within
a single call. Phase 5 synthesizes all category findings into the verdict.

### Adversarial (standalone)

Called directly by the user with `--adversarial`. Multiple validator agents
independently challenge the plan per category; all validators complete before
cross-examination runs; disagreements are resolved before producing a per-category
verdict. Use when thoroughness matters more than speed.

Invoked as:
```bash
/review-plan <plan-artifact-or-topic> [--adversarial]
```

Without `--adversarial`, the skill runs fast-path depth. With `--adversarial`, each
category runs a multi-agent bakeoff. The output schema is identical in both modes.

## Execution Mode Detection

Phase 0 determines which mode to use:

1. If called with `mode: fast-path` in args → fast-path mode
2. If `--adversarial` flag is present in `$ARGUMENTS` → adversarial mode
3. If neither → fast-path mode (default)

In fast-path, phases 1–4 each use a single agent. In adversarial mode, each phase
spawns multiple validator agents and adds a cross-examination step before synthesis.

## Adversarial Mode: Multi-Agent Bakeoff

When running in adversarial mode, each review category (phases 1–4) runs through
a three-step sequence before producing findings.

### Step 1: Spawn Validator Agents

For each category, spawn three independent validator agents in parallel. Each agent:

- Receives the same inputs (plan artifacts, issue bodies, upstream design doc)
- Reads the same phase reference file for its category
- Applies the full check independently, without seeing other validators' findings
- Returns its findings in `critical_findings` format

Spawn all three agents for all four categories in a single message (12 agents total)
to minimize wall-clock time. Each agent runs with `run_in_background: true`.

### Step 2: Collect and Compare

After all validators complete, for each category:

1. Collect findings from all three validators
2. Identify agreements: findings where ≥2 validators independently name the same
   issue (same issue ID, same pattern or description)
3. Identify disagreements: findings named by only one validator

**Agreements are confirmed findings** — proceed directly to the verdict.

**Disagreements require cross-examination** (step 3).

### Step 3: Cross-Examination

For each disagreement within a category:

Spawn a cross-examination agent that receives:
- The disagreeing validator's finding
- The other validators' outputs (including their absence of a finding for the same item)
- The phase reference file for this category
- The prompt: "One validator flagged [finding]. The other two did not. Evaluate
  whether the finding is valid. If valid, confirm it and describe the gap. If not,
  explain why it is a false positive."

The cross-examination agent produces a resolution: confirm or dismiss.

**Confirmed disagreements** are added to the category's findings.
**Dismissed disagreements** are dropped.

After cross-examination, all confirmed findings (from agreements + resolved
disagreements) form the category's final output for Phase 5 synthesis.

### Output Schema

Both fast-path and adversarial modes produce the same `review_result` YAML schema.
The verdict file format, field names, and loop-back behavior are identical. The only
difference is evaluation depth — adversarial mode's multi-agent bakeoff catches more
findings at the cost of significantly higher latency.

## Input

From `$ARGUMENTS` (after stripping flags):

1. **Plan topic string** (e.g., `plan-review`) — resolves to `wip/plan_<topic>_analysis.md`
2. **Path to plan analysis artifact** (e.g., `wip/plan_plan-review_analysis.md`) — used directly
3. **Called as sub-operation** — `plan_topic` is passed via args

Phase 0 reads the wip/ artifacts from the resolved topic to load all plan context.

## Phase Execution Sequence

```
Phase 0: Setup
  → read wip artifacts, detect input_type, select execution mode

Phases 1–4: Review Categories
  → Phase 1: Scope Gate (Category A)            [fast-path: 1 agent; adversarial: 3 agents + cross-exam]
  → Phase 2: Design Fidelity (Category B)       [fast-path: 1 agent; adversarial: 3 agents + cross-exam]
  → Phase 3: AC Discriminability (Category C)   [fast-path: 1 agent; adversarial: 3 agents + cross-exam]
  → Phase 4: Sequencing / Priority Integrity (D)[fast-path: 1 agent; adversarial: 3 agents + cross-exam]
  Note: in adversarial mode all 12 category agents spawn in parallel

Phase 5: Verdict Synthesis
  → collect findings from all categories
  → write verdict artifact

Phase 6: Loop-back (only when verdict is loop-back)
  → delete wip/ artifacts back to loop_target
  → signal /plan to re-enter at loop_target
```

Phases 1–4 each produce findings in the `review_result` `critical_findings` format.
Phase 5 synthesizes them into a single verdict.

## Verdict Artifacts

Phase 5 writes exactly one file per review run:

| Verdict | File | Purpose |
|---------|------|---------|
| `proceed` | `wip/plan_<topic>_review.md` | Phase 7 resume trigger (unchanged from /plan existing logic) |
| `loop-back` | `wip/plan_<topic>_review_loopback.md` | Persists findings and correction hints until loop completes |

Both files use the same `review_result` YAML schema. See
`references/templates/review-result-schema.md` for the full field specification.

## Resume Logic

```
if wip/plan_<topic>_review.md exists          → skip to Phase 7 (already reviewed, proceed)
if wip/plan_<topic>_review_loopback.md exists → Phase 6 already wrote verdict; execute loop-back
else                                           → start at Phase 0
```

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-scope-gate.md` | Phase 1 |
| `references/phases/phase-2-design-fidelity.md` | Phase 2 |
| `references/phases/phase-3-ac-discriminability.md` | Phase 3 |
| `references/phases/phase-4-sequencing.md` | Phase 4 |
| `references/phases/phase-5-verdict.md` | Phase 5 |
| `references/phases/phase-6-loop-back.md` | Phase 6 (loop-back only) |
| `references/templates/review-result-schema.md` | Phases 1–5 (finding format) |
| `references/templates/ac-discriminability-taxonomy.md` | Phase 3 (adversarial pass) |
