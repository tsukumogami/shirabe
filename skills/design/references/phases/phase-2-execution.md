# Phase 2: Decision Execution

Invoke the decision skill for each decision question, except that under a
parent skill a standard-tier question is resolved inline (2.2a). Independent
decisions run in parallel via Task agents.

## Resume Check

If the coordination manifest shows all decisions `complete`, skip to Phase 3.
If some are `complete` and others `pending`, run only the pending ones,
each by the route 2.2a gives it.

## Steps

### 2.1 Read Coordination Manifest

Read key `work/coordination.json` (`koto context get design-<topic>
work/coordination.json`). Identify pending decisions.

### 2.2 Determine Execution Order

- **Independent decisions** (no shared constraints): spawn in parallel
- **Coupled decisions** (one feeds into another): spawn sequentially,
  passing earlier results as additional constraints

### 2.2a Route Each Question by Tier

Run directly, every question goes to `/decision` (2.3). Under a parent
skill (the `chain/dispatch` key the Resume Logic's first
row of SKILL.md reads), route each question by the `complexity` tier Phase 1
recorded in the manifest, per
`docs/decisions/DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md`:

- **standard** (`/decision`'s Tier 3): resolve it inline, here in Phase 2.
  Weigh the options yourself and write a report in the shape a decider
  returns (status, chosen, confidence, rationale, assumptions, rejected)
  to the report key 2.3 names for that question
  (`work/decision_<N>_report.md`), so Phase 3 reads it like any other,
  then update the manifest as 2.4 does for a finished agent (status
  `complete`, report key recorded).
- **critical** (`/decision`'s Tier 4): spawn a decider in 2.3, under a
  parent as in a direct run.

Record each question's provenance in the manifest beside its status:
`"provenance": "inline"` or `"provenance": "decision"`. Phase 3 carries
it into each Considered Options entry, and when any question was
resolved inline the design's frontmatter carries
`decision_provenance: inline-resolved` (Phase 6.5).

### 2.3 Spawn Decider Agents

For each pending decision routed to `/decision`, spawn a Task agent with `run_in_background: true`:

```
Agent tool:
  run_in_background: true
  prompt: |
    You are making a decision for a design document.

    Read the decision skill at skills/decision/SKILL.md and follow
    its workflow phases.

    Decision context:
      question: "<from coordination manifest>"
      session: "design-<topic>"
      key_dir: "work/decision-<N>"
      report_key: "work/decision_<N>_report.md"
      constraints: <from design doc Decision Drivers>
      background: <from design doc Context and Problem Statement>
      complexity: "<standard|critical>"

    Run in --auto mode. Keep every intermediate as a key under key_dir in
    session design-<topic>, and write your decision report as key
    work/decision_<N>_report.md there. The session is already open: do
    not open, adopt or close any session.

    Return a structured YAML result with: status, chosen, confidence,
    rationale, assumptions, rejected, report_key.
```

Launch ALL independent agents in a single message.

### 2.4 Collect Results

As each agent completes, update the coordination manifest:
- Set the decision's status to `complete`
- Record the report key (`work/decision_<N>_report.md`)

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

- [ ] Under a parent skill, each decision routed by tier (2.2a) and its provenance recorded
- [ ] All decisions routed to `/decision` spawned (parallel for independent, sequential for coupled)
- [ ] Coordination manifest updated with results
- [ ] Progress lines emitted per completion

## Next Phase

Proceed to Phase 3: Cross-Validation (`phase-3-cross-validation.md`)
