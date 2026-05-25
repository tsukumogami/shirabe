# Plan Dependencies: shirabe-scope-skill

## Summary

- **Total issues**: 13
- **Issues with no dependencies**: 5 (<<ISSUE:1>>, <<ISSUE:3>>, <<ISSUE:5>>, <<ISSUE:7>>, <<ISSUE:9>>)
- **Maximum dependency depth**: 4 (<<ISSUE:7>> → <<ISSUE:8>> → <<ISSUE:10>> → <<ISSUE:11>> → <<ISSUE:13>>)

## Dependency Graph

```
PR-1:
  <<ISSUE:1>> (no deps)
  └── <<ISSUE:2>> (blocked by 1)

PR-2:
  <<ISSUE:3>> (no deps)
  └── <<ISSUE:4>> (blocked by 3)

PR-3:
  <<ISSUE:5>> (no deps)
  └── <<ISSUE:6>> (blocked by 5)

PR-4 — pattern-doc edits cluster:
  <<ISSUE:7>> (no deps)
  └── <<ISSUE:8>> (blocked by 7)
  <<ISSUE:9>> (no deps)

PR-4 — /scope body cluster:
  <<ISSUE:10>> (blocked by 1, 7, 8, 9 — cites all four pattern-doc references)
  ├── <<ISSUE:11>> (blocked by 10, 3, 5 — phase references cite SKILL.md AND require child-side Phase-N Reject contracts to exist for git-log observability)
  ├── <<ISSUE:12>> (blocked by 10 — Decision Record templates cite SKILL.md reference table)
  └── <<ISSUE:13>> (blocked by 10, 11, 12 — eval suite asserts against all three)
```

## Issue Dependencies

| Issue | Title | Blocked By | Blocks | Complexity | PR |
|-------|-------|------------|--------|------------|----|
| <<ISSUE:1>> | docs(refs): add parent-skill-worktree-discipline reference | None | <<ISSUE:2>>, <<ISSUE:10>> | simple | PR-1 |
| <<ISSUE:2>> | docs(charter): cite worktree-discipline reference in /charter | <<ISSUE:1>> | None | simple | PR-1 |
| <<ISSUE:3>> | feat(prd): ship Phase 4 step 4.5 3-option Reject contract | None | <<ISSUE:4>>, <<ISSUE:11>> | testable | PR-2 |
| <<ISSUE:4>> | test(prd): add Phase 4 Reject contract eval scenario | <<ISSUE:3>> | None | testable | PR-2 |
| <<ISSUE:5>> | feat(design): ship Phase 6 step 6.7 3-option Reject contract | None | <<ISSUE:6>>, <<ISSUE:11>> | testable | PR-3 |
| <<ISSUE:6>> | test(design): add Phase 6 Reject contract eval scenario | <<ISSUE:5>> | None | testable | PR-3 |
| <<ISSUE:7>> | docs(refs): add Gate Vocabulary section and L13 amendment to parent-skill-pattern.md | None | <<ISSUE:8>>, <<ISSUE:10>> | testable | PR-4 |
| <<ISSUE:8>> | docs(refs): extend parent-skill-state-schema.md with boundary, plan_execution_mode, and R9 additions | <<ISSUE:7>> | <<ISSUE:10>> | testable | PR-4 |
| <<ISSUE:9>> | docs(refs): append refuse-and-redirect slot 5 paragraph to parent-skill-resume-ladder-template.md | None | <<ISSUE:10>> | simple | PR-4 |
| <<ISSUE:10>> | feat(scope): add /scope SKILL.md body | <<ISSUE:1>>, <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>> | <<ISSUE:11>>, <<ISSUE:12>>, <<ISSUE:13>> | critical | PR-4 |
| <<ISSUE:11>> | feat(scope): add /scope phase reference files (Phase 0-4) | <<ISSUE:10>>, <<ISSUE:3>>, <<ISSUE:5>> | <<ISSUE:13>> | critical | PR-4 |
| <<ISSUE:12>> | feat(scope): add Decision Record body templates for re-evaluation and rejection at both boundaries | <<ISSUE:10>> | <<ISSUE:13>> | simple | PR-4 |
| <<ISSUE:13>> | test(scope): add /scope eval suite + shirabe CLAUDE.md tactical-chain entry section | <<ISSUE:10>>, <<ISSUE:11>>, <<ISSUE:12>> | None | testable | PR-4 |

## Parallelization Opportunities

### Tier 0 — Immediate Start (5 issues, fully parallel)

All five no-dep issues land in distinct files and can execute simultaneously:

