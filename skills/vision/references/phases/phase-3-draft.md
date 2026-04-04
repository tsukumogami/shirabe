# Phase 3: Draft

Produce a complete VISION draft from scope and research findings, then refine with
the user.

## Goal

Transform the thesis direction and research findings into a complete VISION document,
then surface open questions and trade-offs for the user to weigh in on. By the end of
this phase, the VISION draft should capture the project's strategic justification
accurately.

## Resume Check

If `docs/visions/VISION-<topic>.md` exists with status "Draft", offer to continue
refining from where it left off.

## Approach: Draft-Then-Review

Produce a complete first draft, then present it for thematic feedback. The user sees
the whole picture before giving feedback, and cross-references between sections
(thesis to success criteria, value proposition to org fit) stay consistent.

### 3.1 Gather Inputs

Read all available context:
- `wip/vision_<topic>_scope.md` (from Phase 1)
- `wip/research/vision_<topic>_phase2_*.md` files (from Phase 2, if they exist)
- Any notes from Phase 2 synthesis
- `skills/vision/references/vision-format.md` (format specification)

Detect repo visibility before drafting. Load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

### 3.2 Draft the VISION

Write a complete VISION draft following `references/vision-format.md`. Use the Write
tool to create `docs/visions/VISION-<topic>.md`.

**Section-by-section guidance:**

- **Frontmatter**: Set `status: Draft`. Write the `thesis` field. Set `scope` to
  `org` or `project` based on Phase 1 scoping. Include `upstream` only for
  project-level VISIONs with a parent.
- **Status**: "Draft"
- **Thesis**: Synthesize from Phase 1's thesis direction and Phase 2's research
  findings. Must be a hypothesis: "We believe [audience] needs [capability] because
  [insight]." If the research shifted the thesis from the original scope, use the
  updated version. The thesis is a bet -- write it as something that can be
  invalidated.
- **Audience**: Draw from audience validator findings (Phase 2). Describe the
  audience's current situation, not just a label. Include what they do today and
  what friction they face.
- **Value Proposition**: Draw from value proposition analyst findings (Phase 2).
  State the category of value, not a feature list. One level above features --
  what changes for the audience?
- **Competitive Positioning** (private repos only): Draw from competitive landscape
  analyst findings. Name alternatives, explain differentiation. Skip this section
  entirely in public repos.
- **Resource Implications** (private repos only): If Phase 2 surfaced investment or
  opportunity cost evidence, include it. Skip in public repos.
- **Org Fit**: Draw from org fit researcher findings. Explain why this project
  belongs here -- what existing capabilities or positioning does it build on?
  What would be lost if it were standalone?
- **Success Criteria**: Draw from success criteria researcher findings. Project-level
  outcomes that validate the thesis. Adoption rates, ecosystem signals, quality
  indicators. Not feature acceptance criteria.
- **Non-Goals**: Draw from Phase 1's scope boundaries. Each non-goal should explain
  WHY this project won't do something, tying back to the thesis. Non-goals are about
  identity, not just scope.
- **Open Questions**: Include any unresolved items from Phase 2 synthesis.

### 3.3 Present the Draft

Tell the user the draft is ready and provide the file path so they can read it:

> The VISION draft is at `docs/visions/VISION-<topic>.md`. Take a look when you're
> ready -- I have some questions about positioning and trade-offs below.

Don't summarize each section or walk through the doc asking "does this look right?"
The user can read the doc themselves.

### 3.4 Surface Open Questions and Decisions

Use AskUserQuestion to raise thematic questions the user needs to weigh in on. Focus
on thesis framing, strategic trade-offs, and positioning decisions where the research
pointed in multiple directions.

Read `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for how to structure
decisions. Frame interactions as the agent recommending based on evidence, not
neutrally presenting options.

Good questions target thesis and positioning:
- "The research found two distinct audiences for this. Should the thesis target
  [audience A] or [audience B]? Here's what the evidence says about each..."
- "Org fit is strongest with [project X], but the value proposition overlaps with
  [project Y]. Should we sharpen the boundary or reframe the relationship?"
- "Success criteria S3 (community contributions) is hard to measure in the first 6
  months. Should we keep it as an aspirational signal or replace it with something
  more immediate?"

Bad questions rehash doc structure:
- "Does the thesis capture your intent?"
- "Is the audience description accurate?"
- "Do the non-goals look right?"

If the draft has no genuine open questions (thesis was clear, research was conclusive),
say so and ask if the user has any feedback after reading the draft.

### 3.5 Incorporate Feedback

After the user responds, incorporate their feedback:

- **Minor changes** (wording, clarifying a non-goal, adjusting a success criterion):
  Apply directly and confirm what changed.
- **Significant changes** (thesis reframing, audience shift, new non-goals): Apply
  changes, tell the user what was updated, and ask if the changes landed correctly.
  Focus on the changed areas only -- don't re-review the whole doc.

### 3.6 Loop Back Decision

If the review reveals significant gaps:

- **Missing research**: Loop back to Phase 2 with new specific leads. Don't re-run
  the full discovery -- target only the gaps.
- **Wrong thesis**: Loop back to Phase 1 if the thesis direction itself needs
  reworking. This should be rare -- if Phase 1 checkpoint worked, the direction
  should be solid.

If the user is satisfied, proceed to Phase 4.

### 3.7 Commit Draft

After incorporating all feedback, commit the VISION:

```
docs(vision): draft VISION for <topic>
```

## Quality Checklist

Before proceeding:
- [ ] VISION draft written to `docs/visions/VISION-<topic>.md` with status "Draft"
- [ ] All required sections present (Status, Thesis, Audience, Value Proposition,
      Org Fit, Success Criteria, Non-Goals)
- [ ] Thesis is a hypothesis, not a problem statement
- [ ] Success criteria are project-level outcomes, not feature metrics
- [ ] Non-goals include reasoning tied to the thesis
- [ ] Visibility-gated sections handled correctly (no Competitive Positioning or
      Resource Implications in public repos)

## Artifact State

After this phase:
- VISION draft at `docs/visions/VISION-<topic>.md` with status "Draft"
- Scope document still at `wip/vision_<topic>_scope.md`
- Phase 2 research files still at `wip/research/vision_<topic>_phase2_*.md` (if created)

## Next Phase

Proceed to Phase 4: Validate (`phase-4-validate.md`)
