# Phase 1: Scope

Conversational scoping to understand the roadmap's theme, features, dependencies,
and sequencing constraints, producing candidate features for Phase 2.

## Goal

Develop a shared understanding of WHAT this roadmap coordinates and WHY the features
belong together. By the end of this phase you should have: a clear theme, an initial
feature list (at least one), dependency sketch, sequencing constraints, and downstream
artifact state for each feature.

## Roadmap Issues Preference

Resolve the `## Roadmap Issues:` preference once, here in setup, alongside the
`## Execution Mode:` read. Grep CLAUDE.md for the `## Roadmap Issues:` header and
take the value after the colon. The value is `optional` only when it reads exactly
`optional`; absent header or any unrecognized value resolves to `required`
(fail-closed toward the issue-creating, human-gated path). Record the resolved
value (`optional` or `required`) in the run's context -- the populate phase reads it
to decide whether issues get created and whether the R14 approval gate applies. The
validator never reads this header; it's a skill-only preference.

## Resume Check

If key `work/scope.md` exists in `roadmap-<topic>` and this is NOT a loop-back from
Phase 2, skip to Phase 2.

If this IS a loop-back (Phase 2 determined the theme or feature list was fundamentally
wrong), remove it first (`koto context remove roadmap-<topic> work/scope.md`), then re-scope
from scratch.

Under /charter (`dispatch read` printed `parent=charter-<topic>`), read the scope
/charter left with `koto context get charter-<topic> chain/roadmap-scope`, record it as
`work/scope.md` in `roadmap-<topic>` (`koto context add roadmap-<topic> work/scope.md`,
content on stdin), and continue at Phase 2. On a loop-back, do not re-read it: the
theme or feature list was found wrong, so re-scope from scratch. When `dispatch read`
names another child or matches no parent, ignore `chain/roadmap-scope` entirely and
scope as a direct run does. Nothing pre-populates a scope file on disk; scoping is
settled once `work/scope.md` exists, so the run continues at Phase 2.

## Approach: Conversational with Coverage Tracking

Ask open-ended questions, adapting to what the user already knows. Internally track
coverage of the dimensions below -- don't present them as a checklist to the user, but
weave them into the conversation naturally. Circle back to gaps when appropriate.

### Coverage Dimensions (tracked internally)

| Dimension | What to understand |
|-----------|-------------------|
| Theme clarity | What initiative ties these features together? Why is this one tracked initiative rather than unrelated independent work? |
| Feature identification | What are the features? Are any missing? Is each one independently describable at PRD level? |
| Outcome and evidence | For each candidate, who can do what end to end once it lands, that they couldn't before? Who would check that, from what starting state, and what would they see? An answer that names a merge, a test run or a component is mechanism; ask again for the outcome. |
| Dependency awareness | Which features depend on each other? Are there external dependencies outside this roadmap? |
| Sequencing constraints | What must come first? Are constraints hard blockers or soft preferences? What can run in parallel? |
| Downstream artifact state | What does each feature need next? Which have PRDs, designs, or implementations already? What needs-* labels apply? |
| Scope boundaries | What work is in this roadmap? What's deliberately excluded, and why? |

### Conversation Guidelines

- **Start broad**: "What's the theme behind this roadmap?" or build on the topic
  from `$ARGUMENTS`
- **Follow the user's energy**: If they're passionate about a specific feature or
  constraint, explore it before circling back to gaps
- **Don't front-load decisions**: This phase produces candidate features, not a
  final sequence
- **Identify uncertainty**: Note areas where the user says "I'm not sure" or "maybe" --
  these become investigation targets for Phase 2
- **Use concrete examples**: Ask for scenarios ("Walk me through what happens if
  feature X ships before feature Y") to ground abstract dependencies
- **2-4 questions per turn**: Don't overwhelm. Group related questions naturally.
- **Probe for missing features, don't demand a second one**: If the user describes
  only one feature, ask what else fits the theme -- gaps are common at this stage.
  But a strategy whose work genuinely is one feature gets a one-feature roadmap,
  which is a legitimate progress ledger and the only bridge into `/scope`. Don't
  push the user to invent a second feature to clear a bar that doesn't exist.

### When to Stop Scoping

Stop when you have enough to brief a research team. Signals:
- All 6 dimensions have at least surface coverage
- You have at least one candidate feature with a rough description, and probing
  for more is no longer turning any up
- Dependencies and sequencing constraints are sketched (even if not final)
- The user isn't revealing new features or constraints with additional questions
- The theme feels clear enough to test (even if feature details need refinement)

Don't over-scope. Phase 2 discovers things you can't anticipate here.

## 1.1 Checkpoint

Before investing in research, present your understanding to the user. This is a
lightweight informational checkpoint, not a formal review.

Present:
1. **Theme statement** (2-3 sentences): What initiative, why coordination matters
2. **Candidate milestones** (numbered list): Each with a 1-sentence rationale,
   the outcome someone can exercise, and a sketch of the evidence that would
   show it
3. **Dependency sketch**: Known dependencies between features
4. **Sequencing notes**: Hard blockers vs soft preferences, parallelization potential

The user can interject at any point to course-correct if something looks off.
Proceed to persist scope and move to Phase 2.

## 1.2 Persist Scope

Write the scoping output to key `work/scope.md` in `roadmap-<topic>` (`koto context add`, content on stdin):

```markdown
# /roadmap Scope: <topic>

## Theme Statement
<2-3 sentences: what initiative, why coordination matters>

## Initial Scope
### This Roadmap Covers
- <capability area>

### This Roadmap Does NOT Cover
- <excluded work with reasoning>

## Candidate Features
1. <feature>: <rationale>
   - Outcome: <who can do what, end to end, that they couldn't before>
   - Evidence: <who checks, from what starting state, what they see>
2. <feature>: <rationale>
   - Outcome: <...>
   - Evidence: <...>

## Dependency Sketch
- <feature A> depends on <feature B>: <reason>

## Sequencing Constraints
- Hard: <constraint with reasoning>
- Soft: <preference with reasoning>

## Downstream Artifact State
- <feature>: <needs-prd | needs-design | needs-implementation | etc.>

## Coverage Notes
<Gaps or uncertainties for Phase 2 to resolve>
```

Commit: `docs(roadmap): capture scope for <topic>`

## Quality Checklist

Before proceeding:
- [ ] All 6 coverage dimensions have at least surface coverage
- [ ] At least one candidate feature identified
- [ ] Each feature is independently describable (not a sub-task of another)
- [ ] Dependencies sketched, even if approximate
- [ ] Downstream artifact state noted for each feature

## Artifact State

After this phase:
- Scope document at key `work/scope.md` in `roadmap-<topic>`
- No ROADMAP draft yet
- No research files yet

## Next Phase

Proceed to Phase 2: Discover (`phase-2-discover.md`)
