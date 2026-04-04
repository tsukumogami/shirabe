# Phase 4: Validate

Three-agent jury review followed by finalization and user approval.

## Goal

Validate the VISION draft through independent review by three specialist agents, fix
any issues found, then finalize the VISION with the user.

## Resume Check

If `wip/research/vision_<topic>_phase4_*.md` files exist, skip to step 4.3
(Process Feedback).

## Approach: 3-Agent Jury

Launch 3 agents with fixed roles. Each evaluates the VISION from a different quality
dimension, all specific to what makes a VISION document effective.

### 4.1 Launch Jury Agents

Load `skills/vision/references/vision-format.md` and pass the relevant quality
guidance to each agent.

Launch all 3 agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The VISION draft (read from `docs/visions/VISION-<topic>.md`)
- Their role and evaluation criteria
- The scope document (`wip/vision_<topic>_scope.md`) for reference

#### Thesis Quality Reviewer

```
You are reviewing a VISION document for thesis quality and strategic coherence.
Your job is to test whether the thesis is a genuine hypothesis and whether the
rest of the document supports it.

## VISION to Review
[Contents of docs/visions/VISION-<topic>.md]

## Original Scope
[Contents of wip/vision_<topic>_scope.md]

## Quality Guidance
[Relevant sections from vision-format.md]

## Evaluate
1. Is the thesis a hypothesis ("We believe...because...") or a problem statement
   ("The problem is...")? A VISION thesis is a bet -- it must be something that
   can be invalidated.
2. Does the audience description capture their current situation, or is it just
   a label? "Backend engineers" is too thin. "Backend engineers at mid-size
   companies managing 10+ microservices who currently maintain ad-hoc install
   scripts" tells you something.
3. Is the value proposition a category of value, or a feature list? "Reduce the
   operational burden of managing developer tool installations" vs "provides a
   CLI with install, update, and remove commands."
4. Does org fit explain why HERE and not elsewhere? What would be lost if this
   project were standalone?
5. Do the thesis, audience, value proposition, and org fit tell a coherent story?
   Or could you swap the thesis and the document would still make sense (meaning
   it's too generic)?

## Output Format
Write your full review to `wip/research/vision_<topic>_phase4_thesis-quality.md`:

# Thesis Quality Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Content Boundary Reviewer

```
You are reviewing a VISION document for content boundary violations. Your job is
to catch content that belongs in downstream artifacts (PRDs, designs, roadmaps,
plans) rather than in a VISION.

## VISION to Review
[Contents of docs/visions/VISION-<topic>.md]

## Content Boundaries (from format reference)
VISION does NOT contain:
- Feature requirements or user stories (belongs in a PRD)
- Feature sequencing or timelines (belongs in a Roadmap)
- Technical architecture decisions (belongs in a Design Doc)
- Implementation tasks (belongs in a Plan)
- Full competitive analysis (separate artifact; VISION can reference positioning
  but not duplicate analysis)

## Evaluate
1. Does any section contain feature lists, user stories, or specific requirements?
   These belong in a PRD.
2. Does the document mention timelines, phases, or delivery sequences? These
   belong in a Roadmap.
3. Does the document make technical architecture decisions or specify
   implementation approaches? These belong in a Design Doc.
4. Do success criteria measure features rather than project-level outcomes?
   "Install command exits with code 0" is a feature metric. "10 recipes
   contributed by external users within 6 months" is a project outcome.
5. Are non-goals about identity ("not a system package manager because...") or
   just scope exclusions ("doesn't support Windows")? VISION non-goals should
   explain WHY, tying back to the thesis.

## Output Format
Write your full review to `wip/research/vision_<topic>_phase4_content-boundary.md`:

# Content Boundary Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Violations Found
1. <section>: <the offending content> -> <which artifact type it belongs in> ->
   <what to replace it with in the VISION>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, violation count, and summary to this conversation.
```

#### Section Guidance Reviewer

```
You are reviewing a VISION document for compliance with per-section quality
guidance. Your job is to check each section against its specific quality criteria.

## VISION to Review
[Contents of docs/visions/VISION-<topic>.md]

## Per-Section Quality Criteria

