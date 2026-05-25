---
complexity: simple
complexity_rationale: New top-level reference doc with substrate-agnostic prose; no behavior change, no runtime code, no security surface — pure pattern-doc authorship under references/.
---

## Goal

Ship a new top-level pattern reference at `references/parent-skill-worktree-discipline.md` that captures worktree-staleness mechanics as parent-agnostic infrastructure both `/charter` and `/scope` cite, so future parent skills inherit the discipline without re-deriving it.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope` is the second parent skill landing in shirabe, after `/charter`. Both parents need to detect worktree staleness against the tracking branch before invoking each child, but the staleness discipline is not specific to either parent — it's a pattern-level concern. The design's Component 4 (lines 1470-1498) lifts the discipline into a new top-level reference at the pattern-reference root, sibling to the four existing `parent-skill-*.md` references. Decision 4 (lines 646-729) settles the detailed prose: four named sections (Trigger Condition, Three-Option Prompt, Recording "Proceed Anyway" Divergence, Integration with Chain-Proposal Prompt) plus a fifth Binding Notes section that names per-parent bindings without leaking parent-specific behavior into the body.

This issue is the first PR in the plan because it is a leaf node with no upstream dependencies, and its output is cited by both the `/scope` body work (issue 2) and `/charter`'s back-edit (issue 10). Landing the reference early means downstream issues can cite it by path without forward-reference risk.

The reference's body MUST be parent-agnostic prose. Per-parent specifics live in the Binding Notes section so future parents (the SE8 `/work-on` migration, any amplifier-layer parents) can add a binding-notes row without re-authoring the body.

## Acceptance Criteria

- [ ] New file exists at `references/parent-skill-worktree-discipline.md` (top-level reference root, sibling to existing `parent-skill-*.md` files).
- [ ] File body contains five named sections in this order: Trigger Condition, Three-Option Prompt, Recording "Proceed Anyway" Divergence, Integration with Chain-Proposal Prompt, Binding Notes.
- [ ] **Trigger Condition section** defines "before each Phase 2 child invocation" precisely: after the parent's Phase 1 emits its chain-proposal output and the author confirms, AND before each child invocation in `planned_chain`. The check fires once per child invocation in the chain (four times per full-run `/scope` chain; three for `/charter`), not once per parent invocation. Trigger is bounded by chain step count, not wallclock time.
- [ ] **Three-Option Prompt section** documents the prompt as "Rebase / Proceed anyway / Bail", surfaced when `git fetch && git status --branch --short` shows the upstream tracking branch has new commits. Rebase emits the `git fetch && git rebase` commands and waits for the author's manual approval before running them (never auto-rebases). Proceed anyway accepts the risk and continues; the state file records the divergence per the Recording section. Bail routes per the parent's own bail-handling rule (the body cites this as parent-specific rather than naming `/scope` R8 inline).
- [ ] **Recording "Proceed Anyway" Divergence section** documents the state-file convention: a conditional list `worktree_divergences:` with entries of shape `{phase: <child-name>, upstream_ahead_by: <count>, accepted_at: <ISO-8601>}`. The list is absent when no divergence is accepted (per I-5 conditional-field discipline) and appended to as additional divergences occur.
- [ ] **Integration with Chain-Proposal Prompt section** documents ordering: the staleness check fires AFTER chain-proposal confirmation, not before. The rationale (avoid `git fetch` latency before the author has decided to proceed) is stated explicitly so future parents follow the same convention.
- [ ] **Binding Notes section** names per-parent bindings without leaking parent-specific behavior into the body: `/scope` v1 (load-bearing — 4 children, longest chain in shirabe), `/charter` (back-edit binding; 3 children, also load-bearing), `/work-on` (future; binding deferred to amplifier-layer parent).
- [ ] Body prose is parent-agnostic: outside the Binding Notes section, no inline mention of `/scope`-specific or `/charter`-specific behavior (e.g., do not name `/scope` R8 in the Bail-handling description — say "the parent's own bail-handling rule").
- [ ] No reference to private repos, internal resources, or pre-announcement features (shirabe is a public repo).
- [ ] No reference to any `wip/...` path from the file (wip-hygiene rule).
- [ ] Markdown lints clean per repo conventions; no emojis; no AI attribution lines.
- [ ] Must deliver: the canonical file path `references/parent-skill-worktree-discipline.md` with the five-section structure above (required by <<ISSUE:2>> for `/scope`'s SKILL.md Reference Files table citation, and by <<ISSUE:10>> for `/charter`'s reference-table back-edit citation).
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None — leaf node. The pattern-doc edits in earlier components (Decision 8's edits to `parent-skill-pattern.md`, `parent-skill-state-schema.md`, `parent-skill-resume-ladder-template.md`) are tracked as separate issues but do not block this one: the worktree-discipline reference is a standalone new file at the top-level reference root.

## Downstream Dependencies

- <<ISSUE:2>> — `/scope` SKILL.md body cites `references/parent-skill-worktree-discipline.md` in its Reference Files table (per design Component 5, section 5.7) and references the Trigger Condition section from Phase 2's worktree-staleness step (per Component 7, section 7.1). The canonical file path established by this issue is what <<ISSUE:2>>'s citation will point at.
- <<ISSUE:10>> — `/charter`'s back-edit adds a reference-table citation to `parent-skill-worktree-discipline.md` and a citation in `/charter`'s Phase 2 doc. The Binding Notes section's `/charter` row, written by this issue, is the inverse pointer the back-edit completes.
