# Phase 3: Draft

Produce a complete ROADMAP draft from scope and research findings, then refine with
the user.

## Goal

Transform the theme, feature list, and research findings into a complete ROADMAP
document, then surface open questions and trade-offs for the user to weigh in on.
By the end of this phase, the ROADMAP draft should capture the coordinated feature
plan accurately.

## Resume Check

If `docs/roadmaps/ROADMAP-<topic>.md` exists with status "Draft", offer to continue
refining from where it left off.

## Approach: Draft-Then-Review

Produce a complete first draft, then present it for thematic feedback. The user sees
the whole picture before giving feedback, and cross-references between sections
(features to dependencies to sequencing) stay consistent.

### 3.1 Gather Inputs

Read all available context:
- `wip/roadmap_<topic>_scope.md` (from Phase 1)
- `wip/research/roadmap_<topic>_phase2_*.md` files (from Phase 2)
- Any notes from Phase 2 synthesis
- `skills/roadmap/references/roadmap-format.md` (format specification)

### 3.2 Draft the ROADMAP

Write a complete ROADMAP draft following `references/roadmap-format.md`. Use the Write
tool to create `docs/roadmaps/ROADMAP-<topic>.md`.

**Drafting guidance:**

- **Status**: Set to "Draft". Active requires human approval via lifecycle transition.
- **Theme**: Synthesize from Phase 1's theme statement and Phase 2's findings. Should
  explain what initiative ties the features together and why coordinated sequencing
  matters.
- **Scope**: Draw from Phase 1's scope boundaries. What this roadmap covers and
  doesn't cover.
- **Features**: Populate from Phase 2 agent outputs. Each feature needs:
  - A clear, independently describable title
  - A rationale explaining why it's part of this roadmap
  - A needs-* annotation reflecting downstream artifact state
  - Dependencies on other features (if any)
  - Status: all features start as "Not Started"
- **Sequencing**: Draw from the sequencing analyst's findings. Explain ordering
  rationale -- why this order and not another. Acknowledge parallelization
  opportunities.
- **Dependencies**: Draw from the dependency validator's findings. Include both
  intra-roadmap and external dependencies.

**Minimum feature count:** The roadmap must contain at least 2 features. If Phase 2
reduced the list below 2, flag this to the user -- single-feature work doesn't need
a roadmap.

**All features start as "Not Started."** The roadmap is a plan, not a progress
tracker at creation time. Features move through statuses as work proceeds.

### 3.3 Present the Draft

Tell the user the draft is ready and provide the file path so they can read it:

> The ROADMAP draft is at `docs/roadmaps/ROADMAP-<topic>.md`. Take a look when you're
> ready -- I have some questions about sequencing and dependencies below.

Don't summarize each section or walk through the doc asking "does this look right?"
The user can read the doc themselves.

### 3.4 Surface Open Questions and Decisions

Use AskUserQuestion to raise thematic questions the user needs to weigh in on. Focus
on sequencing trade-offs, dependency decisions, and feature scope where the research
pointed in multiple directions.

Read `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for how to structure
decisions. Frame interactions as the agent recommending based on evidence, not
neutrally presenting options.

Good questions target sequencing and coordination:
- "Features A and B have no mutual dependency. Should they be parallelized, or is
  there a resource constraint that forces sequential delivery?"
- "The dependency validator found that Feature C depends on an external API that
  doesn't exist yet. Should we add that as a blocking dependency or plan Feature C
  to work with a stub?"
- "Feature D could be split into D1 (core) and D2 (polish). D1 unblocks Feature E
  earlier. Worth the split?"

Bad questions rehash doc structure:
- "Does the feature list look complete?"
- "Is the sequencing right?"
- "Do the dependencies look correct?"

If the draft has no genuine open questions (features were clear, dependencies were
confirmed), say so and ask if the user has any feedback after reading the draft.

### 3.5 Incorporate Feedback

After the user responds, incorporate their feedback:

- **Minor changes** (wording, adjusting a needs-* label, clarifying a dependency):
  Apply directly and confirm what changed.
- **Significant changes** (adding/removing features, reordering sequence, changing
  dependencies): Apply changes, tell the user what was updated, and ask if the
  changes landed correctly. Focus on the changed areas only -- don't re-review the
  whole doc.

### 3.6 Loop Back Decision

If the review reveals significant gaps:

- **Missing features or dependencies**: Loop back to Phase 2 with specific
  investigation targets. Don't re-run the full discovery -- target only the gaps.
- **Wrong theme**: Loop back to Phase 1 if the theme itself needs reworking. This
  should be rare -- if Phase 1 checkpoint worked, the theme should be solid.

If the user is satisfied, proceed to Phase 4.

### 3.7 Commit Draft

After incorporating all feedback, commit the ROADMAP:

```
docs(roadmap): draft ROADMAP for <topic>
```

## Quality Checklist

Before proceeding:
- [ ] ROADMAP draft written to `docs/roadmaps/ROADMAP-<topic>.md` with status "Draft"
- [ ] All features present with rationale, needs-* annotation, dependencies, and
      "Not Started" status
- [ ] At least 2 features in the roadmap
- [ ] Sequencing rationale explains ordering, not just lists features
- [ ] Dependencies include both intra-roadmap and external
- [ ] No downstream content (requirements, architecture, implementation details)
- [ ] No dates or deadlines

## Artifact State

After this phase:
- ROADMAP draft at `docs/roadmaps/ROADMAP-<topic>.md` with status "Draft"
- Scope document still at `wip/roadmap_<topic>_scope.md`
- Phase 2 research files still at `wip/research/roadmap_<topic>_phase2_*.md`

## Next Phase

Proceed to Phase 4: Validate (`phase-4-validate.md`)
