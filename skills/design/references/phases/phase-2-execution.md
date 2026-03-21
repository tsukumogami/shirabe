# Phase 2: Decision Execution

Invoke the decision skill for each decision question. Independent decisions
run in parallel via Task agents.

## Resume Check

If the coordination manifest shows all decisions `complete`, skip to Phase 3.
If some are `complete` and others `pending`, re-spawn only the pending ones.

## Steps

### 2.1 Read Coordination Manifest

Read `wip/design_<topic>_coordination.json`. Identify pending decisions.

### 2.2 Determine Execution Order

- **Independent decisions** (no shared constraints): spawn in parallel
- **Coupled decisions** (one feeds into another): spawn sequentially,
  passing earlier results as additional constraints

### 2.3 Spawn Decider Agents

For each pending decision, spawn a Task agent with `run_in_background: true`:

```
Agent tool:
  run_in_background: true
  prompt: |
    You are making a decision for a design document.

    Read the decision skill at skills/decision/SKILL.md and follow
    its workflow phases.

    Decision context:
      question: "<from coordination manifest>"
      prefix: "design_<topic>_decision_<N>"
      constraints: <from design doc Decision Drivers>
      background: <from design doc Context and Problem Statement>
      complexity: "<standard|critical>"

    Run in --auto mode. Write your decision report to
    wip/design_<topic>_decision_<N>_report.md.

    Return a structured YAML result with: status, chosen, confidence,
    rationale, assumptions, rejected, report_file.
```

Launch ALL independent agents in a single message.

### 2.4 Collect Results

As each agent completes, update the coordination manifest:
- Set the decision's status to `complete`
- Record the report file path

Emit progress lines per completion:
```
[design] Phase 2: decision <N>/<total> complete -- <chosen> (<status>)
```

### 2.5 Handle Failures

If an agent fails or times out:
- First retry: re-spawn with the same prompt
- Second failure: mark as `failed` in manifest, continue with remaining
  decisions, and report the failure

## Quality Checklist

- [ ] All decisions spawned (parallel for independent, sequential for coupled)
- [ ] Coordination manifest updated with results
- [ ] Progress lines emitted per completion

## Next Phase

Proceed to Phase 3: Cross-Validation (`phase-3-cross-validation.md`)
