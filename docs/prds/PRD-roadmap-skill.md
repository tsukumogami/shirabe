---
status: Done
problem: |
  The roadmap artifact type has a format-reference skill but no creation
  workflow or lifecycle management. Roadmaps are manually authored or
  produced via /explore's bare inline template. The lifecycle rules
  (when to transition, what to preserve, what gates merging) are
  undocumented and unenforced.
goals: |
  Define what a roadmap is, how it's created, and how its lifecycle works
  -- everything the /roadmap skill needs to own.
---

# PRD: Roadmap Skill

## Status

Draft

## Problem Statement

The roadmap artifact type has a format-reference skill (private plugin)
that defines structure and validation rules, but no creation workflow and
no lifecycle enforcement. Users manually author roadmaps or rely on
/explore's inline production handler, which writes a bare template without
guided scoping, research, or review.

Additionally, roadmap lifecycle rules are implicit:
- The strategic pipeline roadmap merged to main as Draft (should have been
  Active)
- There's no transition script enforcing allowed/forbidden state changes
- No rule says when a roadmap is "Done" or what happens to its content
  at that point
- No consistency invariant ties GitHub issue status back to the roadmap's
  progress tracking

## Goals

- Define the complete /roadmap skill: creation workflow, format spec,
  lifecycle management, and transition script
- Establish lifecycle gates: Active before merge, Done preserves content
- Ensure progress consistency between GitHub issues and roadmap status
- Enable /explore to hand off to /roadmap via auto-continue

## User Stories

1. As a user with a multi-feature initiative, I want a guided /roadmap
   workflow so I get the same quality of scoping, research, and review
   that /prd and /vision provide.

2. As a maintainer, I want roadmaps to be Active before merging to main
   so that Draft feature lists don't accidentally become the source of
   truth.

3. As an agent running /explore, I want /explore to hand off to /roadmap
   via auto-continue so the user doesn't have to manually invoke a
   separate command.

4. As a user tracking a multi-feature initiative, I want the roadmap's
   progress section to stay consistent with GitHub issue status so I can
   trust the roadmap as the single source of truth.

## Requirements

### Functional

**R1. /roadmap creation skill.** A dedicated /roadmap skill with a
multi-phase creation workflow (scope, discover, draft, validate) following
the /vision pattern. Works standalone (`/roadmap <topic>`) and via /explore
handoff. Produces `docs/roadmaps/ROADMAP-<topic>.md` with Draft status.

**R2. Format specification.** The skill owns the roadmap format spec
(adopted from the private plugin): frontmatter (status, theme, scope),
required sections (Status, Theme, Features, Sequencing Rationale,
Progress), lifecycle states, validation rules, quality guidance, and
content boundaries. Format reference lives in the skill's references/
directory.

**R3. Lifecycle states and transitions.** Draft -> Active -> Done.
Transition script enforces:
- Draft -> Active: feature list locked, human approval
- Active -> Done: all features terminal (delivered or explicitly dropped)
- Forbidden: Done -> any (permanent record), Active -> Draft (no
  regression)

**R4. Active before merge.** A roadmap must not be merged to main with
Draft status. The transition script or CI validates this.

**R5. Permanent record on Done.** Done roadmaps retain all content:
Implementation Issues table, Mermaid dependency graph, Progress section,
feature descriptions. Nothing is stripped or deleted. Done roadmaps are
historical artifacts.

**R6. Format supports planning enrichment.** The roadmap format reserves
positions for an Implementation Issues table and Mermaid dependency graph
(after the Progress section). These sections are empty at creation time
and populated by /plan when it consumes the roadmap. The /roadmap skill
defines the format; /plan populates it (see PRD-plan-skill-rework.md).

**R7. /explore auto-continue handoff.** /explore's Phase 5 hands off to
/roadmap via the auto-continue pattern (writes a scope artifact, invokes
/roadmap). Replaces the current inline production in
phase-5-produce-deferred.md.

**R8. At least one feature.** A roadmap must have at least one feature.
There is no two-feature floor.

Sequencing is only half of what a roadmap does. The other half is that it
is the progress ledger for a strategy's execution — its per-feature status
is the only place recording how far along the work is, and the completion
cascade updates it as downstream plans land. It is also the only bridge
from the strategic chain to the tactical one: `/brief` accepts a ROADMAP or
a PRD as upstream, never a STRATEGY. A strategy whose work is a single
feature would therefore be stranded under a two-feature rule — no legal
path into `/scope`, and no progress tracking — for no benefit, since one
feature is a perfectly coherent ledger.

Most roadmaps do sequence several features, and coordinated multi-feature
work is where the sequencing rationale earns the most; that stays quality
guidance, not a gate. A roadmap with zero features is still malformed:
nothing to sequence, nothing to track, nothing to hand downstream. That is
the only count `shirabe transition <path> Active` rejects.

### Non-Functional

**R9. No Go code changes.** The /roadmap skill is implemented in skill
markdown and shell scripts, not in the workflow-tool binary.

**R10. Transition script follows established interface.** The script
matches the design doc transition script's conventions (argument pattern,
output format, error reporting).

## Acceptance Criteria

- [ ] `skills/roadmap/SKILL.md` exists with creation workflow and format spec
- [ ] Phase files exist (scope, discover, draft, validate)
- [ ] `skills/roadmap/scripts/transition-status.sh` exists and enforces
      allowed/forbidden transitions
- [ ] Draft -> Active requires human approval
- [ ] Active -> Done requires all features terminal
- [ ] Done roadmaps retain all content (no stripping)
- [ ] Roadmap format reserves positions for Implementation Issues table and
      Mermaid dependency graph (empty at creation, populated by /plan)
- [ ] /explore Phase 5 hands off to /roadmap (auto-continue, not inline)
- [ ] Inline roadmap production removed from phase-5-produce-deferred.md
- [ ] Roadmap validation rejects a roadmap with zero features and accepts a
      one-feature roadmap through Draft -> Active
- [ ] Transition script matches design doc script's interface conventions

## Out of Scope

- /plan skill changes for roadmap enrichment (see PRD-plan-skill-rework.md)
- Progress consistency enforcement mechanism (how issue closure propagates
  to the roadmap — that's /plan and /work-on's concern)
- Go code changes to workflow-tool
- Changes to /implement, /work-on, or other plan consumers
- Retroactive changes to existing roadmap artifacts
- Shared conventions document (premature for 2 types)

## Related

- **PRD-plan-skill-rework.md** — covers /plan's changes needed to enrich
  roadmaps directly (R6's population mechanism), completion cascades, and
  progress consistency enforcement. Deferred until the /roadmap skill ships.