- <<ISSUE:1>> — `references/parent-skill-worktree-discipline.md` (NEW)
- <<ISSUE:3>> — `skills/prd/SKILL.md` + `skills/prd/references/phases/phase-4-validate.md`
- <<ISSUE:5>> — `skills/design/SKILL.md` + `skills/design/references/phases/phase-6-*.md`
- <<ISSUE:7>> — `references/parent-skill-pattern.md` (EDIT)
- <<ISSUE:9>> — `references/parent-skill-resume-ladder-template.md` (EDIT)

### Tier 1 — After Tier 0 (5 issues, parallel within tier)

- <<ISSUE:2>> after <<ISSUE:1>> — `skills/charter/SKILL.md` reference-table back-edit
- <<ISSUE:4>> after <<ISSUE:3>> — `skills/prd/evals/evals.json` scenario addition
- <<ISSUE:6>> after <<ISSUE:5>> — `skills/design/evals/evals.json` scenario addition
- <<ISSUE:8>> after <<ISSUE:7>> — `references/parent-skill-state-schema.md` extension
- (<<ISSUE:10>> waits for Tier 2 because it needs <<ISSUE:8>>)

### Tier 2 — /scope keystone

- <<ISSUE:10>> after <<ISSUE:1>>, <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>> — `skills/scope/SKILL.md` (NEW)

### Tier 3 — /scope auxiliary (2 issues, parallel)

- <<ISSUE:11>> after <<ISSUE:10>>, <<ISSUE:3>>, <<ISSUE:5>> — five phase reference files under `skills/scope/references/phases/`
- <<ISSUE:12>> after <<ISSUE:10>> — four Decision Record body templates under `skills/scope/references/`

### Tier 4 — /scope verification

- <<ISSUE:13>> after <<ISSUE:10>>, <<ISSUE:11>>, <<ISSUE:12>> — `skills/scope/evals/evals.json` + `CLAUDE.md` tactical-chain entry

## Critical Path

The longest dependency chain is **5 issues deep**:

<<ISSUE:7>> → <<ISSUE:8>> → <<ISSUE:10>> → <<ISSUE:11>> → <<ISSUE:13>>

Estimated wall time (per-issue session estimate):
- <<ISSUE:7>> — testable pattern-doc edit, ~30-45min
- <<ISSUE:8>> — testable pattern-doc edit, ~30-45min
- <<ISSUE:10>> — critical SKILL.md body, ~90-150min
- <<ISSUE:11>> — critical 5-phase reference set, ~90-150min
- <<ISSUE:13>> — testable eval suite + CLAUDE.md, ~45-75min

**Total critical-path estimate**: ~5-7 hours of sequential work. With parallel execution of Tiers 0/1/3, total wall-clock could compress significantly if multiple agents execute simultaneously.

## Cross-PR Dependencies

PR-4 depends on PR-2 and PR-3 because <<ISSUE:11>> (in PR-4) cites the discard-commit observability surface that <<ISSUE:3>> (PR-2) and <<ISSUE:5>> (PR-3) ship. The merge order MUST be:

1. PR-1 (independent — `/charter` back-edit + new top-level reference)
2. PR-2 and PR-3 (independent of each other and of PR-1; both ship before PR-4 merges so the SKILL.md body and Phase 2 reference in PR-4 cite consistent durable child contracts)
3. PR-4 (depends on PR-2 + PR-3 + cites <<ISSUE:1>> from PR-1)

Within PR-4, branch-internal sequencing follows Tiers 1 → 2 → 3 → 4 above.

## Validation

- [x] **No circular dependencies** — all edges flow in one direction (downstream issues never block upstream issues).
- [x] **All blockers exist in the issue list** — every `<<ISSUE:N>>` reference resolves to an issue in the manifest.
- [x] **Critical path length is reasonable** — 5 issues is on the high end but within tolerance for a 13-issue plan with one critical SKILL.md keystone.
- [x] **At least one issue has no dependencies** — 5 issues are immediate-start.
- [x] **Bottleneck identified** — <<ISSUE:10>> is the keystone; everything in PR-4 funnels through it.
- [x] **Cross-PR dependencies surfaced** — PR-4 ↔ PR-2/PR-3 dependency documented above.

## Notes for Phase 6 Review

Two validation warnings carried from Phase 4 manifest into the dependency graph:

- <<ISSUE:8>>: testable complexity but no separate `## Validation` section — verification lives inline in grep-checkable ACs.
- <<ISSUE:13>>: testable complexity but no separate `## Validation` section — verification lives inline in ~15+ grep-checkable ACs.

Phase 6 review should adjudicate whether AC-only verification is acceptable for pattern-doc-edit work or whether a `## Validation` section addition is required.

## Next Phase

Proceed to Phase 6: AI Review. Spawn a reviewer via team-lead to validate completeness, sequencing, complexity assignments, and AC quality. Verdict written to `wip/research/plan_shirabe-scope-skill_phase6_review.md`. PASS → Phase 7; NEEDS-ITERATION → loop back to Phase 3.
