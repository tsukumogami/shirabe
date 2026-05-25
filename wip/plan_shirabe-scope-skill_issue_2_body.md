---
complexity: simple
complexity_rationale: Single-line documentation addition to a markdown reference table — no code, no behavior change, no tests beyond CI.
---

## Goal

Add a reference-table citation in `skills/charter/SKILL.md` pointing at the new top-level `references/parent-skill-worktree-discipline.md` so `/charter` consumes the shared worktree-discipline contract `/scope` introduced.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope`'s design (Phase D — "/charter back-edit") introduces `references/parent-skill-worktree-discipline.md` as a parent-agnostic top-level reference that both `/charter` and `/scope` bind to (Decision 4). Once <<ISSUE:1>> ships the new reference file, `/charter`'s SKILL.md must cite it in the Reference Files table at `skills/charter/SKILL.md:202-215`, alongside the other top-level pattern references already listed there.

This is the smallest part of PR-1: a single docs-only addition that verifies the new top-level reference is consumable by an existing parent skill. The cite-back-edit is what makes the worktree-discipline contract reachable from `/charter`'s reference surface rather than orphaned at the pattern level. The PRD/design path mirrors the existing rows for `parent-skill-pattern.md`, `parent-skill-state-schema.md`, `parent-skill-resume-ladder-template.md`, and `parent-skill-child-inspection.md`.

This issue does NOT migrate `/charter`'s existing `--parent-orchestrated` flag to the new `parent_orchestration:` sentinel — that part of Phase D is a separate concern and stays out of this issue's scope.

## Acceptance Criteria

- [ ] `skills/charter/SKILL.md` Reference Files table contains a new row citing `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`
- [ ] The new row's "When to load" cell names a phase or condition under which `/charter` consults the worktree-discipline reference (consistent in tone with adjacent rows)
- [ ] The new row is placed alongside the other `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-*.md` rows (not buried in the `skills/charter/references/phases/*.md` block)
- [ ] No other content in `skills/charter/SKILL.md` is modified beyond the table addition
- [ ] The cited file path resolves: `references/parent-skill-worktree-discipline.md` exists in the repo (delivered by <<ISSUE:1>>)
- [ ] `grep -q 'parent-skill-worktree-discipline' skills/charter/SKILL.md` returns 0
- [ ] CI green

## Dependencies

Blocked by <<ISSUE:1>>

The new `references/parent-skill-worktree-discipline.md` file must exist before this back-edit can cite it. <<ISSUE:1>> ships that file.

## Downstream Dependencies

None — this is a leaf issue inside PR-1. The completed back-edit demonstrates that the new top-level reference introduced by <<ISSUE:1>> is consumable by an existing parent skill, closing PR-1's verification loop.