- **Thesis**: Must be a hypothesis, not a problem statement. Format: "We believe
  [audience] needs [capability] because [insight]." If it reads like "The problem
  is..." it's wrong.
- **Audience**: Describe the audience's current situation, not just a label.
  Include what they do today and what friction they face.
- **Value Proposition**: State the category of value, not a feature list. One
  level above features.
- **Org Fit**: Explain why HERE and not elsewhere. What existing capabilities
  does it build on? What would be lost standalone?
- **Success Criteria**: Project-level outcomes, not feature acceptance criteria.
  Adoption rates, ecosystem signals, quality indicators.
- **Non-Goals**: About identity, not scope. Each non-goal should explain WHY,
  tying back to the thesis.

## Also Check
- Frontmatter `status` matches the body Status section
- Visibility-gated sections: Competitive Positioning and Resource Implications
  must NOT appear in public repos. Check the repo visibility.
- Open Questions section is allowed only in Draft status

## Output Format
Write your full review to `wip/research/vision_<topic>_phase4_section-guidance.md`:

# Section Guidance Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <section>: <what's wrong> -> <what the guidance says> -> <suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

### 4.2 Collect Results

Wait for all 3 agents to complete. Read their summaries.

### 4.3 Process Feedback

**Reference**: Full review details available in `wip/research/vision_<topic>_phase4_*.md`.

Determine consensus:

| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, briefly show fixes to user, proceed |
| Any fail with significant issues | Present issues to user, incorporate fixes, re-validate if changes are substantial |
| Agents disagree on same issue | Present both perspectives to user, let user decide |

**For minor issues** (wording fixes, sharpening a non-goal's reasoning, clarifying
audience description): Fix directly, update the VISION, show the user what changed.

**For significant issues** (thesis is a problem statement not a hypothesis, feature
lists in the value proposition, success criteria measuring features not outcomes):
Present the jury's findings to the user with specific recommendations. Use
AskUserQuestion when the findings surface trade-offs or decisions. If changes are
substantial (thesis reframing, section rewrites), loop back to Phase 3 step 3.5.

### 4.4 Finalize VISION

After all issues are resolved:

1. Update the VISION with all fixes
2. Verify the VISION passes the format reference's validation rules
3. Commit: `docs(vision): finalize VISION for <topic>`

### 4.5 Present to User

Present a brief summary:
- Thesis (1 sentence)
- Audience (1 sentence)
- Success criteria count
- Any known open questions remaining

Use AskUserQuestion to ask for approval. Provide context explaining the VISION is
validated and ready for acceptance. Options:
- **Approve** -- status changes to Accepted, ready for downstream work
- **Request changes** -- specify what needs to change

### 4.6 Handle Approval

**If user approves:**
1. Update VISION status from "Draft" to "Accepted" (both frontmatter and Status section)
2. Remove or empty the Open Questions section (if present)
3. Commit: `docs(vision): accept VISION for <topic>`
4. Create PR (or update existing PR if on a shared branch)

Then present routing options:

"The VISION is accepted. Based on the project's needs, here are the recommended
next steps:"

| Situation | Suggestion |
|-----------|-----------|
| Clear feature scope already | /prd to write requirements |
| Multiple directions possible | /explore to investigate further |
| Needs organizational alignment | Share VISION for stakeholder review |

**If user wants changes:**
Return to Phase 3 step 3.5 to incorporate the specific feedback. Don't re-walk
the entire doc -- focus on the areas the user identified.

### 4.7 Cleanup

After the PR is created, clean up temporary artifacts:

```bash
rm -f wip/vision_<topic>_scope.md
rm -f wip/research/vision_<topic>_phase2_*.md
rm -f wip/research/vision_<topic>_phase4_*.md
```

Commit: `chore(vision): clean up working artifacts`

## Quality Checklist

- [ ] All 3 jury agents reviewed the VISION
- [ ] All issues from jury review are resolved
- [ ] User has approved the VISION

## Artifact State

Final VISION at `docs/visions/VISION-<topic>.md` with:
- YAML frontmatter with status "Accepted"
- All required sections complete and validated
- Working artifacts cleaned up (scope doc, research files removed)
