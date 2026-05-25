# Plan Dependencies: shirabe-charter-skill

## Summary

- Total issues: 10
- Issues with no dependencies: 2 (Issue 1, Issue 10)
- Maximum dependency depth: 6 (Issue 9, via 1 → 2 → 3 → 4 → 7 → 8 → 9)

## Dependency Graph

```
Issue 1 (no deps; foundational references)
├── Issue 2 (blocked by 1)
│   ├── Issue 3 (blocked by 2)
│   │   └── Issue 4 (blocked by 3)
│   │       └── Issue 7 (blocked by 4, 5)
│   │           └── Issue 8 (blocked by 7)
│   │               └── Issue 9 (blocked by 2, 3, 4, 5, 6, 7, 8)
│   └── Issue 5 (blocked by 1, 2)
│       ├── Issue 6 (blocked by 5)
│       │   └── Issue 9 (via 6 — same node as above)
│       └── Issue 7 (via 5 — same node as above)
Issue 10 (no deps; independent leaf)
```

Note: Issue 7 has two incoming edges (from 4 and from 5); Issue 9 has seven incoming edges (from 2, 3, 4, 5, 6, 7, 8). Issue 10 is a parallel root with no edges in either direction.

## Issue Dependencies

| Issue | Title | Blocked By | Blocks |
|-------|-------|------------|--------|
| 1 | docs(references): add four parent-skill pattern-level references | None | 2, 5 |
| 2 | feat(charter): add SKILL.md with input modes, slug constraint, and Phase 0 wiring | 1 | 3, 5, 9 |
| 3 | feat(charter): add Phase 1 discovery, visibility detection, and manual-fallback rule | 2 | 4, 9 |
| 4 | feat(charter): add child invocation logic and chain-proposal confirmation prompt | 3 | 7, 9 |
| 5 | feat(charter): add state file schema and hard finalization check | 1, 2 | 6, 7, 9 |
| 6 | feat(charter): add resume ladder with drift detection and stale-session handling | 5 | 9 |
| 7 | feat(charter): add three exit paths and tie-break orchestration | 4, 5 | 8, 9 |
| 8 | feat(charter): add exit artifact authoring (Decision Records + abandonment-forced marker + STRATEGY validation pass-through) | 7 | 9 |
| 9 | test(charter): add evals covering user stories and shared baseline | 2, 3, 4, 5, 6, 7, 8 | None |
| 10 | docs(charter): surface /charter in shirabe and workspace CLAUDE.md | None | None |

## Parallelization Opportunities

- **Immediate start (Wave 0)**: Issues 1 and 10 (both have no blockers). Issue 10 is fully independent and can land at any point in the timeline without coordination.
- **After Issue 1 (Wave 1)**: Issue 2 unblocks.
- **After Issue 2 (Wave 2)**: Issues 3 and 5 can be worked in parallel (both depend only on completed prerequisites).
- **After Issue 3 (Wave 3 — partial)**: Issue 4 unblocks. Issue 5's separate sub-chain (Issue 6) is also available in parallel.
- **After Issue 5 (Wave 3 — partial)**: Issue 6 unblocks (independent of the 3→4 sub-chain).
- **After Issues 4 and 5 (Wave 4)**: Issue 7 unblocks. Issue 6 may still be in flight in parallel.
- **After Issue 7 (Wave 5)**: Issue 8 unblocks.
- **After Issues 2, 3, 4, 5, 6, 7, 8 all complete (Wave 6)**: Issue 9 (evals) unblocks. Issue 9 is the final fan-in node.

Peak parallelism occurs in Wave 3/4: Issues 4 (or its prerequisite 3 finishing) and 6 can advance simultaneously, with Issue 10 still landable at any point.

## Critical Path

Issue 1 → Issue 2 → Issue 3 → Issue 4 → Issue 7 → Issue 8 → Issue 9

Length: 7 issues (6 edges).

Rationale: This is the longest chain of blocked-by edges in the DAG. Issue 9 sits at depth 6 measured from Issue 1. The alternate paths through Issue 5 (1 → 2 → 5 → 7 → 8 → 9 at depth 5, and 1 → 2 → 5 → 6 → 9 at depth 4) are shorter, so the 3 → 4 → 7 traversal sets the floor on minimum sequential time-to-completion.

## Validation

- [x] No circular dependencies — topological sort produces a valid ordering: 1, 10, 2, 3, 5, 4, 6, 7, 8, 9.
- [x] All blockers exist in issue list — every id referenced in any `dependencies` list (1, 2, 3, 4, 5, 6, 7, 8) appears in the manifest's 1..10 range.
- [x] At least one issue has no dependencies — Issues 1 and 10 are both independent entry points. Issue 10's "None" claim in its body was verified against the manifest.
- [x] Critical path length is reasonable — 6 edges across 10 issues is consistent with a horizontal-stage decomposition where Stage 1 foundations gate Stage 2 implementation gate Stage 2 evals.

## Notes on Manifest / Issue Body Alignment

The manifest's `dependencies` lists and each issue body's `## Dependencies` / `## Downstream Dependencies` sections were cross-checked. No contradictions found:

- Issues 1 and 10 both declare "None" as dependencies in their bodies, matching empty arrays in the manifest.
- Issue 5's body explicitly lists both blockers (`<<ISSUE:1>>` and `<<ISSUE:2>>`); manifest carries `["1", "2"]`.
- Issue 7's body explicitly lists both blockers (`<<ISSUE:4>>` and `<<ISSUE:5>>`); manifest carries `["4", "5"]`.
- Issue 9's body explicitly lists the seven direct blockers (2, 3, 4, 5, 6, 7, 8) and notes Issue 1 is transitively required (not a direct blocker); manifest carries `["2", "3", "4", "5", "6", "7", "8"]` — consistent with the body's framing.
- Downstream-dependency prose in every issue body is consistent with the inverse edges derived from the manifest's `dependencies` lists.
