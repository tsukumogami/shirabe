# Phase 3: Cross-Validation

Check assumptions across completed decisions. Single pass with bounded restart.
This phase always runs after Phase 2, even with one decision; it is never skipped.

## Resume Check

If coordination manifest has `cross_validation: "passed"`, skip to Phase 4.
If `cross_validation: "in_progress"`, resume where left off.

## Steps

### 3.1 Read All Decision Reports

For each completed decision in the coordination manifest, read the report
at the stored key (`koto context get design-<topic> work/decision_<N>_report.md`). Extract the `assumptions` list from each.

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
   - Re-spawn the decider agent with the conflict as a constraint (a
     question Phase 2 resolved inline is re-resolved inline instead):
     "Decision 3 chose event-driven invalidation. Your assumption of low
     write volume is invalidated. Re-evaluate with this constraint."
   - Remove the decision's old report key first (`koto context remove
     design-<topic> work/decision_<N>_report.md`), so the decider's resume
     check doesn't read the decision as complete
   - The decision skill runs a fresh evaluation (its intermediate keys
     under `work/decision-<N>/` were removed at its Phase 6), not a partial
     resume

3. After all restarts complete, set `cross_validation: "passed"`. Do NOT
   run a second validation round. Any remaining conflicts are recorded as
   high-priority assumptions.

### 3.4 Write Considered Options

Map each decision report into the design doc's Considered Options section
using the rendering rules from `${CLAUDE_PLUGIN_ROOT}/references/decision-report-format.md`:

- Context → opening paragraphs under `### Decision N: <Topic>`
- Provenance → the entry's first line, `Resolved inline.` or
  `Delegated to /decision.`, from the manifest's `provenance` (Phase 2.2a);
  a direct run, where every question goes to `/decision`, leaves it out
- Assumptions → bulleted "Key assumptions:" within Context
- Chosen → `#### Chosen: <Name>` with full description
- Rationale → inline in Chosen section
- Alternatives → `#### Alternatives Considered` with per-alt rejection
- Consequences → roll up into design doc's `## Consequences`

Also write the Decision Outcome section synthesizing how the individual
decisions work together.

### 3.5 Preserve Artifacts

Do NOT remove the decision report keys or the coordination manifest key at
this point. They remain in `design-<topic>` for resumability -- if the run is
interrupted after Phase 3 but before the workflow completes, the resume logic
needs the coordination manifest to detect that cross-validation passed and
the decision reports for context recovery.

Nothing is ever deleted from the staging folder: `/design` writes nothing
there. The session's keys stay until the session is closed (Phase 6 on a
direct run, the parent's exit under a parent), and stay readable after.

## Quality Checklist

- [ ] All assumptions checked against peer decisions
- [ ] Conflicts restarted once with constraints
- [ ] Considered Options written to design doc

## Next Phase

Proceed to Phase 4: Investigation (`phase-4-architecture.md`)
