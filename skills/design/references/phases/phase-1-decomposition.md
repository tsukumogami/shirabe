# Phase 1: Decision Decomposition

Identify independent decision questions from the design doc's problem statement
and decision drivers. This replaces the former Phase 1 (Approach Discovery)
which treated the entire design as one big decision.

## Resume Check

If `wip/design_<topic>_coordination.json` exists, skip to Phase 2.

## Steps

### 1.1 Read the Design Doc Skeleton

Read the Context and Problem Statement and Decision Drivers sections. These
define the problem space and the constraints that shape solutions.

### 1.2 Identify Decision Questions

For each distinct technical choice the design needs to make, create a decision
question. Apply the independence criterion from considered-options-structure.md:
"options for one question don't affect options for another."

**Merge coupled questions.** If the answer to question A constrains what's
viable for question B, merge them into a broader question. Err toward fewer,
broader decisions to avoid false independence that cross-validation would
have to catch.

### 1.3 Classify Each Decision

For each question, assign a complexity tier:
- **standard** (Tier 3): 3+ options, needs research, but trade-offs aren't
  deeply contested. Decision skill fast path.
- **critical** (Tier 4): irreversible, security implications, or experts
  would genuinely disagree. Decision skill full path.

### 1.4 Apply Scaling Heuristic

Count independent decision questions (after merging coupled ones):

| Count | Interactive | --auto |
|-------|------------|--------|
| 1-5 | Proceed normally | Proceed normally |
| 6-7 | Warn, proceed with confirmation | Proceed, record high-priority assumption |
| 8-9 | Present split proposal, require confirmation | Proceed as one doc, record assumption |
| 10+ | Refuse, require splitting | Refuse, halt with error |

### 1.5 Present Decomposition

**Interactive:** present the decision questions with their complexity
classifications for user confirmation. User can merge, split, or reclassify.

**--auto:** log the decomposition and proceed.

### 1.6 Write Coordination Manifest

Create `wip/design_<topic>_coordination.json`:

```json
{
  "topic": "<topic>",
  "decisions": [
    {"id": 1, "question": "...", "status": "pending", "complexity": "standard"},
    {"id": 2, "question": "...", "status": "pending", "complexity": "critical"}
  ],
  "cross_validation": "pending",
  "round": 0
}
```

## Quality Checklist

- [ ] Decision questions identified and independence validated
- [ ] Coupled questions merged before counting
- [ ] Scaling heuristic applied

## Next Phase

Proceed to Phase 2: Decision Execution (`phase-2-execution.md`)
