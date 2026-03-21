# Phase 3: Cross-Validation

Check assumptions across completed decisions. Single pass with bounded restart.

## Resume Check

If coordination manifest has `cross_validation: "passed"`, skip to Phase 4.
If `cross_validation: "in_progress"`, resume where left off.

## Steps

### 3.1 Read All Decision Reports

For each completed decision in the coordination manifest, read the report
at the stored file path. Extract the `assumptions` list from each.

### 3.2 Check for Conflicts

For each decision's assumptions, check whether any peer decision's chosen
option contradicts it.

Example conflict: Decision 1 assumes "low write volume to Redis" but
Decision 3 chose "event-driven invalidation" which generates high write
volume.

### 3.3 Handle Conflicts

**No conflicts found:** set `cross_validation: "passed"` in manifest. Proceed.

**Conflicts found:**

1. Log each conflict with progress feedback:
   ```
   [design] Phase 3: conflict -- Decision 1 assumes "low write volume"
            but Decision 3 chose event-driven (high writes)
   ```

2. For each conflicting decision, restart it ONCE with the peer's outcome
   as an additional constraint:
   - Set the decision's status to `restarted` in manifest
   - Re-spawn the decider agent with the conflict as a constraint:
     "Decision 3 chose event-driven invalidation. Your assumption of low
     write volume is invalidated. Re-evaluate with this constraint."
   - The decision skill runs a fresh evaluation (intermediate artifacts
     were cleaned after Phase 6), not a partial resume

3. After all restarts complete, set `cross_validation: "passed"`. Do NOT
   run a second validation round. Any remaining conflicts are recorded as
   high-priority assumptions.

### 3.4 Write Considered Options

Map each decision report into the design doc's Considered Options section
using the rendering rules from `${CLAUDE_PLUGIN_ROOT}/references/decision-report-format.md`:

- Context → opening paragraphs under `### Decision N: <Topic>`
- Assumptions → bulleted "Key assumptions:" within Context
- Chosen → `#### Chosen: <Name>` with full description
- Rationale → inline in Chosen section
- Alternatives → `#### Alternatives Considered` with per-alt rejection
- Consequences → roll up into design doc's `## Consequences`

Also write the Decision Outcome section synthesizing how the individual
decisions work together.

### 3.5 Cleanup Decision Artifacts

Delete intermediate files that cross-validation no longer needs:
- Individual decision report files (content now in the design doc)
- Coordination manifest (its state is captured in the design doc)

## Quality Checklist

- [ ] All assumptions checked against peer decisions
- [ ] Conflicts restarted once with constraints
- [ ] Considered Options written to design doc

## Next Phase

Proceed to Phase 4: Investigation (`phase-4-investigation.md`)
