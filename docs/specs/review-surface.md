# Review Surface Templates

Templates for the three layers where assumptions surface: terminal summary,
PR body section, and progress feedback during execution.

## Terminal Summary

Printed at workflow end. Shows high-priority assumptions with actionable
next steps.

```
=== Decision Summary ===

Decisions made: 7 (4 confirmed, 3 assumed)

High-priority assumptions requiring review:

  A2: cache-approach (assumed, high)
      Choice: TTL-based cache invalidation
      Why assumed: heuristic was close (60/40 TTL vs event-driven)
      Next steps:
        - Accept: do nothing, merge as-is
        - Override: re-run with --correct A2="event-driven invalidation"
        - Re-evaluate: re-run interactively to discuss options

  A4: final-approval (assumed, high)
      Choice: design doc auto-approved
      Why assumed: auto-approval in --auto mode
      Next steps:
        - Accept: merge proceeds to review
        - Override: run /design interactively to review before accepting

Low-priority assumptions (2): see wip/<workflow>_<topic>_decisions.md

Full decision log: wip/<workflow>_<topic>_decisions.md
```

## PR Body Section

Appended to the PR body when a PR is created. Visible to all reviewers.

```markdown
## Assumptions

This PR was generated in `--auto` mode. The following assumptions were made
and should be reviewed:

| # | Decision | Assumption | If wrong |
|---|----------|-----------|----------|
| A2 | Cache invalidation: TTL-based | Heuristic was close (60/40) | Re-invoke decision skill with correction |
| A4 | Design doc auto-approved | Validation passed, not human-reviewed | Run /design interactively |

<details>
<summary>All decisions (7 total, 4 confirmed)</summary>

See `wip/<workflow>_<topic>_decisions.md` on the branch for the full log.
</details>
```

## Progress Feedback Protocol

In --auto mode, emit status lines during execution so the user can monitor.

### Phase transitions

One line per phase entry:

```
[<skill>] Phase <N>: <brief description>...
```

Examples:
```
[design] Phase 1: decomposing into decision questions...
[design] Phase 1: identified 3 decisions
[design] Phase 2: executing decision 1/3 (cache strategy, standard)...
[design] Phase 2: decision 1/3 complete -- TTL-based (confirmed)
[design] Phase 3: cross-validating 3 decisions...
[explore] Phase 2: discover round 1, 5 leads...
[plan] Phase 3: horizontal decomposition, 8 issues...
```

### Per-agent completion (multi-decision)

During parallel agent execution, emit as each completes:

```
[design] Phase 2: decision 2/3 complete -- PostgreSQL (assumed)
```

### Significant assumptions

Log immediately when made, not batched for the end:

```
[design] ASSUMED: storage backend -- PostgreSQL chosen over SQLite
         (heuristic was close, 60/40). Review in terminal summary.
```

Only log `status="assumed"` decisions with `priority="high"`. Low-priority
assumptions are silent during execution.

## Implementation Notes

- The terminal summary reads the consolidated decisions file and filters by priority
- The PR body section is generated from the same data during PR creation
- Progress lines are emitted by the orchestrator (not the sub-agents)
- Sub-agents can't emit progress lines directly; the orchestrator logs when it receives their results
