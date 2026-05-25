# Plan Milestone: Shirabe Scope Skill

## Milestone

**Name**: Shirabe Scope Skill

**Description**: `Design: docs/designs/DESIGN-shirabe-scope-skill.md`

**Source Document**: `docs/designs/DESIGN-shirabe-scope-skill.md`

## Scope Assessment

**Estimated issues**: 12-16

**Assessment**: Large — at the upper end of the typical range. The design is cohesive (one parent skill, eight components, three categories) and is NOT a split candidate. The design's own Implementation Approach already partitions into 4 sequenced phases (A/B/C/D); the milestone tracks the full sequence as one unit, but the issues themselves aggregate into 4 PRs per the team-lead's decomposition rationale.

The issue count reflects splitting Components 5 (the SKILL.md body, ~600-800 lines) and 7 (Phase 2 chain-orchestration reference) into multiple atomic issues per the design's own sub-section structure — each sub-section a separate testable unit — rather than shipping each component as a single issue. The 12-16 estimate consolidates: ~4 issues for PR-1 (worktree-discipline reference + `/charter` back-edit), ~2 issues for PR-2 (`/prd` Phase-N Reject), ~2 issues for PR-3 (`/design` Phase-N Reject), ~6-8 issues for PR-4 (pattern-doc edits + `/scope` body + phase references + Decision Record templates + eval suite + CLAUDE.md edits). Phase 3 decomposition will confirm the exact count.

The design is NOT a candidate for being split into multiple designs because all 8 components share a tightly-coupled pattern-doc contract — splitting would force fragile cross-PR contract changes. The 4-PR aggregation absorbs this coupling at the PR-sequencing layer rather than the design-splitting layer.

## Title Derivation Note

The design's first `#` heading is literally `# DESIGN: shirabe-scope-skill` — i.e., the topic slug appears after the prefix rather than a human-readable phrase. Per Phase 2 step 2.1's guidance ("the title should read naturally as the answer to 'what does this milestone accomplish?' — not a kebab-case slug or a filename"), the milestone title is rendered in title-case as **Shirabe Scope Skill** rather than carrying the kebab-case slug verbatim.

This mirrors the title-derivation rule for topic-input milestones (which converts hyphens to spaces and capitalises words) applied to a degenerate document-input case where the document's first heading IS the topic slug.
