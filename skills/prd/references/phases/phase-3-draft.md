# Phase 3: Draft

Produce a complete PRD draft, surface open questions, and refine based on user feedback.

## Goal

Transform the scope and research findings into a complete PRD, then surface thematic
questions and trade-offs for the user to weigh in on. By the end of this phase, the PRD
draft should reflect the user's intent accurately.

## Resume Check

If `docs/prds/PRD-<topic>.md` exists with status "Draft", offer to continue
refining from where it left off.

## Approach: Draft-Then-Review

Produce a complete first draft, then present it for thematic feedback. This is more
efficient than co-authoring section by section because:
- The user sees the whole picture before giving feedback
- Cross-references between sections (requirements to acceptance criteria) are consistent
- The agent can apply research findings holistically rather than piecemeal

### 3.1 Gather Inputs

Read all available context:
- `wip/prd_<topic>_scope.md` (from Phase 1)
- `wip/research/prd_<topic>_phase2_*.md` files (from Phase 2, if they exist)
- Any notes from Phase 2 synthesis

**Detect upstream:** Check `$ARGUMENTS` for an `--upstream <path>` flag. If
present, store the path for inclusion in frontmatter (step 3.2). The upstream
path typically points to a Roadmap document when the PRD is part of a
multi-feature initiative. If `--upstream` is not provided, omit the field
from frontmatter.

**Validate upstream:** If a path was detected, run these checks in order
before storing it. These are hard-stops -- do not write a failing value into
frontmatter:

1. **Is the path under `wip/`?** STOP. wip/ paths are non-durable and would
   leave the PRD's `upstream:` orphaned after wip-hygiene cleanup. Resolve
   the canonical location and use that path instead, or OMIT the field.
2. **Does the path resolve in this repo?** Run `git ls-files <path>`. If
   non-empty, the upstream is durable -- continue.
3. **Path is out-of-repo?** Detect this repo's visibility from CLAUDE.md
   (`## Repo Visibility:`). If public AND the canonical upstream lives in a
   private repo, STOP and OMIT the `upstream:` field. Public artifacts must
   not reference private resources. See
   `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` for the
   visibility-direction table and the cross-repo `owner/repo:path` syntax for
   allowed cases (public->public, private->public, private->private).

When omitting the field, optionally describe the source-context in prose in
the PRD body's Problem Statement section, without naming a private path or
repo.

### 3.2 Draft the PRD

Write a complete PRD draft following the `prd` skill structure. Use the Write tool to
create `docs/prds/PRD-<topic>.md`.

**Drafting guidelines:**
- **Problem Statement**: Draw from Phase 1 scope. Be specific about who and why now.
- **Goals**: Distill from the scope's success criteria. High-level outcomes only.
- **User Stories**: Create 3-5 stories covering the primary scenarios. Use real role names
  from the problem space, not generic "user."
- **Requirements**: Number them R1, R2, etc. Draw from both the scope and research
  findings. Separate functional from non-functional. Each requirement should be testable.
- **Acceptance Criteria**: Derive from requirements. Each criterion is binary pass/fail.
  Cover happy path and important edge cases.
- **Out of Scope**: Include items from the scope document plus anything the research
  revealed should be excluded.
- **Open Questions**: Include any unresolved items from research synthesis.
- **Known Limitations**: Include trade-offs identified during research.
- **Decisions and Trade-offs**: Populate from Phase 2 research findings. For each
  decision recorded during discovery, state what was decided, what alternatives
  existed, and why the chosen option won. Include decisions made during this
  drafting phase as well.

Set frontmatter status to "Draft". If an `--upstream` path was detected AND
passed validation in step 3.1, include `upstream: <path>` in frontmatter.
Otherwise omit the field.

### 3.3 Present the Draft

Tell the user the draft is ready and provide the file path so they can read it:

> The PRD draft is at `docs/prds/PRD-<topic>.md`. Take a look when you're ready --
> I have some questions about trade-offs and open decisions below.

Don't summarize each section or walk through the doc asking "does this look right?"
The user can read the doc themselves.

### 3.4 Surface Open Questions and Decisions

Use AskUserQuestion to raise thematic questions the user needs to weigh in on. Focus
on trade-offs, ambiguous scope boundaries, and decisions where the research pointed
in multiple directions.

Read `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for how to structure decisions.
Frame interactions as the agent recommending based on evidence, not neutrally
presenting options. Pick the best option, say why, and let the user override.

For each question, provide:
- A paragraph of context explaining the question and why it matters
- A recommended answer with justification
- Alternative answers with justifications

Good questions target themes and trade-offs:
- "Should R3 (offline support) be a hard requirement or a nice-to-have? The research
  found it doubles implementation scope."
- "The codebase analyst found two patterns for this. Which aligns better with your
  long-term direction?"
- "Requirements R5 and R8 create tension -- satisfying both requires X. Should we
  prioritize one over the other?"

Bad questions rehash doc structure:
- "Does the problem statement capture your intent?"
- "Are these the right user stories?"
- "Does the out-of-scope list look correct?"

If the draft has no genuine open questions (scope was clear, research was conclusive),
say so and ask if the user has any feedback after reading the draft.

### 3.5 Incorporate Feedback

After the user responds, incorporate their feedback:

- **Minor changes** (wording, additional criteria, scope adjustments): Apply directly
  and confirm what changed.
- **Significant changes** (new requirements, changed scope, removed stories): Apply
  changes, tell the user what was updated, and ask if the changes landed correctly.
  Focus on the changed areas only -- don't re-review the whole doc.

### 3.6 Loop Back Decision

If the review reveals significant gaps:

- **Missing research**: Loop back to Phase 2 with new specific leads. Don't re-run
  the full discovery -- target only the gaps.
- **Wrong scope**: Loop back to Phase 1 if the problem statement itself needs reworking.
  This should be rare -- if Phase 1 checkpoint worked, the scope should be solid.

If the user is satisfied, proceed to Phase 4.

### 3.7 Decision Review Checkpoint

Before finalizing, scan `wip/` artifacts (scope document, Phase 2 research files,
conversation history) for decisions that were made but not captured in the PRD's
Decisions and Trade-offs section. Common gaps:

- Scope narrowing choices from Phase 1 that shaped requirements
- Research findings where one approach was chosen over another
- Trade-offs resolved during 3.4/3.5 feedback that aren't recorded

If the PRD has no Decisions and Trade-offs section and no decisions were made
during the workflow, that's fine -- the section is optional. But if decisions
exist in the artifacts and aren't reflected in the PRD, add them now.

### 3.8 Commit Draft

After incorporating all feedback, commit the PRD:

```
docs(prd): draft PRD for <topic>
```

## Quality Checklist

Before proceeding:
- [ ] PRD draft written to `docs/prds/PRD-<topic>.md` with status "Draft"
- [ ] All sections present (Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope)
- [ ] Requirements are numbered (R1, R2, ...) and each is testable

## Artifact State

After this phase:
- PRD draft at `docs/prds/PRD-<topic>.md` with status "Draft"
- Scope document still at `wip/prd_<topic>_scope.md`
- Phase 2 research files still at `wip/research/prd_<topic>_phase2_*.md` (if created)

## Next Phase

Proceed to Phase 4: Validate (`phase-4-validate.md`)
