# Phase 6 Review — Category D (Sequencing and Priority Integrity)

- **Reviewer**: reviewer-sequencing-integrity
- **Mode**: fast-path (single reviewer)
- **Category**: D — Sequencing / priority integrity
- **Verdict**: **PASS**
- **loop_target**: n/a (PASS)

## Summary

The dependency DAG is acyclic, the cited critical path is the longest blocked-by chain, the cited parallelization windows are honest, and the only QA-flavored issue (Issue 9 evals) is correctly positioned as the convergence leaf node after every behavior it asserts is implemented. No structural deferral. No dependency ordering error.

## Checks performed

### 1. QA scenario deprioritization (structural deferral)

Issue 9 is the only QA / integration issue. Per phase-4-sequencing.md key signal:

> A plan where the only QA or integration issue carries `simple` complexity and sits at the end of a chain where all implementation issues precede it is not a structural deferral — the QA issue runs last but validates what precedes it.

Issue 9 carries `testable` complexity (not `simple`), declares direct dependencies on every implementation issue it validates (`["2", "3", "4", "5", "6", "7", "8"]`), and validates documented behaviors authored by each blocker. This is canonical "validate-what-precedes-it" sequencing, not deferral.

Issue 9's blockers fan-in is intentional and matches `shirabe/CLAUDE.md`'s evals convention (`skills/<name>/evals/evals.json` is one canonical file per skill, and per Design Decision 4 `/charter`'s evals.json is the canonical source for the future shared baseline). Splitting Issue 9 per-user-story would scatter the canonical-source file across PRs and break the copy-and-adapt contract for `/scope` and `/work-on`. Convergence is necessary; the fan-in is not a bottleneck defect.

### 2. Dependency ordering errors (DAG correctness)

Cross-checked the dependency-analyst's Phase 5 claims against the Phase 4 manifest and per-issue `## Dependencies` / `## Downstream Dependencies` sections:

- **No cycles**: topological ordering `1, 10, 2, 3, 5, 4, 6, 7, 8, 9` is valid; every edge points forward.
- **All blockers resolve**: every id in any `dependencies` array (1, 2, 3, 4, 5, 6, 7, 8) appears in the 1..10 manifest range.
- **No phantom edges**: each manifest dependency is reflected in the cited issue body's Dependencies section and downstream-dependency prose in the blocker.
- **No missing edges**: spot-checked issue bodies for behavior references against blockers — every observed "depends on behavior from X" is captured in the manifest. Notably, Issue 9's body documents transitive dependency on Issue 1 via every prior issue's blocker — the manifest correctly carries only direct edges, not transitive ones.

### 3. Critical-path classification

Cited critical path: `1 → 2 → 3 → 4 → 7 → 8 → 9` (length 7 issues, 6 edges).

Verified by hand against all longest paths in the DAG:

| Path | Edge count |
|------|------------|
| 1 → 2 → 3 → 4 → 7 → 8 → 9 | 6 |
| 1 → 2 → 5 → 7 → 8 → 9     | 5 |
| 1 → 2 → 5 → 6 → 9          | 4 |
| 1 → 2 → 3 → 4 → 7 → 9      | 5 (skipping 8 not possible — 9 depends on 8 directly) |

The 3 → 4 → 7 traversal correctly sets the floor; no alternate path is longer. Cited length matches.

**Critical-complexity issues are 5, 6, 7.** Of these, Issue 5 IS on the critical path (transitively via the 1→2→5→7→8→9 sub-chain that converges with the critical path at Issue 7) and Issue 7 IS on the critical path directly. Issue 6 is NOT on the cited critical path — it sits on a parallel branch (1→2→5→6→9).

Issue 6's off-critical-path placement is defensible:
- Issue 6 outputs `skills/charter/references/phases/phase-resume.md` consumed by Issue 9 (evals) directly, not by Issue 7 (exit-paths) or Issue 8 (exit-artifacts).
- The 3→4→7→8 chain is longer (4 edges past Issue 2) than 5→6 (2 edges past Issue 2), so 6 is genuinely shorter-path even though its complexity is highest.
- Critical complexity does NOT imply critical path. The two dimensions measure different things: complexity is per-issue risk; critical path is graph-theoretic longest chain. The plan correctly separates them.

### 4. Parallelization windows

Verified the named waves against manifest dependencies:

- **Wave 0 = {1, 10}**: both have empty dependency arrays. Honest.
- **Wave 1 = {2}** after Issue 1: Issue 2's only blocker is Issue 1. Honest.
- **Wave 2 = {3, 5} parallel after Issue 2**: Issue 3 deps = `["2"]` and Issue 5 deps = `["1", "2"]`. Both satisfied once Issues 1 and 2 land. Honest. No hidden state coupling: Issue 3 writes `phase-1-discovery.md`; Issue 5 writes `phase-state-management.md` (or equivalent). Different file paths, no shared editable surface.
- **Issue 6 in parallel with 3→4 sub-chain**: Issue 6's only blocker is Issue 5; after Issue 5 lands, Issue 6 can advance regardless of Issue 3 or Issue 4's status. Honest.

### 5. Spot-checks raised by the coordinator

#### Issue 10 + Issue 2 transient state hazard

Issue 10's body explicitly addresses this on lines 38-39: "The trigger phrases reference `/charter` by name, not by file existence — the surfacing can land before, during, or after `/charter`'s SKILL.md exists. Authors who try the trigger phrases before `/charter` ships will see a 'skill not found' response, which is the same failure mode any pre-implementation discovery surface produces."

This is a transient documentation/code-existence gap, not a sequencing defect. For documentation-only decompositions, transient name-mention-before-target-exists is acceptable because no execution path depends on the mention. SE4 context point 4 ("Long critical path acceptable for horizontal documentation-only decomposition") reinforces this is the right shape for this plan. Not flagged.

#### Issue 9 fan-in (7 blockers)

Already addressed in check (1) above. Necessary for the canonical-source contract; splitting would violate Design Decision 4. Not flagged.

#### Issue 5 needs Issue 2

Confirmed via Issue 2's "Must deliver" downstream-dependency clause (line 74 of issue body 2): "SKILL.md's Resume Logic section references the state-file path `wip/charter_<topic>_state.md` as the per-topic state location so `<<ISSUE:5>>` and `<<ISSUE:6>>` can build the schema and ladder against it (required by `<<ISSUE:5>>`, `<<ISSUE:6>>`)."

Issue 5's body line 174 cites the same reason: "Blocked by `<<ISSUE:2>>` (`skills/charter/SKILL.md` must exist with the structural skeleton so this file is cited from either the Phase Execution section or the Resume Logic prelude)."

The Issue 5 → Issue 2 edge is real (SKILL.md citation surface for the phase-state-management.md file), not a phantom dependency. Honest.

## Findings

`critical_findings: []` — no Category D findings.

## SE4 directive context (acknowledged, not flagged)

1. PLAN doc target status `Proposed` — intentional; not a sequencing concern.
2. Milestone name "Charter Skill" — intentional per the per-parent-milestone discipline; not a sequencing concern.
3. `wip/...` path references in design and issue bodies are contract specifications (state file path `wip/charter_<topic>_state.md`, child intermediate paths `wip/strategy_<topic>_discover.md`, etc.), not orphan staging pointers; the runtime files those paths reference are produced by `/charter` at runtime, not committed pre-merge.
4. Long critical path (7 issues) is acceptable for the horizontal Stage 1 → Stage 2 → Stage 3 layering the design itself prescribes.

## Verdict

**PASS**. The plan's sequencing and priority integrity is sound. Critical-path classification correctly distinguishes complexity-of-issue from position-on-longest-chain. The DAG is acyclic, all dependencies resolve, parallelization windows are honest, and the only QA issue is correctly positioned as the convergence leaf with explicit per-blocker behavioral dependencies.
